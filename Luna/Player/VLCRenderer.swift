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

// MARK: - Compatibility: Handle missing MobileVLCKit gracefully
#if canImport(MobileVLCKit)
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
    
    private var vlcInstance: VLCMediaList?
    private var mediaPlayer: VLCMediaPlayer?
    private var currentMedia: VLCMedia?
    
    private var isPaused: Bool = true
    private var isLoading: Bool = false
    private var isReadyToSeek: Bool = false
    private var cachedDuration: Double = 0
    private var cachedPosition: Double = 0
    private var currentURL: URL?
    private var currentHeaders: [String: String]?
    private var currentPreset: PlayerPreset?
    private var isRunning = false
    private var isStopping = false
    
    weak var delegate: VLCRendererDelegate?
    
    init(displayLayer: AVSampleBufferDisplayLayer) {
        self.displayLayer = displayLayer
        super.init()
    }
    
    deinit {
        stop()
    }
    
    // MARK: - Lifecycle
    
    func start() throws {
        guard !isRunning else { return }
        
        do {
            mediaPlayer = VLCMediaPlayer()
            guard let mediaPlayer = mediaPlayer else {
                throw RendererError.vlcInitializationFailed
            }
            
            // Configure media player for compatibility with AVSampleBufferDisplayLayer
            mediaPlayer.audio = true
            mediaPlayer.drawable = displayLayer
            
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
            
            NotificationCenter.default.removeObserver(self)
        }
        
        isStopping = false
    }
    
    // MARK: - Playback Control
    
    func load(url: URL, with preset: PlayerPreset, headers: [String: String]? = nil) {
        currentURL = url
        currentPreset = preset
        currentHeaders = headers
        
        Logger.shared.log("VLCRenderer: Loading \(url.absoluteString)", type: "Info")
        
        isLoading = true
        isReadyToSeek = false
        DispatchQueue.main.async { [weak self] in
            guard let self else { return }
            self.delegate?.renderer(self, didChangeLoading: true)
        }
        
        eventQueue.async { [weak self] in
            guard let self, let player = self.mediaPlayer else { return }
            
            var urlString = url.absoluteString
            
            // Apply HTTP headers if provided
            if let headers = headers, !headers.isEmpty {
                // VLC media options for HTTP headers
                let headerStrings = headers.map { "\($0.key): \($0.value)" }
                urlString = urlString + "?:http-user-agent=" + (headers["User-Agent"] ?? "VLC")
            }
            
            let media = VLCMedia(URL: URL(string: urlString) ?? url)
            self.currentMedia = media
            
            player.media = media
            player.play()
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
            player.position = Float(clamped / (self.cachedDuration > 0 ? self.cachedDuration : 1.0))
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
            player.rate = Float(speed)
        }
    }
    
    func getSpeed() -> Double {
        guard let player = mediaPlayer else { return 1.0 }
        return Double(player.rate)
    }
    
    // MARK: - Audio Track Controls
    
    func getAudioTracksDetailed() -> [(Int, String, String)] {
        guard let media = currentMedia else { return [] }
        
        var result: [(Int, String, String)] = []
        var trackNumber = 1
        
        // VLC media descriptors for audio tracks
        let audioTrackInfo = media.mediaAsStringValueForOption(VLCAudioTrackOptionsKey) ?? ""
        if audioTrackInfo.isEmpty {
            return []
        }
        
        // Parse audio track info and create entries
        // Format varies by source, so provide generic numbered audio tracks
        let trackCount = media.numberOfAudioTracks()
        for i in 0..<Int32(trackCount) {
            let trackName = media.audioTrackNameAtIndex(i)
            let displayName = !trackName.isEmpty ? trackName : "Audio Track \(trackNumber)"
            result.append((Int(i), displayName, ""))
            trackNumber += 1
        }
        
        return result
    }
    
    func getAudioTracks() -> [(Int, String)] {
        return getAudioTracksDetailed().map { ($0.0, $0.1) }
    }
    
    func setAudioTrack(_ id: Int) {
        setAudioTrack(id)
    }
    
    func setAudioTrack(id: Int) {
        eventQueue.async { [weak self] in
            guard let self, let media = self.currentMedia else { return }
            
            if id >= 0 && id < Int(media.numberOfAudioTracks()) {
                media.audioTrackIndexForAudioDescription(id)
                DispatchQueue.main.async { [weak self] in
                    guard let self else { return }
                    self.delegate?.renderer(self, subtitleTrackDidChange: id)
                }
            }
        }
    }
    
    // MARK: - Subtitle Track Controls
    
    func getSubtitleTracks() -> [(Int, String)] {
        guard let media = currentMedia else { return [] }
        
        var result: [(Int, String)] = []
        var trackNumber = 1
        
        let subTrackCount = Int(media.numberOfSubtitleTracks())
        for i in 0..<subTrackCount {
            let trackName = media.subtitleTrackNameAtIndex(Int32(i))
            let displayName = !trackName.isEmpty ? trackName : "Subtitle Track \(trackNumber)"
            result.append((i, displayName))
            trackNumber += 1
        }
        
        return result
    }
    
    func setSubtitleTrack(_ id: Int) {
        eventQueue.async { [weak self] in
            guard let self, let media = self.currentMedia else { return }
            
            if id >= 0 && id < Int(media.numberOfSubtitleTracks()) {
                media.subtitleTrackIndexForSubtitleDescription(Int32(id))
                DispatchQueue.main.async { [weak self] in
                    guard let self else { return }
                    self.delegate?.renderer(self, subtitleTrackDidChange: id)
                }
            }
        }
    }
    
    func disableSubtitles() {
        eventQueue.async { [weak self] in
            guard let self, let media = self.currentMedia else { return }
            // Disable subtitles by setting track to -1
            media.subtitleTrackIndexForSubtitleDescription(-1)
        }
    }
    
    func refreshSubtitleOverlay() {
        // VLC handles subtitle rendering automatically through native libass
        // No manual refresh needed
    }
    
    // MARK: - External Subtitles
    
    func loadExternalSubtitles(urls: [String]) {
        guard let player = mediaPlayer, let media = currentMedia else { return }
        
        eventQueue.async {
            for urlString in urls {
                if let url = URL(string: urlString) {
                    player.addPlaybackSlave(url, type: VLCMediaPlaybackSlaveType.subtitle, enforce: false)
                }
            }
        }
    }
    
    func clearSubtitleCache() {
        // VLC handles subtitle caching internally
    }
    
    // MARK: - Event Handlers
    
    @objc private func mediaPlayerTimeChanged() {
        guard let player = mediaPlayer else { return }
        
        let position = Double(player.time.value) / 1000.0  // Convert from milliseconds
        let duration = Double(player.media?.length.value ?? 0) / 1000.0
        
        cachedPosition = position
        cachedDuration = duration
        
        DispatchQueue.main.async { [weak self] in
            guard let self else { return }
            self.delegate?.renderer(self, didUpdatePosition: position, duration: duration)
        }
    }
    
    @objc private func mediaPlayerStateChanged() {
        guard let player = mediaPlayer else { return }
        
        let state = player.state
        
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
            
        case .buffering:
            isLoading = true
            DispatchQueue.main.async { [weak self] in
                guard let self else { return }
                self.delegate?.renderer(self, didChangeLoading: true)
            }
            
        case .stopped, .ended, .error:
            isPaused = true
            DispatchQueue.main.async { [weak self] in
                guard let self else { return }
                self.delegate?.renderer(self, didChangePause: true)
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
    func setAudioTrack(id: Int) { }
    func getSubtitleTracks() -> [(Int, String)] { [] }
    func setSubtitleTrack(id: Int) { }
    func disableSubtitles() { }
    func refreshSubtitleOverlay() { }
    func loadExternalSubtitles(urls: [String]) { }
    func clearSubtitleCache() { }
    var isPausedState: Bool { true }
    weak var delegate: VLCRendererDelegate?
}

#endif  // canImport(MobileVLCKit)

