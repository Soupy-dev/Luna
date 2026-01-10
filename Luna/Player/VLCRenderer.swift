//
//  VLCRenderer.swift
//  Luna
//
//  VLC player renderer using MobileVLCKit for GPU-accelerated playback
//  Provides same interface as MPVSoftwareRenderer for thermal optimization
//
//  DEPENDENCY: Add MobileVLCKit via CocoaPods:
//  pod 'MobileVLCKit'
//  
//  Or via Xcode: Project → Targets → Build Phases → Link Binary With Libraries → Add MobileVLCKit.xcframework

import UIKit
import AVFoundation

// MARK: - Compatibility: VLC renderer is iOS-only (tvOS uses MPV)
#if canImport(MobileVLCKit) && os(iOS)
import MobileVLCKit

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
    
    // VLC rendering container - uses OpenGL rendering
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
    
    weak var delegate: VLCRendererDelegate?
    
    init(displayLayer: AVSampleBufferDisplayLayer) {
        self.displayLayer = displayLayer
        // Create a UIView container that VLC will render into
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
        // Prefer aspect-fit semantics to keep full frame visible; rely on black bars
        vlcView.contentMode = .scaleAspectFit
        vlcView.layer.contentsGravity = .resizeAspect
        vlcView.layer.isOpaque = true
        vlcView.clipsToBounds = true
        vlcView.isUserInteractionEnabled = false  // Allow touches to pass through to controls
    }
    
    /// Return the VLC view to be added to the view hierarchy
    func getRenderingView() -> UIView {
        return vlcView
    }
    
    // MARK: - Lifecycle
    
    func start() throws {
        guard !isRunning else { return }
        
        do {
            Logger.shared.log("[VLCRenderer.start] Initializing VLCMediaPlayer", type: "Stream")
            
            // Configure audio session for playback
            #if os(iOS)
            do {
                let audioSession = AVAudioSession.sharedInstance()
                try audioSession.setCategory(.playback, mode: .moviePlayback, options: [])
                try audioSession.setActive(true)
                Logger.shared.log("[VLCRenderer.start] Audio session configured", type: "Stream")
            } catch {
                Logger.shared.log("[VLCRenderer.start] Failed to configure audio session: \(error)", type: "Error")
            }
            #endif
            
            // Initialize VLC with proper options for video rendering
            mediaPlayer = VLCMediaPlayer()
            guard let mediaPlayer = mediaPlayer else {
                throw RendererError.vlcInitializationFailed
            }
            
            // Render directly into the VLC view (stable video output)
            mediaPlayer.drawable = vlcView
            
            // Set up event handling
            NotificationCenter.default.addObserver(
                self,
                selector: #selector(mediaPlayerTimeChanged),
                name: NSNotification.Name(rawValue: VLCMediaPlayerTimeChanged),
                object: mediaPlayer
            )
            NotificationCenter.default.addObserver(
                self,
                selector: #selector(mediaPlayerStateChanged),
                name: NSNotification.Name(rawValue: VLCMediaPlayerStateChanged),
                object: mediaPlayer
            )
            
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
            Logger.shared.log("[VLCRenderer.start] isRunning=true", type: "Stream")
        } catch {
            throw RendererError.vlcInitializationFailed
        }
    }
    
    func stop() {
        if isStopping { return }
        if !isRunning { return }
        
        isRunning = false
        isStopping = true

        eventQueue.async { [weak self] in
            guard let self else { return }

            if let player = self.mediaPlayer {
                player.stop()
                self.mediaPlayer = nil
            }

            self.currentMedia = nil
            self.isReadyToSeek = false
            self.isPaused = true
            self.isLoading = false

            NotificationCenter.default.removeObserver(self)

            // Mark stop completion only after cleanup finishes to prevent reentrancy races
            self.isStopping = false
        }
    }
    
    // MARK: - Playback Control
    
    func load(url: URL, with preset: PlayerPreset, headers: [String: String]? = nil) {
        Logger.shared.log("[VLCRenderer.load] Starting load with URL: \(url.absoluteString)", type: "Stream")
        Logger.shared.log("[VLCRenderer.load] Headers count: \(headers?.count ?? 0)", type: "Stream")
        if let headers = headers {
            for (k, v) in headers {
                Logger.shared.log("[VLCRenderer.load] Header - \(k): \(v.prefix(50))...", type: "Stream")
            }
        }
        
        currentURL = url
        currentPreset = preset

        // Use provided headers as-is; they're already built correctly by the caller
        // (StreamURL domain should NOT be used for headers—service baseUrl should be)
        currentHeaders = headers ?? [:]
        
        Logger.shared.log("[VLCRenderer.load] VLCRenderer: Loading \(url.absoluteString)", type: "Info")
        
        isLoading = true
        isReadyToSeek = false
        DispatchQueue.main.async { [weak self] in
            guard let self else { return }
            self.delegate?.renderer(self, didChangeLoading: true)
        }
        
        eventQueue.async { [weak self] in
            guard let self, let player = self.mediaPlayer else { 
                Logger.shared.log("[VLCRenderer.load] ERROR: mediaPlayer is nil", type: "Error")
                return 
            }
            
            Logger.shared.log("[VLCRenderer.load] Creating VLCMedia with URL", type: "Stream")
            // Keep the URL untouched; apply headers via VLC media options
            let media = VLCMedia(url: url)
            if let headers = self.currentHeaders, !headers.isEmpty {
                Logger.shared.log("[VLCRenderer.load] Applying \(headers.count) headers to VLCMedia", type: "Stream")
                // Prefer dedicated options when available (unquoted to match server expectations)
                if let ua = headers["User-Agent"], !ua.isEmpty {
                    Logger.shared.log("[VLCRenderer.load] Setting User-Agent", type: "Stream")
                    media.addOption(":http-user-agent=\(ua)")
                }
                if let referer = headers["Referer"], !referer.isEmpty {
                    Logger.shared.log("[VLCRenderer.load] Setting Referer", type: "Stream")
                    media.addOption(":http-referrer=\(referer)")
                    // Some HLS mirrors expect the header form as well; set both to be safe.
                    media.addOption(":http-header=Referer: \(referer)")
                }
                if let cookie = headers["Cookie"], !cookie.isEmpty {
                    Logger.shared.log("[VLCRenderer.load] Setting Cookie", type: "Stream")
                    media.addOption(":http-cookie=\(cookie)")
                }

                // Let VLC reconnect on transient failures (common on these CDNs)
                Logger.shared.log("[VLCRenderer.load] Setting http-reconnect=true", type: "Stream")
                media.addOption(":http-reconnect=true")

                // Add remaining headers individually, skipping ones already set via dedicated options
                let skippedKeys: Set<String> = ["User-Agent", "Referer", "Cookie"]
                var headerCount = 0
                for (key, value) in headers where !skippedKeys.contains(key) {
                    guard !value.isEmpty else { continue }
                    let headerLine = "\(key): \(value)"
                    Logger.shared.log("[VLCRenderer.load] Adding header: \(key)", type: "Stream")
                    media.addOption(":http-header=\(headerLine)")
                    headerCount += 1
                }
                Logger.shared.log("[VLCRenderer.load] Applied \(headerCount) additional headers plus User-Agent/Referer/Cookie", type: "Info")
            }

            // Increase network caching to reduce early EOF/errors on slow mirrors
            media.addOption(":network-caching=1200")
            // Keep reconnect enabled for flaky hosts
            media.addOption(":http-reconnect=true")

            self.currentMedia = media
            
            Logger.shared.log("[VLCRenderer.load] Setting media on player and calling play()", type: "Stream")
            player.media = media
            player.play()
            Logger.shared.log("[VLCRenderer.load] play() called", type: "Stream")
        }
    }
    
    func reloadCurrentItem() {
        guard let url = currentURL, let preset = currentPreset else { return }
        load(url: url, with: preset, headers: currentHeaders)
    }
    
    func applyPreset(_ preset: PlayerPreset) {
        currentPreset = preset
        // VLC doesn't require preset application like mpv does
        // Presets are mainly for video output configuration which VLC handles automatically
    }
    
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
            
            // Track current speed for thermal optimization
            self.currentPlaybackSpeed = max(0.1, speed)
            
            player.rate = Float(speed)
        }
    }
    
    func getSpeed() -> Double {
        guard let player = mediaPlayer else { return 1.0 }
        return Double(player.rate)
    }
    
    // MARK: - Audio Track Controls
    
    func getAudioTracksDetailed() -> [(Int, String, String)] {
        guard let player = mediaPlayer else { return [] }
        
        var result: [(Int, String, String)] = []
        
        // VLC provides audio track info through the media player
        if let audioTrackIndexes = player.audioTrackIndexes as? [Int],
           let audioTrackNames = player.audioTrackNames as? [String] {
            // MobileVLCKit doesn't expose language codes publicly; rely on name parsing
            for (index, name) in zip(audioTrackIndexes, audioTrackNames) {
                let code = guessLanguageCode(from: name)
                result.append((index, name, code))
            }
        }
        
        return result
    }

    // Heuristic language guess when VLC doesn't expose codes
    private func guessLanguageCode(from name: String) -> String {
        let lower = name.lowercased()
        let map: [(String, [String])] = [
            ("jpn", ["japanese", "jpn", "ja", "jp"]),
            ("eng", ["english", "eng", "en", "us", "uk"]),
            ("spa", ["spanish", "spa", "es", "esp", "lat" ]),
            ("fre", ["french", "fra", "fre", "fr"]),
            ("ger", ["german", "deu", "ger", "de"]),
            ("ita", ["italian", "ita", "it"]),
            ("por", ["portuguese", "por", "pt", "br"]),
            ("rus", ["russian", "rus", "ru"]),
            ("chi", ["chinese", "chi", "zho", "zh", "mandarin", "cantonese"]),
            ("kor", ["korean", "kor", "ko"])
        ]
        for (code, tokens) in map {
            if tokens.contains(where: { lower.contains($0) }) {
                return code
            }
        }
        return ""
    }
    
    func getAudioTracks() -> [(Int, String)] {
        return getAudioTracksDetailed().map { ($0.0, $0.1) }
    }
    
    func setAudioTrack(id: Int) {
        eventQueue.async { [weak self] in
            guard let self, let player = self.mediaPlayer else { return }
            
            player.currentAudioTrackIndex = Int32(id)
            DispatchQueue.main.async { [weak self] in
                guard let self else { return }
                self.delegate?.rendererDidChangeTracks(self)
            }
        }
    }
    
    func getCurrentAudioTrackId() -> Int {
        guard let player = mediaPlayer else { return -1 }
        return Int(player.currentAudioTrackIndex)
    }

    
    // MARK: - Subtitle Track Controls
    
    func getSubtitleTracks() -> [(Int, String)] {
        guard let player = mediaPlayer else { return [] }
        
        var result: [(Int, String)] = []
        
        // VLC provides subtitle track info through the media player
        if let subtitleIndexes = player.videoSubTitlesIndexes as? [Int],
           let subtitleNames = player.videoSubTitlesNames as? [String] {
            for (index, name) in zip(subtitleIndexes, subtitleNames) {
                result.append((index, name))
            }
        }
        
        return result
    }
    
    func setSubtitleTrack(id: Int) {
        eventQueue.async { [weak self] in
            guard let self, let player = self.mediaPlayer else { return }
            
            player.currentVideoSubTitleIndex = Int32(id)
            DispatchQueue.main.async { [weak self] in
                guard let self else { return }
                self.delegate?.renderer(self, subtitleTrackDidChange: id)
                self.delegate?.rendererDidChangeTracks(self)
            }
        }
    }
    
    func disableSubtitles() {
        eventQueue.async { [weak self] in
            guard let self, let player = self.mediaPlayer else { return }
            // Disable subtitles by setting track index to -1
            player.currentVideoSubTitleIndex = -1
        }
    }
    
    func refreshSubtitleOverlay() {
        // VLC handles subtitle rendering automatically through native libass
        // No manual refresh needed
    }
    
    // MARK: - External Subtitles
    
    func loadExternalSubtitles(urls: [String]) {
        guard let player = mediaPlayer, let media = currentMedia else { return }
        
        eventQueue.async { [weak self] in
            Logger.shared.log("VLCRenderer: Adding external subtitles count=\(urls.count)", type: "Info")
            for urlString in urls {
                if let url = URL(string: urlString) {
                    player.addPlaybackSlave(url, type: VLCMediaPlaybackSlaveType.subtitle, enforce: false)
                    Logger.shared.log("VLCRenderer: added playback slave subtitle=\(url.absoluteString)", type: "Info")
                }
            }
            DispatchQueue.main.async { [weak self] in
                guard let self else { return }
                self.delegate?.rendererDidChangeTracks(self)
            }
        }
    }
    
    func clearSubtitleCache() {
        // VLC handles subtitle caching internally
    }
    
    func getSubtitleTracksDetailed() -> [(Int, String)] {
        return getSubtitleTracks()
    }
    
    func getCurrentSubtitleTrackId() -> Int {
        guard let player = mediaPlayer else { return -1 }
        return Int(player.currentVideoSubTitleIndex)
    }
    
    func getAvailableSubtitles() -> [String] {
        return getSubtitleTracks().map { $0.1 }
    }
    
    // MARK: - Anime Audio & Auto Subtitle Features
    
    // These methods are called by VLCPlayer but VLC handles track selection
    // through the standard track APIs. We keep these for compatibility.
    
    func enableAutoSubtitles(_ enable: Bool) {
        // Auto-subtitle selection is handled through track selection UI
        // VLC automatically detects and lists all subtitle tracks
        Logger.shared.log("[VLCRenderer] Auto subtitles \(enable ? "enabled" : "disabled")", type: "Info")
    }
    
    func setPreferredAudioLanguage(_ language: String) {
        // Store preference for future use, but VLC doesn't auto-select by language
        Logger.shared.log("[VLCRenderer] Preferred audio language set to: \(language)", type: "Info")
    }
    
    func setAnimeAudioLanguage(_ language: String) {
        // Store anime audio preference
        Logger.shared.log("[VLCRenderer] Anime audio language set to: \(language)", type: "Info")
    }
    
    func togglePlayPause() {
        togglePause()
    }

    // MARK: - Event Handlers
    
    @objc private func mediaPlayerTimeChanged() {
        guard let player = mediaPlayer else { return }
        
        let positionMs = player.time.value?.doubleValue ?? 0
        let durationMs = player.media?.length.value?.doubleValue ?? 0
        let position = positionMs / 1000.0
        let duration = durationMs / 1000.0
        
        cachedPosition = position
        cachedDuration = duration

        // If we were waiting for duration to apply a pending seek, do it once duration is known.
        if duration > 0, let pending = pendingAbsoluteSeek {
            let normalized = min(max(pending / duration, 0), 1)
            player.position = Float(normalized)
            pendingAbsoluteSeek = nil
        }

        // If we were marked loading but playback is progressing, clear loading state
        if isLoading {
            isLoading = false
            DispatchQueue.main.async { [weak self] in
                guard let self else { return }
                self.delegate?.renderer(self, didChangeLoading: false)
            }
        }
        
        DispatchQueue.main.async { [weak self] in
            guard let self else { return }
            self.delegate?.renderer(self, didUpdatePosition: position, duration: duration)
        }
    }
    
    @objc private func mediaPlayerStateChanged() {
        guard let player = mediaPlayer else { return }
        
        let state = player.state
        let urlString = currentURL?.absoluteString ?? "nil"
        let stateLabel = describeState(state)
        let logType = (state == .error) ? "Error" : "Info"
        if state == .error {
            let headerCount = currentHeaders?.count ?? 0
            Logger.shared.log("VLCRenderer: state=\(stateLabel) url=\(urlString) headers=\(headerCount) preset=\(currentPreset?.id.rawValue ?? "nil")", type: logType)
        } else {
            Logger.shared.log("VLCRenderer: state=\(stateLabel) url=\(urlString)", type: logType)
        }
        
        switch state {
        case .playing:
            isPaused = false
            isLoading = false
            isReadyToSeek = true
            
            DispatchQueue.main.async { [weak self] in
                guard let self else { return }
                self.delegate?.renderer(self, didChangePause: false)
                self.delegate?.renderer(self, didChangeLoading: false)
                self.delegate?.renderer(self, didBecomeReadyToSeek: true)
            }
            
        case .paused:
            isPaused = true
            DispatchQueue.main.async { [weak self] in
                guard let self else { return }
                self.delegate?.renderer(self, didChangePause: true)
            }
            
        case .opening, .buffering:
            isLoading = true
            DispatchQueue.main.async { [weak self] in
                guard let self else { return }
                self.delegate?.renderer(self, didChangeLoading: true)
            }

        case .stopped, .ended, .error:
            isPaused = true
            isLoading = false
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
        // Pause playback when app goes to background for thermal efficiency
        pausePlayback()
    }
    
    @objc private func handleAppWillEnterForeground() {
        // Resume playback when app returns to foreground
        play()
    }
    
    // MARK: - State Properties
    
    var isPausedState: Bool {
        return isPaused
    }

    private func describeState(_ state: VLCMediaPlayerState) -> String {
        switch state {
        case .opening: return "opening"
        case .buffering: return "buffering"
        case .ended: return "ended"
        case .error: return "error"
        case .paused: return "paused"
        case .playing: return "playing"
        case .stopped: return "stopped"
        case .esAdded: return "esAdded"
        @unknown default:
            // Older or newer SDKs may expose an idle/unknown state; fall back to rawValue for logging.
            return "unknown(\(state.rawValue))"
        }
    }
}

#else  // Stub when MobileVLCKit is not available

// Minimal stub to allow compilation when MobileVLCKit is not installed
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
    func seek(to seconds: Double) { }
    func seek(by seconds: Double) { }
    func setSpeed(_ speed: Double) { }
    func getSpeed() -> Double { 1.0 }
    func getAudioTracksDetailed() -> [(Int, String, String)] { [] }
    func getAudioTracks() -> [(Int, String)] { [] }
    func getCurrentAudioTrackId() -> Int { -1 }
    func setAudioTrack(id: Int) { }
    func getSubtitleTracks() -> [(Int, String)] { [] }
    func getSubtitleTracksDetailed() -> [(Int, String)] { [] }
    func getCurrentSubtitleTrackId() -> Int { -1 }
    func setSubtitleTrack(id: Int) { }
    func disableSubtitles() { }
    func refreshSubtitleOverlay() { }
    func loadExternalSubtitles(urls: [String]) { }
    func clearSubtitleCache() { }
    func getAvailableSubtitles() -> [String] { [] }
    func enableAutoSubtitles(_ enable: Bool) { }
    func setPreferredAudioLanguage(_ language: String) { }
    func setAnimeAudioLanguage(_ language: String) { }
    func togglePlayPause() { }
    var isPausedState: Bool { true }
    weak var delegate: VLCRendererDelegate?
}

#endif  // canImport(MobileVLCKit)

