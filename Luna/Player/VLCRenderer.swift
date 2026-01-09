//
//  VLCRenderer.swift
//  Luna
//
//  VLC player renderer using MobileVLCKit for GPU-accelerated playback
//  iOS-only implementation - tvOS uses MPV (conditional compilation)
//

import UIKit
import AVFoundation

// MARK: - Compatibility: VLC renderer is iOS-only (tvOS uses MPV)
// Use canImport to gracefully handle when MobileVLCKit is not available
#if os(iOS) && canImport(MobileVLCKit)
import MobileVLCKit

// Log that we're using real VLC implementation
private let _ = {
    print("[VLCRenderer] ✓ Using REAL iOS VLC implementation with MobileVLCKit")
    return true
}()

protocol VLCRendererDelegate: AnyObject {
    func renderer(_ renderer: VLCRenderer, didUpdatePosition position: Double, duration: Double)
    func renderer(_ renderer: VLCRenderer, didChangePause isPaused: Bool)
    func renderer(_ renderer: VLCRenderer, didChangeLoading isLoading: Bool)
    func renderer(_ renderer: VLCRenderer, didBecomeReadyToSeek: Bool)
    func renderer(_ renderer: VLCRenderer, getSubtitleForTime time: Double) -> NSAttributedString?
    func renderer(_ renderer: VLCRenderer, getSubtitleStyle: Void) -> SubtitleStyle
    func renderer(_ renderer: VLCRenderer, subtitleTrackDidChange trackId: Int)
    func rendererDidChangeTracks(_ renderer: VLCRenderer)
}

final class VLCRenderer: NSObject {
    enum RendererError: Error {
        case vlcInitializationFailed
        case mediaCreationFailed
    }
    
    private let displayLayer: AVSampleBufferDisplayLayer
    private let eventQueue = DispatchQueue(label: "vlc.renderer.events", qos: .utility)
    private let stateQueue = DispatchQueue(label: "vlc.renderer.state", attributes: .concurrent)
    
    // VLC rendering container
    private let vlcView: UIView
    
    private var vlcInstance: VLCMediaList?
    private var mediaPlayer: VLCMediaPlayer?
    private var currentMedia: VLCMedia?
    
    private var isPaused: Bool = true
    private var isLoading: Bool = false
    private var isReadyToSeek: Bool = false
    private var cachedDuration: Double = 0
    private var cachedPosition: Double = 0
    private var pendingAbsoluteSeek: Double?
    private var currentURL: URL?
    private var currentHeaders: [String: String]?
    private var currentPreset: PlayerPreset?
    private var isRunning = false
    private var isStopping = false
    private var currentPlaybackSpeed: Double = 1.0
    
    // VLC-exclusive features
    private var preferredAudioLanguage: String = "en"
    private var autoLoadSubtitles: Bool = true
    private var animeAudioLanguage: String = "ja"
    
    weak var delegate: VLCRendererDelegate?
    
    init(displayLayer: AVSampleBufferDisplayLayer) {
        self.displayLayer = displayLayer
        self.vlcView = UIView()
        super.init()
        setupVLCView()
    }
    
    deinit {
        stop()
    }
    
    // MARK: - View Setup
    
    private func setupVLCView() {
        vlcView.backgroundColor = .black
        vlcView.contentMode = .scaleAspectFit
        vlcView.layer.contentsGravity = .resizeAspect
        vlcView.layer.isOpaque = true
        vlcView.clipsToBounds = true
        vlcView.isUserInteractionEnabled = false
    }
    
    /// Return the VLC view to be added to the view hierarchy
    func getRenderingView() -> UIView {
        return vlcView
    }
    
    // MARK: - Lifecycle
    
    func start() throws {
        guard !isRunning else { 
            Logger.shared.log("[VLCRenderer.start] Already running, returning", type: "Stream")
            return 
        }
        
        Logger.shared.log("[VLCRenderer.start] INITIALIZING VLCMediaPlayer", type: "Stream")
        
        mediaPlayer = VLCMediaPlayer()
        guard let mediaPlayer = mediaPlayer else {
            Logger.shared.log("[VLCRenderer.start] FAILED: VLCMediaPlayer() returned nil", type: "Error")
            throw RendererError.vlcInitializationFailed
        }
        
        Logger.shared.log("[VLCRenderer.start] VLCMediaPlayer created successfully", type: "Stream")
        Logger.shared.log("[VLCRenderer.start] Setting drawable to vlcView (\(vlcView))", type: "Stream")
        
        // Attach to view for rendering
        mediaPlayer.drawable = vlcView
        Logger.shared.log("[VLCRenderer.start] drawable set, vlcView class: \(type(of: vlcView))", type: "Stream")
        
        // Setup event handlers with @objc selectors
        Logger.shared.log("[VLCRenderer.start] Registering notification observers", type: "Stream")
        NotificationCenter.default.addObserver(
            self,
            selector: #selector(mediaPlayerTimeChanged),
            name: NSNotification.Name(rawValue: VLCMediaPlayerTimeChanged),
            object: mediaPlayer
        )
        Logger.shared.log("[VLCRenderer.start] Registered timeChanged observer", type: "Stream")
        
        NotificationCenter.default.addObserver(
            self,
            selector: #selector(mediaPlayerStateChanged),
            name: NSNotification.Name(rawValue: VLCMediaPlayerStateChanged),
            object: mediaPlayer
        )
        Logger.shared.log("[VLCRenderer.start] Registered stateChanged observer", type: "Stream")
        
        // Observe app lifecycle
        NotificationCenter.default.addObserver(
            self,
            selector: #selector(handleAppDidEnterBackground),
            name: UIApplication.didEnterBackgroundNotification,
            object: nil
        )
        NotificationCenter.default.addObserver(
            self,
            selector: #selector(handleAppWillEnterForeground),
            name: UIApplication.willEnterForegroundNotification,
            object: nil
        )
        
        isRunning = true
        Logger.shared.log("[VLCRenderer.start] VLCRenderer FULLY INITIALIZED", type: "Stream")
    }
    
    func stop() {
        guard isRunning && !isStopping else { return }
        isStopping = true
        
        stateQueue.async(flags: .barrier) { [weak self] in
            self?.mediaPlayer?.stop()
            self?.mediaPlayer = nil
            self?.currentMedia = nil
            self?.isRunning = false
            self?.isStopping = false
        }
    }
    
    // MARK: - Media Loading
    
    func loadMedia(url: URL, headers: [String: String]? = nil, preset: PlayerPreset? = nil) {
        Logger.shared.log("[VLCRenderer.loadMedia] Starting load with URL: \(url.absoluteString)", type: "Stream")
        Logger.shared.log("[VLCRenderer.loadMedia] Headers count: \(headers?.count ?? 0)", type: "Stream")
        if let headers = headers {
            for (k, v) in headers {
                Logger.shared.log("[VLCRenderer.loadMedia] Header - \(k): \(v.prefix(50))...", type: "Stream")
            }
        }
        
        currentURL = url
        currentPreset = preset
        currentHeaders = headers ?? [:]
        
        isLoading = true
        isReadyToSeek = false
        DispatchQueue.main.async { [weak self] in
            guard let self else { return }
            self.delegate?.renderer(self, didChangeLoading: true)
        }
        
        eventQueue.async { [weak self] in
            guard let self, let player = self.mediaPlayer else {
                Logger.shared.log("[VLCRenderer.loadMedia] ERROR: mediaPlayer is nil in eventQueue", type: "Error")
                return
            }
            
            Logger.shared.log("[VLCRenderer.loadMedia] Creating VLCMedia with URL", type: "Stream")
            // Keep the URL untouched; apply headers via VLC media options
            let media = VLCMedia(url: url)
            if let headers = self.currentHeaders, !headers.isEmpty {
                Logger.shared.log("[VLCRenderer.loadMedia] Applying \(headers.count) headers to VLCMedia", type: "Stream")
                // Prefer dedicated options when available (unquoted to match server expectations)
                if let ua = headers["User-Agent"], !ua.isEmpty {
                    Logger.shared.log("[VLCRenderer.loadMedia] Setting User-Agent", type: "Stream")
                    media.addOption(":http-user-agent=\(ua)")
                }
                if let referer = headers["Referer"], !referer.isEmpty {
                    Logger.shared.log("[VLCRenderer.loadMedia] Setting Referer", type: "Stream")
                    media.addOption(":http-referrer=\(referer)")
                    // Some HLS mirrors expect the header form as well; set both to be safe.
                    media.addOption(":http-header=Referer: \(referer)")
                }
                if let cookie = headers["Cookie"], !cookie.isEmpty {
                    Logger.shared.log("[VLCRenderer.loadMedia] Setting Cookie", type: "Stream")
                    media.addOption(":http-cookie=\(cookie)")
                }
                
                // Let VLC reconnect on transient failures (common on these CDNs)
                Logger.shared.log("[VLCRenderer.loadMedia] Setting http-reconnect=true", type: "Stream")
                media.addOption(":http-reconnect=true")
                
                // Add remaining headers individually, skipping ones already set via dedicated options
                let skippedKeys: Set<String> = ["User-Agent", "Referer", "Cookie"]
                var headerCount = 0
                for (key, value) in headers where !skippedKeys.contains(key) {
                    guard !value.isEmpty else { continue }
                    let headerLine = "\(key): \(value)"
                    Logger.shared.log("[VLCRenderer.loadMedia] Adding header: \(key)", type: "Stream")
                    media.addOption(":http-header=\(headerLine)")
                    headerCount += 1
                }
                Logger.shared.log("[VLCRenderer.loadMedia] Applied \(headerCount) additional headers plus User-Agent/Referer/Cookie", type: "Info")
            }
            
            // Increase network caching to reduce early EOF/errors on slow mirrors
            media.addOption(":network-caching=1200")
            // Keep reconnect enabled for flaky hosts
            media.addOption(":http-reconnect=true")
            
            self.currentMedia = media
            
            Logger.shared.log("[VLCRenderer.loadMedia] Setting media on player and calling play()", type: "Stream")
            Logger.shared.log("[VLCRenderer.loadMedia] Before set media - player state: \(player.state.rawValue)", type: "Stream")
            player.media = media
            Logger.shared.log("[VLCRenderer.loadMedia] After set media - player state: \(player.state.rawValue)", type: "Stream")
            player.play()
            Logger.shared.log("[VLCRenderer.loadMedia] After play() called - player state: \(player.state.rawValue)", type: "Stream")
        }
    }
    
    // Convenience entry point used by VLCPlayer
    func load(url: URL, with preset: PlayerPreset, headers: [String: String]? = nil) {
        Logger.shared.log("[VLCRenderer.load] ENTRY - calling loadMedia with URL: \(url.absoluteString)", type: "Stream")
        Logger.shared.log("[VLCRenderer.load] mediaPlayer is \(mediaPlayer != nil ? "INITIALIZED" : "NIL")", type: "Stream")
        loadMedia(url: url, headers: headers, preset: preset)
    }
    
    // MARK: - Playback Control
    
    func play() {
        eventQueue.async { [weak self] in
            guard let self, let player = self.mediaPlayer else { return }
            player.play()
        }
    }
    
    func pausePlayback() {
        eventQueue.async { [weak self] in
            guard let self, let player = self.mediaPlayer else { return }
            player.pause()
        }
    }
    
    func togglePause() {
        if isPaused { play() } else { pausePlayback() }
    }
    
    func togglePlayPause() {
        togglePause()
    }
    
    func seek(to seconds: Double) {
        eventQueue.async { [weak self] in
            guard let self, let player = self.mediaPlayer else { return }
            let clamped = max(0, seconds)
            
            // If VLC already knows the duration, seek accurately using normalized position.
            let durationMs = player.media?.length.value?.doubleValue ?? 0
            let durationSec = durationMs / 1000.0
            if durationSec > 0 {
                let normalized = min(max(clamped / durationSec, 0), 1)
                player.position = Float(normalized)
                self.cachedDuration = durationSec
                self.pendingAbsoluteSeek = nil
                return
            }
            
            // If we have a cached duration, fall back to it.
            if self.cachedDuration > 0 {
                let normalized = min(max(clamped / self.cachedDuration, 0), 1)
                player.position = Float(normalized)
                self.pendingAbsoluteSeek = clamped
                return
            }
            
            // Duration unknown: stash the seek request to apply once duration arrives.
            self.pendingAbsoluteSeek = clamped
        }
    }
    
    func seek(by seconds: Double) {
        eventQueue.async { [weak self] in
            guard let self, let player = self.mediaPlayer else { return }
            let newTime = self.cachedPosition + seconds
            self.seek(to: newTime)
        }
    }
    
    func setSpeed(_ speed: Double) {
        eventQueue.async { [weak self] in
            guard let self, let player = self.mediaPlayer else { return }
            self.currentPlaybackSpeed = max(0.1, speed)
            player.rate = Float(speed)
        }
    }
    
    func getSpeed() -> Double {
        guard let player = mediaPlayer else { return 1.0 }
        return Double(player.rate)
    }
    
    // MARK: - Audio Tracks (VLC-exclusive)
    
    func getAudioTracks() -> [String] {
        guard let mediaPlayer = mediaPlayer else { return [] }
        return (mediaPlayer.audioTrackNames as? [String]) ?? []
    }
    
    // Returns (id, name, language) tuples to match stub implementation
    func getAudioTracksDetailed() -> [(Int, String, String)] {
        guard let mediaPlayer = mediaPlayer else { return [] }
        
        let trackIds = (mediaPlayer.audioTrackIndexes as? [NSNumber]) ?? []
        let trackNames = (mediaPlayer.audioTrackNames as? [String]) ?? []
        
        return trackIds.enumerated().map { index, idNum in
            let trackName = index < trackNames.count ? trackNames[index] : "Audio Track \(index)"
            let language = parseLanguageFromTrackName(trackName) ?? "und"
            return (idNum.intValue, trackName, language)
        }
    }
    
    func setAudioTrack(id trackIndex: Int) {
        guard let mediaPlayer = mediaPlayer else { return }
        mediaPlayer.currentAudioTrackIndex = Int32(trackIndex)
    }
    
    func setPreferredAudioLanguage(_ language: String) {
        preferredAudioLanguage = language
        applyAudioLanguagePreference()
    }
    
    func setAnimeAudioLanguage(_ language: String) {
        animeAudioLanguage = language
        applyAnimeAudioPreference()
    }
    
    private func applyAudioLanguagePreference() {
        guard let mediaPlayer = mediaPlayer else { return }
        
        let detailedTracks = getAudioTracksDetailed()
        
        // First try exact language match
        if let matchingTrack = detailedTracks.first(where: { $0.2.lowercased() == preferredAudioLanguage.lowercased() }) {
            setAudioTrack(id: matchingTrack.0)
            return
        }
        
        // Then try language code (e.g., "en" for English)
        let languageCode = String(preferredAudioLanguage.prefix(2))
        if let matchingTrack = detailedTracks.first(where: { 
            $0.2.lowercased().starts(with: languageCode.lowercased())
        }) {
            setAudioTrack(id: matchingTrack.0)
            return
        }
        
        // Default to first track
        if let firstTrack = detailedTracks.first {
            setAudioTrack(id: firstTrack.0)
        }
    }
    
    private func applyAnimeAudioPreference() {
        guard let mediaPlayer = mediaPlayer else { return }
        
        let detailedTracks = getAudioTracksDetailed()
        
        // Look for Japanese audio
        if let japaneseTrack = detailedTracks.first(where: { 
            $0.2.lowercased().contains("ja") || 
            $0.1.lowercased().contains("japanese")
        }) {
            setAudioTrack(id: japaneseTrack.0)
            return
        }
        
        // Fallback to standard preference
        applyAudioLanguagePreference()
    }
    
    private func parseLanguageFromTrackName(_ trackName: String) -> String? {
        let components = trackName.lowercased().components(separatedBy: " ")
        
        // Map common language names to codes
        let languageMap: [String: String] = [
            "english": "en", "eng": "en",
            "japanese": "ja", "jpn": "ja",
            "spanish": "es", "spa": "es",
            "french": "fr", "fra": "fr",
            "german": "de", "deu": "de",
            "italian": "it", "ita": "it",
            "portuguese": "pt", "por": "pt",
            "russian": "ru", "rus": "ru",
            "chinese": "zh", "zho": "zh",
            "korean": "ko", "kor": "ko"
        ]
        
        for component in components {
            if let language = languageMap[component] {
                return language
            }
        }
        
        // Try ISO 639-3 codes
        if trackName.count >= 2 {
            return String(trackName.prefix(2)).lowercased()
        }
        
        return nil
    }
    
    // MARK: - Subtitle Tracks (VLC-exclusive)
    
    func getSubtitleTracks() -> [String] {
        guard let mediaPlayer = mediaPlayer else { return [] }
        return (mediaPlayer.videoSubTitlesNames as? [String]) ?? []
    }
    
    // Returns (id, name) tuples to match stub implementation
    func getSubtitleTracksDetailed() -> [(Int, String)] {
        guard let mediaPlayer = mediaPlayer else { return [] }
        
        let trackIds = (mediaPlayer.videoSubTitlesIndexes as? [NSNumber]) ?? []
        let trackNames = (mediaPlayer.videoSubTitlesNames as? [String]) ?? []
        
        return trackIds.enumerated().map { index, idNum in
            let trackName = index < trackNames.count ? trackNames[index] : "Subtitle Track \(index)"
            return (idNum.intValue, trackName)
        }
    }
    
    func setSubtitleTrack(id trackIndex: Int) {
        guard let mediaPlayer = mediaPlayer else { return }
        mediaPlayer.currentVideoSubTitleIndex = Int32(trackIndex)
        delegate?.rendererDidChangeTracks(self)
    }
    
    func getAvailableSubtitles() -> [String] {
        return getSubtitleTracks()
    }
    
    func loadExternalSubtitles(url: URL) throws {
        guard let mediaPlayer = mediaPlayer else { return }
        
        // VLC auto-detects external subtitles in the same folder
        // For direct file loading, add the subtitle file as media option
        let subtitlePath = url.path
        mediaPlayer.media?.addOption("sub-file=\(subtitlePath)")
        
        Logger.shared.log("[VLCRenderer] Loaded external subtitles: \(subtitlePath)", type: "Stream")
    }
    
    func disableSubtitles() {
        guard let mediaPlayer = mediaPlayer else { return }
        mediaPlayer.currentVideoSubTitleIndex = -1
        delegate?.rendererDidChangeTracks(self)
    }
    
    func enableAutoSubtitles(_ enabled: Bool) {
        autoLoadSubtitles = enabled
        guard let currentURL = currentURL else { return }
        
        if enabled {
            // Try to auto-load subtitle files with same name
            let subtitleFormats = ["srt", "vtt", "ass", "ssa"]
            let basePath = currentURL.deletingPathExtension().path
            
            for format in subtitleFormats {
                let subtitlePath = basePath + ".\(format)"
                if FileManager.default.fileExists(atPath: subtitlePath) {
                    try? loadExternalSubtitles(url: URL(fileURLWithPath: subtitlePath))
                    break
                }
            }
        }
    }
    
    // MARK: - Event Observers
    
    @objc private func mediaPlayerTimeChanged() {
        guard let player = mediaPlayer else { return }
        
        let positionMs = player.time.value?.doubleValue ?? 0
        let position = positionMs / 1000.0
        let durationMs = player.media?.length.value?.doubleValue ?? 0
        let duration = durationMs / 1000.0
        
        cachedPosition = position
        cachedDuration = duration
        
        if duration > 0 && !isLoading {
            if isLoading {
                isLoading = false
                DispatchQueue.main.async { [weak self] in
                    guard let self else { return }
                    self.delegate?.renderer(self, didChangeLoading: false)
                }
            }
        }
        
        DispatchQueue.main.async { [weak self] in
            guard let self else { return }
            self.delegate?.renderer(self, didUpdatePosition: position, duration: duration)
        }
    }
    
    @objc private func mediaPlayerStateChanged() {
        guard let player = mediaPlayer else { 
            Logger.shared.log("[VLCRenderer.mediaPlayerStateChanged] ERROR: mediaPlayer is nil!", type: "Error")
            return 
        }
        
        let state = player.state
        Logger.shared.log("[VLCRenderer.mediaPlayerStateChanged] State changed to: \(state.rawValue) (media=\(player.media != nil ? "set" : "nil"))", type: "Stream")
        
        switch state {
        case .playing:
            isPaused = false
            isLoading = false
            isReadyToSeek = true
            
            Logger.shared.log("[VLCRenderer] Now playing", type: "Stream")
            DispatchQueue.main.async { [weak self] in
                guard let self else { return }
                self.delegate?.renderer(self, didChangePause: false)
                self.delegate?.renderer(self, didChangeLoading: false)
                self.delegate?.renderer(self, didBecomeReadyToSeek: true)
            }
            
        case .paused:
            isPaused = true
            Logger.shared.log("[VLCRenderer] Paused", type: "Stream")
            DispatchQueue.main.async { [weak self] in
                guard let self else { return }
                self.delegate?.renderer(self, didChangePause: true)
            }
            
        case .opening, .buffering:
            isLoading = true
            Logger.shared.log("[VLCRenderer] Loading/Buffering", type: "Stream")
            DispatchQueue.main.async { [weak self] in
                guard let self else { return }
                self.delegate?.renderer(self, didChangeLoading: true)
            }

        case .stopped, .ended, .error:
            isPaused = true
            isLoading = false
            if state == .error {
                Logger.shared.log("[VLCRenderer] ERROR state reached", type: "Error")
            }
            DispatchQueue.main.async { [weak self] in
                guard let self else { return }
                self.delegate?.renderer(self, didChangePause: true)
                self.delegate?.renderer(self, didChangeLoading: false)
            }
            
        default:
            break
        }
    }
    
    @objc private func handleAppDidEnterBackground() {
        pausePlayback()
    }
    
    @objc private func handleAppWillEnterForeground() {
        play()
    }
    
    // MARK: - Properties
    
    var position: Double {
        return cachedPosition
    }
    
    var duration: Double {
        return cachedDuration
    }
    
    var isPlaying: Bool {
        return !isPaused
    }
}

#else
// Stub when MobileVLCKit is not available (tvOS, etc.)

// Log that we're using stub implementation
private let _ = {
    print("[VLCRenderer] ⚠️ Using STUB implementation - MobileVLCKit NOT available!")
    print("[VLCRenderer] ⚠️ Install CocoaPods: cd to project folder, run 'pod install'")
    return true
}()

protocol VLCRendererDelegate: AnyObject {
    func renderer(_ renderer: VLCRenderer, didUpdatePosition position: Double, duration: Double)
    func renderer(_ renderer: VLCRenderer, didChangePause isPaused: Bool)
    func renderer(_ renderer: VLCRenderer, didChangeLoading isLoading: Bool)
    func renderer(_ renderer: VLCRenderer, didBecomeReadyToSeek: Bool)
    func renderer(_ renderer: VLCRenderer, getSubtitleForTime time: Double) -> NSAttributedString?
    func renderer(_ renderer: VLCRenderer, getSubtitleStyle: Void) -> SubtitleStyle
    func renderer(_ renderer: VLCRenderer, subtitleTrackDidChange trackId: Int)
    func rendererDidChangeTracks(_ renderer: VLCRenderer)
}

final class VLCRenderer {
    enum RendererError: Error {
        case vlcInitializationFailed
    }
    
    init(displayLayer: AVSampleBufferDisplayLayer) { }
    func getRenderingView() -> UIView { UIView() }
    func start() throws { throw RendererError.vlcInitializationFailed }
    func stop() { }
    func load(url: URL, with preset: PlayerPreset, headers: [String: String]?) { }
    func reloadCurrentItem() { }
    func applyPreset(_ preset: PlayerPreset) { }
    func play() { }
    func pausePlayback() { }
    func togglePause() { }
    func togglePlayPause() { }
    func seek(to seconds: Double) { }
    func seek(by seconds: Double) { }
    func setSpeed(_ speed: Double) { }
    func getSpeed() -> Double { 1.0 }
    func getAudioTracksDetailed() -> [(Int, String, String)] { [] }
    func getAudioTracks() -> [(Int, String)] { [] }
    func setAudioTrack(id: Int) { }
    func setPreferredAudioLanguage(_ language: String) { }
    func setAnimeAudioLanguage(_ language: String) { }
    func getSubtitleTracks() -> [(Int, String)] { [] }
    func getSubtitleTracksDetailed() -> [(Int, String)] { [] }
    func setSubtitleTrack(id: Int) { }
    func disableSubtitles() { }
    func enableAutoSubtitles(_ enabled: Bool) { }
    func getAvailableSubtitles() -> [String] { [] }
    func refreshSubtitleOverlay() { }
    func loadExternalSubtitles(urls: [String]) { }
    func clearSubtitleCache() { }
    var isPausedState: Bool { true }
    var position: Double { 0 }
    var duration: Double { 0 }
    weak var delegate: VLCRendererDelegate?
}

#endif  // canImport(MobileVLCKit)
