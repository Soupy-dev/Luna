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
#if os(iOS)
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
        guard !isRunning else { return }
        
        Logger.shared.log("[VLCRenderer.start] Initializing VLCMediaPlayer", type: "Stream")
        
        mediaPlayer = VLCMediaPlayer()
        guard let mediaPlayer = mediaPlayer else {
            throw RendererError.vlcInitializationFailed
        }
        
        // Attach to view for rendering
        mediaPlayer.drawable = vlcView
        
        // Setup event handlers
        setupMediaPlayerObservers(mediaPlayer)
        
        isRunning = true
        Logger.shared.log("[VLCRenderer.start] VLCRenderer initialized", type: "Stream")
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
    
    func loadMedia(url: URL, headers: [String: String]? = nil, preset: PlayerPreset? = nil) throws {
        guard isRunning else { throw RendererError.vlcInitializationFailed }
        guard let mediaPlayer = mediaPlayer else { throw RendererError.vlcInitializationFailed }
        
        currentURL = url
        currentHeaders = headers
        currentPreset = preset
        
        let media = VLCMedia(url: url)
        
        // Configure network options
        media.addOption(":http-reconnect=true")
        media.addOption(":http-timeout=10000")
        media.addOption(":network-caching=5000")
        media.addOption(":file-caching=1000")
        
        // Add custom headers if provided
        if let headers = headers {
            var userAgent = ""
            for (key, value) in headers {
                if key.lowercased() == "user-agent" {
                    userAgent = value
                } else {
                    media.addOption("http-header=\(key): \(value)")
                }
            }
            if !userAgent.isEmpty {
                media.addOption(":http-user-agent=\(userAgent)")
            }
        }
        
        // Enable hardware decoding if available
        media.addOption(":codec=videotoolbox")
        
        currentMedia = media
        mediaPlayer.media = media
        
        // Apply audio preferences
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) { [weak self] in
            self?.applyAudioLanguagePreference()
            self?.enableAutoSubtitles(self?.autoLoadSubtitles ?? true)
        }
        
        mediaPlayer.play()
        
        Logger.shared.log("[VLCRenderer] Loaded media: \(url.absoluteString)", type: "Stream")
    }
    
    // MARK: - Playback Control
    
    func play() {
        mediaPlayer?.play()
    }
    
    func pause() {
        mediaPlayer?.pause()
    }
    
    func togglePlayPause() {
        if isPaused {
            play()
        } else {
            pause()
        }
    }
    
    func seek(to position: Double) {
        guard let mediaPlayer = mediaPlayer else { return }
        mediaPlayer.position = Float(position / (cachedDuration > 0 ? cachedDuration : 1.0))
    }
    
    func setPlaybackSpeed(_ speed: Double) {
        currentPlaybackSpeed = speed
        mediaPlayer?.rate = Float(speed)
    }
    
    // MARK: - Audio Tracks (VLC-exclusive)
    
    struct AudioTrack {
        let id: Int
        let name: String
        let language: String?
        let isDefault: Bool
    }
    
    func getAudioTracks() -> [String] {
        guard let mediaPlayer = mediaPlayer else { return [] }
        return (mediaPlayer.audioTrackNames as? [String]) ?? []
    }
    
    func getAudioTracksDetailed() -> [AudioTrack] {
        guard let mediaPlayer = mediaPlayer else { return [] }
        
        let trackIds = (mediaPlayer.audioTrackIndexes as? [NSNumber]) ?? []
        let trackNames = (mediaPlayer.audioTrackNames as? [String]) ?? []
        
        return trackIds.enumerated().map { index, idNum in
            let trackName = index < trackNames.count ? trackNames[index] : "Audio Track \(index)"
            let language = parseLanguageFromTrackName(trackName)
            return AudioTrack(
                id: idNum.intValue,
                name: trackName,
                language: language,
                isDefault: idNum.intValue == mediaPlayer.currentAudioTrackIndex
            )
        }
    }
    
    func setAudioTrack(_ trackIndex: Int) {
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
        if let matchingTrack = detailedTracks.first(where: { $0.language?.lowercased() == preferredAudioLanguage.lowercased() }) {
            setAudioTrack(matchingTrack.id)
            return
        }
        
        // Then try language code (e.g., "en" for English)
        let languageCode = String(preferredAudioLanguage.prefix(2))
        if let matchingTrack = detailedTracks.first(where: { 
            $0.language?.lowercased().starts(with: languageCode.lowercased()) ?? false
        }) {
            setAudioTrack(matchingTrack.id)
            return
        }
        
        // Default to first track
        if let firstTrack = detailedTracks.first {
            setAudioTrack(firstTrack.id)
        }
    }
    
    private func applyAnimeAudioPreference() {
        guard let mediaPlayer = mediaPlayer else { return }
        guard Settings.shared.isAnimeContent else { return }
        
        let detailedTracks = getAudioTracksDetailed()
        
        // Look for Japanese audio
        if let japaneseTrack = detailedTracks.first(where: { 
            $0.language?.lowercased().contains("ja") ?? false || 
            $0.name.lowercased().contains("japanese")
        }) {
            setAudioTrack(japaneseTrack.id)
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
    
    struct SubtitleTrack {
        let id: Int
        let name: String
        let isDefault: Bool
        let isExternal: Bool
    }
    
    func getSubtitleTracks() -> [String] {
        guard let mediaPlayer = mediaPlayer else { return [] }
        return (mediaPlayer.videoSubTitlesNames as? [String]) ?? []
    }
    
    func getSubtitleTracksDetailed() -> [SubtitleTrack] {
        guard let mediaPlayer = mediaPlayer else { return [] }
        
        let trackIds = (mediaPlayer.videoSubTitlesIndexes as? [NSNumber]) ?? []
        let trackNames = (mediaPlayer.videoSubTitlesNames as? [String]) ?? []
        
        return trackIds.enumerated().map { index, idNum in
            let trackName = index < trackNames.count ? trackNames[index] : "Subtitle Track \(index)"
            return SubtitleTrack(
                id: idNum.intValue,
                name: trackName,
                isDefault: idNum.intValue == mediaPlayer.currentVideoSubTitleIndex,
                isExternal: trackName.contains("srt") || trackName.contains("vtt") || trackName.contains("ass")
            )
        }
    }
    
    func setSubtitleTrack(_ trackIndex: Int) {
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
    
    private func setupMediaPlayerObservers(_ mediaPlayer: VLCMediaPlayer) {
        let notificationCenter = NotificationCenter.default
        
        notificationCenter.addObserver(
            forName: VLCMediaPlayerStateChanged,
            object: mediaPlayer,
            queue: eventQueue
        ) { [weak self] _ in
            self?.handleMediaPlayerStateChange()
        }
        
        notificationCenter.addObserver(
            forName: VLCMediaPlayerTimeChanged,
            object: mediaPlayer,
            queue: eventQueue
        ) { [weak self] _ in
            self?.handleMediaPlayerTimeChanged()
        }
    }
    
    private func handleMediaPlayerStateChange() {
        guard let mediaPlayer = mediaPlayer else { return }
        
        DispatchQueue.main.async { [weak self] in
            guard let self = self else { return }
            
            let newPaused = mediaPlayer.state == .paused || mediaPlayer.state == .stopped
            if newPaused != self.isPaused {
                self.isPaused = newPaused
                self.delegate?.renderer(self, didChangePause: self.isPaused)
            }
            
            let newLoading = mediaPlayer.state == .opening || mediaPlayer.state == .buffering
            if newLoading != self.isLoading {
                self.isLoading = newLoading
                self.delegate?.renderer(self, didChangeLoading: self.isLoading)
            }
        }
    }
    
    private func handleMediaPlayerTimeChanged() {
        guard let mediaPlayer = mediaPlayer else { return }
        
        DispatchQueue.main.async { [weak self] in
            guard let self = self else { return }
            
            let position = Double(mediaPlayer.time.value) / 1000.0
            let duration = Double(mediaPlayer.media?.length.value ?? 0) / 1000.0
            
            self.cachedPosition = position
            self.cachedDuration = duration
            
            self.delegate?.renderer(self, didUpdatePosition: position, duration: duration)
        }
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
// tvOS: Placeholder implementation that does nothing
final class VLCRenderer: NSObject {
    init(displayLayer: AVSampleBufferDisplayLayer) {}
    func getRenderingView() -> UIView { return UIView() }
    func start() throws {}
    func stop() {}
    func loadMedia(url: URL, headers: [String: String]? = nil, preset: PlayerPreset? = nil) throws {}
    func play() {}
    func pause() {}
    func seek(to position: Double) {}
    func setPlaybackSpeed(_ speed: Double) {}
    func setPreferredAudioLanguage(_ language: String) {}
    func setAnimeAudioLanguage(_ language: String) {}
    func enableAutoSubtitles(_ enabled: Bool) {}
    func setSubtitleTrack(_ trackIndex: Int) {}
    func getAvailableSubtitles() -> [String] { [] }
    var position: Double { 0 }
    var duration: Double { 0 }
    var isPlaying: Bool { false }
}
#endif
