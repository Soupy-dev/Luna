//
//  VLCPlayer.swift
//  Luna
//
//  VLC Player SwiftUI wrapper with anime audio and auto-subtitle features
//  iOS-only implementation - tvOS uses MPV
//

import SwiftUI
import AVFoundation
import Combine

#if os(iOS)

struct VLCPlayer: UIViewControllerRepresentable {
    let url: URL
    var headers: [String: String]? = nil
    var preset: PlayerPreset? = nil
    var mediaInfo: MediaInfo? = nil
    @ObservedObject var playerState: VLCPlayerState
    
    func makeUIViewController(context: Context) -> VLCPlayerViewController {
        let controller = VLCPlayerViewController()
        controller.playerState = playerState
        controller.mediaInfo = mediaInfo
        controller.pendingURL = url
        controller.pendingHeaders = headers
        controller.pendingPreset = preset
        return controller
    }
    
    func updateUIViewController(_ uiViewController: VLCPlayerViewController, context: Context) {}
}

// MARK: - VLC Player State Management

class VLCPlayerState: NSObject, ObservableObject {
    @Published var isPlaying = false
    @Published var position: Double = 0
    @Published var duration: Double = 0
    @Published var isLoading = false
    @Published var showControls = true
    @Published var currentPlaybackSpeed: Double = 1.0
    @Published var audioTracks: [(Int, String, String)] = []
    @Published var subtitleTracks: [(Int, String)] = []
    @Published var selectedAudioLanguage = "en"
    @Published var enableAutoSubtitles = true
    
    private var hideControlsTimer: Timer?
    
    func scheduleHideControls() {
        hideControlsTimer?.invalidate()
        showControls = true
        hideControlsTimer = Timer.scheduledTimer(withTimeInterval: 5.0, repeats: false) { [weak self] _ in
            withAnimation { self?.showControls = false }
        }
    }
}

// MARK: - VLC Player View Controller

class VLCPlayerViewController: UIViewController, VLCRendererDelegate, UIGestureRecognizerDelegate {
    private let vlcRenderer: VLCRenderer
    var playerState: VLCPlayerState?
    var mediaInfo: MediaInfo?
    
    var pendingURL: URL?
    var pendingHeaders: [String: String]?
    var pendingPreset: PlayerPreset?
    
    private let controlsContainer = UIView()
    private let topControlsView = UIView()
    private let bottomControlsView = UIView()
    private let centerPlayButton = UIButton(type: .system)
    private let progressBar = UISlider()
    private let timeLabel = UILabel()
    private let durationLabel = UILabel()
    private var isSeeking = false
    private let bufferingSpinner = UIActivityIndicatorView(style: .large)
    
    private var positionUpdateTimer: Timer?
    private var lastPlayedTime: Double?
    
    override init(nibName nibNameOrNil: String?, bundle nibBundleOrNil: Bundle?) {
        let displayLayer = AVSampleBufferDisplayLayer()
        self.vlcRenderer = VLCRenderer(displayLayer: displayLayer)
        super.init(nibName: nibNameOrNil, bundle: nibBundleOrNil)
    }
    
    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }
    
    override func viewDidLoad() {
        super.viewDidLoad()
        view.backgroundColor = .black
        vlcRenderer.delegate = self
        
        // Load VLC preferences from settings
        let enableSubtitles = UserDefaults.standard.bool(forKey: "enableSubtitlesByDefault")
        let defaultSubtitleLanguage = UserDefaults.standard.string(forKey: "defaultSubtitleLanguage") ?? "eng"
        let preferredAnimeAudio = UserDefaults.standard.string(forKey: "preferredAnimeAudioLanguage") ?? "jpn"
        
        vlcRenderer.enableAutoSubtitles(enableSubtitles)
        vlcRenderer.setPreferredAudioLanguage(preferredAnimeAudio)
        vlcRenderer.setAnimeAudioLanguage(preferredAnimeAudio)
        
        playerState?.enableAutoSubtitles = enableSubtitles
        playerState?.selectedAudioLanguage = preferredAnimeAudio
        
        setupUI()
        setupGestureRecognizers()
        observePlayerState()
        
        do {
            try vlcRenderer.start()
        } catch {
            Logger.shared.log("Failed to start VLC: \(error)", type: "Error")
        }
    }
    
    override func viewDidAppear(_ animated: Bool) {
        super.viewDidAppear(animated)
        
        Logger.shared.log("[VLCPlayer] viewDidAppear called", type: "Stream")
        Logger.shared.log("[VLCPlayer] rendering view bounds: \(vlcRenderer.getRenderingView().bounds)", type: "Stream")
        Logger.shared.log("[VLCPlayer] rendering view superview: \(vlcRenderer.getRenderingView().superview != nil ? "set" : "nil")", type: "Stream")
        
        // Load media after view is fully visible and VLC is initialized
        if let url = pendingURL {
            Logger.shared.log("[VLCPlayer] Loading pending URL: \(url.absoluteString)", type: "Stream")
            Logger.shared.log("[VLCPlayer] Headers: \(pendingHeaders?.count ?? 0) preset: \(pendingPreset?.id.rawValue ?? "nil")", type: "Stream")
            load(url: url, headers: pendingHeaders, preset: pendingPreset)
            pendingURL = nil
            pendingHeaders = nil
            pendingPreset = nil
        } else {
            Logger.shared.log("[VLCPlayer] No pending URL to load", type: "Stream")
        }
    }
    
    override func viewDidLayoutSubviews() {
        super.viewDidLayoutSubviews()
        
        // Ensure VLC rendering view has proper frame
        let renderingView = vlcRenderer.getRenderingView()
        if renderingView.bounds.size != view.bounds.size {
            Logger.shared.log("[VLCPlayer] Updating VLC view frame: \(view.bounds)", type: "Stream")
        }
    }
    
    private func setupUI() {
        // Main rendering view
        let renderingView = vlcRenderer.getRenderingView()
        view.addSubview(renderingView)
        renderingView.translatesAutoresizingMaskIntoConstraints = false
        
        NSLayoutConstraint.activate([
            renderingView.topAnchor.constraint(equalTo: view.topAnchor),
            renderingView.bottomAnchor.constraint(equalTo: view.bottomAnchor),
            renderingView.leadingAnchor.constraint(equalTo: view.leadingAnchor),
            renderingView.trailingAnchor.constraint(equalTo: view.trailingAnchor)
        ])
        
        // Controls container
        view.addSubview(controlsContainer)
        controlsContainer.translatesAutoresizingMaskIntoConstraints = false
        controlsContainer.alpha = 0.8
        
        NSLayoutConstraint.activate([
            controlsContainer.topAnchor.constraint(equalTo: view.topAnchor),
            controlsContainer.bottomAnchor.constraint(equalTo: view.bottomAnchor),
            controlsContainer.leadingAnchor.constraint(equalTo: view.leadingAnchor),
            controlsContainer.trailingAnchor.constraint(equalTo: view.trailingAnchor)
        ])
        
        // Top controls (back button, title)
        topControlsView.backgroundColor = UIColor.black.withAlphaComponent(0.4)
        controlsContainer.addSubview(topControlsView)
        topControlsView.translatesAutoresizingMaskIntoConstraints = false
        
        NSLayoutConstraint.activate([
            topControlsView.topAnchor.constraint(equalTo: controlsContainer.topAnchor),
            topControlsView.leadingAnchor.constraint(equalTo: controlsContainer.leadingAnchor),
            topControlsView.trailingAnchor.constraint(equalTo: controlsContainer.trailingAnchor),
            topControlsView.heightAnchor.constraint(equalToConstant: 50)
        ])
        
        let backButton = UIButton(type: .system)
        backButton.setTitle("← Back", for: .normal)
        backButton.tintColor = .white
        backButton.addTarget(self, action: #selector(backButtonTapped), for: .touchUpInside)
        topControlsView.addSubview(backButton)
        backButton.translatesAutoresizingMaskIntoConstraints = false
        backButton.leadingAnchor.constraint(equalTo: topControlsView.leadingAnchor, constant: 12).isActive = true
        backButton.centerYAnchor.constraint(equalTo: topControlsView.centerYAnchor).isActive = true
        
        // Center play button
        centerPlayButton.setImage(UIImage(systemName: "play.fill"), for: .normal)
        centerPlayButton.tintColor = .white
        centerPlayButton.titleLabel?.font = UIFont.systemFont(ofSize: 48)
        centerPlayButton.addTarget(self, action: #selector(togglePlayPause), for: .touchUpInside)
        controlsContainer.addSubview(centerPlayButton)
        centerPlayButton.translatesAutoresizingMaskIntoConstraints = false
        
        NSLayoutConstraint.activate([
            centerPlayButton.centerXAnchor.constraint(equalTo: controlsContainer.centerXAnchor),
            centerPlayButton.centerYAnchor.constraint(equalTo: controlsContainer.centerYAnchor),
            centerPlayButton.widthAnchor.constraint(equalToConstant: 80),
            centerPlayButton.heightAnchor.constraint(equalToConstant: 80)
        ])
        
        // Bottom controls
        bottomControlsView.backgroundColor = UIColor.black.withAlphaComponent(0.4)
        controlsContainer.addSubview(bottomControlsView)
        bottomControlsView.translatesAutoresizingMaskIntoConstraints = false
        
        NSLayoutConstraint.activate([
            bottomControlsView.bottomAnchor.constraint(equalTo: controlsContainer.bottomAnchor),
            bottomControlsView.leadingAnchor.constraint(equalTo: controlsContainer.leadingAnchor),
            bottomControlsView.trailingAnchor.constraint(equalTo: controlsContainer.trailingAnchor),
            bottomControlsView.heightAnchor.constraint(greaterThanOrEqualToConstant: 80)
        ])
        
        // Progress bar (slider)
        progressBar.minimumValue = 0
        progressBar.maximumValue = 1
        progressBar.value = 0
        progressBar.minimumTrackTintColor = .systemBlue
        progressBar.maximumTrackTintColor = .white.withAlphaComponent(0.3)
        progressBar.addTarget(self, action: #selector(progressBarChanged(_:)), for: .valueChanged)
        progressBar.addTarget(self, action: #selector(progressBarTouchDown(_:)), for: .touchDown)
        progressBar.addTarget(self, action: #selector(progressBarTouchUp(_:)), for: [.touchUpInside, .touchUpOutside])
        bottomControlsView.addSubview(progressBar)
        progressBar.translatesAutoresizingMaskIntoConstraints = false
        
        NSLayoutConstraint.activate([
            progressBar.topAnchor.constraint(equalTo: bottomControlsView.topAnchor, constant: 8),
            progressBar.leadingAnchor.constraint(equalTo: bottomControlsView.leadingAnchor, constant: 12),
            progressBar.trailingAnchor.constraint(equalTo: bottomControlsView.trailingAnchor, constant: -12),
            progressBar.heightAnchor.constraint(equalToConstant: 30)
        ])
        
        // Time display
        timeLabel.textColor = .white
        timeLabel.font = UIFont.systemFont(ofSize: 12)
        timeLabel.text = "00:00"
        bottomControlsView.addSubview(timeLabel)
        timeLabel.translatesAutoresizingMaskIntoConstraints = false
        
        durationLabel.textColor = .white
        durationLabel.font = UIFont.systemFont(ofSize: 12)
        durationLabel.text = "00:00"
        bottomControlsView.addSubview(durationLabel)
        durationLabel.translatesAutoresizingMaskIntoConstraints = false
        
        NSLayoutConstraint.activate([
            timeLabel.leadingAnchor.constraint(equalTo: bottomControlsView.leadingAnchor, constant: 12),
            timeLabel.topAnchor.constraint(equalTo: progressBar.bottomAnchor, constant: 8),
            durationLabel.trailingAnchor.constraint(equalTo: bottomControlsView.trailingAnchor, constant: -12),
            durationLabel.topAnchor.constraint(equalTo: progressBar.bottomAnchor, constant: 8)
        ])
        
        // Buffering spinner
        bufferingSpinner.color = .white
        bufferingSpinner.hidesWhenStopped = true
        controlsContainer.addSubview(bufferingSpinner)
        bufferingSpinner.translatesAutoresizingMaskIntoConstraints = false
        
        NSLayoutConstraint.activate([
            bufferingSpinner.centerXAnchor.constraint(equalTo: controlsContainer.centerXAnchor),
            bufferingSpinner.centerYAnchor.constraint(equalTo: controlsContainer.centerYAnchor)
        ])
        
        // Control buttons (audio, subtitles, speed)
        setupBottomControlButtons()
    }
    
    private func setupBottomControlButtons() {
        let buttonsStackView = UIStackView()
        buttonsStackView.axis = .horizontal
        buttonsStackView.spacing = 12
        buttonsStackView.alignment = .center
        buttonsStackView.distribution = .fillEqually
        bottomControlsView.addSubview(buttonsStackView)
        buttonsStackView.translatesAutoresizingMaskIntoConstraints = false
        
        NSLayoutConstraint.activate([
            buttonsStackView.leadingAnchor.constraint(equalTo: bottomControlsView.leadingAnchor, constant: 12),
            buttonsStackView.trailingAnchor.constraint(equalTo: bottomControlsView.trailingAnchor, constant: -12),
            buttonsStackView.topAnchor.constraint(equalTo: timeLabel.bottomAnchor, constant: 12),
            buttonsStackView.bottomAnchor.constraint(equalTo: bottomControlsView.bottomAnchor, constant: -12),
            buttonsStackView.heightAnchor.constraint(equalToConstant: 40)
        ])
        
        // Audio track button
        let audioButton = UIButton(type: .system)
        audioButton.setImage(UIImage(systemName: "speaker.wave.2"), for: .normal)
        audioButton.tintColor = .white
        audioButton.showsMenuAsPrimaryAction = true
        audioButton.menu = createAudioMenu()
        audioButton.tag = 997  // Tag for finding button later
        buttonsStackView.addArrangedSubview(audioButton)
        
        // Subtitle button
        let subtitleButton = UIButton(type: .system)
        subtitleButton.setImage(UIImage(systemName: "captions.bubble"), for: .normal)
        subtitleButton.tintColor = .white
        subtitleButton.showsMenuAsPrimaryAction = true
        subtitleButton.menu = createSubtitleMenu()
        subtitleButton.tag = 998  // Tag for finding button later
        buttonsStackView.addArrangedSubview(subtitleButton)
        
        // Speed button
        let speedButton = UIButton(type: .system)
        let cfg = UIImage.SymbolConfiguration(pointSize: 16, weight: .semibold)
        let img = UIImage(systemName: "hare.fill", withConfiguration: cfg)
        speedButton.setImage(img, for: .normal)
        speedButton.tintColor = .white
        speedButton.showsMenuAsPrimaryAction = true
        speedButton.menu = createSpeedMenu()
        speedButton.tag = 999  // Tag for finding button later
        buttonsStackView.addArrangedSubview(speedButton)
    }
    
    private func setupGestureRecognizers() {
        // Single tap to toggle controls - lower priority
        let tapGesture = UITapGestureRecognizer(target: self, action: #selector(handleTap))
        tapGesture.delegate = self
        tapGesture.numberOfTapsRequired = 1
        view.addGestureRecognizer(tapGesture)
        
        // Two-finger tap to toggle play/pause
        let twoFingerTapGesture = UITapGestureRecognizer(target: self, action: #selector(togglePlayPause))
        twoFingerTapGesture.numberOfTouchesRequired = 2
        twoFingerTapGesture.numberOfTapsRequired = 1
        view.addGestureRecognizer(twoFingerTapGesture)
        
        // Double tap left side to go back 10s
        let doubleTapLeftGesture = UITapGestureRecognizer(target: self, action: #selector(handleDoubleTapLeft(_:)))
        doubleTapLeftGesture.numberOfTapsRequired = 2
        doubleTapLeftGesture.numberOfTouchesRequired = 1
        view.addGestureRecognizer(doubleTapLeftGesture)
        
        // Double tap right side to skip forward 10s
        let doubleTapRightGesture = UITapGestureRecognizer(target: self, action: #selector(handleDoubleTapRight(_:)))
        doubleTapRightGesture.numberOfTapsRequired = 2
        doubleTapRightGesture.numberOfTouchesRequired = 1
        view.addGestureRecognizer(doubleTapRightGesture)
        
        // Prevent single tap from firing when double tapping
        tapGesture.require(toFail: doubleTapLeftGesture)
        tapGesture.require(toFail: doubleTapRightGesture)
        
        // Long press for 2x speed
        let longPressGesture = UILongPressGestureRecognizer(target: self, action: #selector(handleLongPress(_:)))
        longPressGesture.minimumPressDuration = 0.5
        view.addGestureRecognizer(longPressGesture)
    }
    
    // Allow gestures to work simultaneously when needed
    func gestureRecognizer(_ gestureRecognizer: UIGestureRecognizer, shouldRecognizeSimultaneouslyWith otherGestureRecognizer: UIGestureRecognizer) -> Bool {
        return false
    }
    
    @objc private func backButtonTapped() {
        vlcRenderer.stop()
        if presentingViewController != nil {
            dismiss(animated: true, completion: nil)
        } else {
            view.window?.rootViewController?.dismiss(animated: true, completion: nil)
        }
    }
    
    private func observePlayerState() {
        playerState?.$showControls
            .sink { [weak self] show in
                UIView.animate(withDuration: 0.3) {
                    self?.controlsContainer.alpha = show ? 1.0 : 0.0
                }
                self?.updateCenterPlayButtonVisibility()
            }
            .store(in: &cancellables)
        
        // Start with controls visible
        playerState?.scheduleHideControls()
    }
    
    private func updateCenterPlayButtonVisibility() {
        let isLoading = playerState?.isLoading ?? false
        let isPaused = !(playerState?.isPlaying ?? false)
        let showControls = playerState?.showControls ?? false
        
        // Show play button if: not loading AND (paused OR controls are visible)
        let shouldShow = !isLoading && (isPaused || showControls)
        
        UIView.animate(withDuration: 0.3) {
            self.centerPlayButton.alpha = shouldShow ? 1.0 : 0.0
        }
    }
    
    private var cancellables = Set<AnyCancellable>()
    
    @objc private func handleTap() {
        if playerState?.showControls == true {
            // Hide controls
            playerState?.showControls = false
        } else {
            // Show and schedule hide
            playerState?.scheduleHideControls()
        }
    }
    
    @objc private func handleLongPress(_ gesture: UILongPressGestureRecognizer) {
        if gesture.state == .began {
            vlcRenderer.setSpeed(2.0)
            playerState?.currentPlaybackSpeed = 2.0
            Logger.shared.log("[VLCPlayer] Long press: 2x speed", type: "Stream")
        } else if gesture.state == .ended {
            vlcRenderer.setSpeed(1.0)
            playerState?.currentPlaybackSpeed = 1.0
            Logger.shared.log("[VLCPlayer] Long press released: 1x speed", type: "Stream")
        }
    }
    
    @objc private func togglePlayPause() {
        vlcRenderer.togglePlayPause()
        playerState?.scheduleHideControls()
    }
    
    @objc private func progressBarTouchDown(_ slider: UISlider) {
        isSeeking = true
        playerState?.showControls = true
    }
    
    @objc private func progressBarChanged(_ slider: UISlider) {
        if isSeeking {
            let duration = playerState?.duration ?? 0
            let newPosition = Double(slider.value) * duration
            timeLabel.text = formatTime(newPosition)
        }
    }
    
    @objc private func progressBarTouchUp(_ slider: UISlider) {
        let duration = playerState?.duration ?? 0
        let newPosition = Double(slider.value) * duration
        vlcRenderer.seek(to: newPosition)
        isSeeking = false
        playerState?.scheduleHideControls()
    }
    
    @objc private func handleDoubleTapLeft(_ gesture: UITapGestureRecognizer) {
        let location = gesture.location(in: view)
        // Only trigger if tap is on left half of screen
        if location.x < view.bounds.width / 2 {
            vlcRenderer.seek(by: -10)
            Logger.shared.log("[VLCPlayer] Seek back 10s", type: "Stream")
            playerState?.scheduleHideControls()
        }
    }
    
    @objc private func handleDoubleTapRight(_ gesture: UITapGestureRecognizer) {
        let location = gesture.location(in: view)
        // Only trigger if tap is on right half of screen
        if location.x >= view.bounds.width / 2 {
            vlcRenderer.seek(by: 10)
            Logger.shared.log("[VLCPlayer] Seek forward 10s", type: "Stream")
            playerState?.scheduleHideControls()
        }
    }
    
    private func createAudioMenu() -> UIMenu {
        let audioTracks = vlcRenderer.getAudioTracksDetailed()
        let currentTrack = vlcRenderer.getCurrentAudioTrackId()
        
        if audioTracks.isEmpty {
            let noTracksAction = UIAction(title: "No audio tracks available", attributes: .disabled) { _ in }
            return UIMenu(title: "Audio Track", children: [noTracksAction])
        }
        
        let actions = audioTracks.map { track in
            let isSelected = (track.0 == currentTrack)
            return UIAction(
                title: track.1,
                state: isSelected ? .on : .off
            ) { [weak self] _ in
                self?.vlcRenderer.setAudioTrack(id: track.0)
                // Recreate menu to update checkmarks
                if let audioButton = self?.view.viewWithTag(997) as? UIButton {
                    audioButton.menu = self?.createAudioMenu()
                }
            }
        }
        return UIMenu(title: "Audio Track", children: actions)
    }
    
    private func createSubtitleMenu() -> UIMenu {
        let subtitleTracks = vlcRenderer.getSubtitleTracksDetailed()
        let currentTrack = vlcRenderer.getCurrentSubtitleTrackId()
        
        var actions: [UIAction] = [
            UIAction(
                title: "None",
                state: (currentTrack == -1) ? .on : .off
            ) { [weak self] _ in
                self?.vlcRenderer.disableSubtitles()
                // Recreate menu to update checkmarks
                if let subtitleButton = self?.view.viewWithTag(998) as? UIButton {
                    subtitleButton.menu = self?.createSubtitleMenu()
                }
            }
        ]
        
        actions += subtitleTracks.map { track in
            let isSelected = (track.0 == currentTrack)
            return UIAction(
                title: track.1,
                state: isSelected ? .on : .off
            ) { [weak self] _ in
                self?.vlcRenderer.setSubtitleTrack(id: track.0)
                // Recreate menu to update checkmarks
                if let subtitleButton = self?.view.viewWithTag(998) as? UIButton {
                    subtitleButton.menu = self?.createSubtitleMenu()
                }
            }
        }
        return UIMenu(title: "Subtitles", children: actions)
    }
    
    private func createSpeedMenu() -> UIMenu {
        let speeds = [0.5, 0.75, 1.0, 1.25, 1.5, 2.0]
        let currentSpeed = playerState?.currentPlaybackSpeed ?? 1.0
        
        let actions = speeds.map { speed in
            let isSelected = abs(currentSpeed - speed) < 0.01
            return UIAction(
                title: "\(speed)x",
                state: isSelected ? .on : .off
            ) { [weak self] _ in
                self?.vlcRenderer.setSpeed(speed)
                self?.playerState?.currentPlaybackSpeed = speed
                // Recreate menu to update checkmarks
                if let speedButton = self?.view.viewWithTag(999) as? UIButton {
                    speedButton.menu = self?.createSpeedMenu()
                }
            }
        }
        return UIMenu(title: "Playback Speed", children: actions)
    }
    
    func load(url: URL, headers: [String: String]?, preset: PlayerPreset?) {
        Logger.shared.log("[VLCPlayer.load] ENTRY with URL: \(url.absoluteString)", type: "Stream")
        Logger.shared.log("[VLCPlayer.load] Headers count: \(headers?.count ?? 0), preset: \(preset?.id.rawValue ?? "nil")", type: "Stream")
        
        let defaultPreset = PlayerPreset(id: .hd1080, title: "HD 1080p", summary: "Default", stream: nil, commands: [])
        vlcRenderer.load(url: url, with: preset ?? defaultPreset, headers: headers)
        
        // Prepare to seek to last position if mediaInfo is set
        if let info = mediaInfo {
            prepareSeekToLastPosition(for: info)
        }
        
        Logger.shared.log("[VLCPlayer.load] EXIT - load() delegated to vlcRenderer", type: "Stream")
    }
    
    deinit {
        positionUpdateTimer?.invalidate()
        vlcRenderer.stop()
    }
    
    // MARK: - VLCRendererDelegate
    
    func renderer(_ renderer: VLCRenderer, didUpdatePosition position: Double, duration: Double) {
        DispatchQueue.main.async {
            self.playerState?.position = position
            self.playerState?.duration = duration
            
            // Only update slider if user is not currently seeking
            if !self.isSeeking && duration > 0 {
                self.progressBar.value = Float(position / duration)
            }
            
            self.timeLabel.text = self.formatTime(position)
            self.durationLabel.text = self.formatTime(duration)
            
            // Record progress
            self.recordProgress(position: position, duration: duration)
        }
    }
    
    func renderer(_ renderer: VLCRenderer, didChangePause isPaused: Bool) {
        DispatchQueue.main.async {
            self.playerState?.isPlaying = !isPaused
            let imageName = isPaused ? "play.fill" : "pause.fill"
            self.centerPlayButton.setImage(UIImage(systemName: imageName), for: .normal)
            self.updateCenterPlayButtonVisibility()
        }
    }
    
    func renderer(_ renderer: VLCRenderer, didChangeLoading isLoading: Bool) {
        DispatchQueue.main.async {
            self.playerState?.isLoading = isLoading
            if isLoading {
                self.bufferingSpinner.startAnimating()
            } else {
                self.bufferingSpinner.stopAnimating()
            }
            self.updateCenterPlayButtonVisibility()
        }
    }
    
    func renderer(_ renderer: VLCRenderer, didBecomeReadyToSeek: Bool) {
        if didBecomeReadyToSeek, let lastTime = lastPlayedTime, lastTime > 5.0 {
            vlcRenderer.seek(to: lastTime)
            lastPlayedTime = nil
        }
    }
    
    func renderer(_ renderer: VLCRenderer, getSubtitleForTime time: Double) -> NSAttributedString? {
        return nil
    }
    
    func renderer(_ renderer: VLCRenderer, getSubtitleStyle: Void) -> SubtitleStyle {
        return SubtitleStyle(foregroundColor: .white, strokeColor: .black, strokeWidth: 1.5, fontSize: 16.0, isVisible: true)
    }
    
    func renderer(_ renderer: VLCRenderer, subtitleTrackDidChange trackId: Int) {}
    
    func rendererDidChangeTracks(_ renderer: VLCRenderer) {
        playerState?.audioTracks = renderer.getAudioTracksDetailed()
        playerState?.subtitleTracks = renderer.getSubtitleTracksDetailed()
    }
    
    // MARK: - Progress Tracking
    
    private func recordProgress(position: Double, duration: Double) {
        guard duration.isFinite, duration > 0, position >= 0, let info = mediaInfo else { return }
        
        switch info {
        case .movie(let id, let title, let posterURL):
            ProgressManager.shared.updateMovieProgress(movieId: id, title: title, currentTime: position, totalDuration: duration, posterURL: posterURL)
        case .episode(let showId, let seasonNumber, let episodeNumber, let showTitle, let showPosterURL):
            ProgressManager.shared.updateEpisodeProgress(showId: showId, seasonNumber: seasonNumber, episodeNumber: episodeNumber, currentTime: position, totalDuration: duration, showTitle: showTitle, showPosterURL: showPosterURL)
        }
    }
    
    private func prepareSeekToLastPosition(for mediaInfo: MediaInfo) {
        var lastTime: Double?
        
        switch mediaInfo {
        case .movie(let id, let title, _):
            lastTime = ProgressManager.shared.getMovieCurrentTime(movieId: id, title: title)
        case .episode(let showId, let seasonNumber, let episodeNumber, _, _):
            lastTime = ProgressManager.shared.getEpisodeCurrentTime(showId: showId, seasonNumber: seasonNumber, episodeNumber: episodeNumber)
        }
        
        if let time = lastTime, time > 5.0 {
            self.lastPlayedTime = time
        }
    }
    
    private func formatTime(_ seconds: Double) -> String {
        let hours = Int(seconds) / 3600
        let minutes = (Int(seconds) % 3600) / 60
        let secs = Int(seconds) % 60
        
        if hours > 0 {
            return String(format: "%d:%02d:%02d", hours, minutes, secs)
        } else {
            return String(format: "%d:%02d", minutes, secs)
        }
    }
}

// MARK: - VLC Player Controls with Anime Audio & Subtitles

struct VLCPlayerControlsView: View {
    @State private var showAudioLanguageMenu = false
    @State private var showSubtitleMenu = false
    @State private var selectedAudioLanguage = "en"
    @State private var enableAutoSubtitles = true
    @State private var availableSubtitles: [String] = []
    
    let renderer: VLCRenderer
    
    var body: some View {
        VStack(spacing: 12) {
            HStack(spacing: 16) {
                // Anime Audio Language Button (VLC-exclusive)
                Menu {
                    Button("English") { selectedAudioLanguage = "en" }
                    Button("Japanese") { selectedAudioLanguage = "ja" }
                    Button("Chinese") { selectedAudioLanguage = "zh" }
                    Button("Korean") { selectedAudioLanguage = "ko" }
                    Button("Spanish") { selectedAudioLanguage = "es" }
                } label: {
                    HStack(spacing: 4) {
                        Image(systemName: "speaker.wave.2")
                        Text("Audio")
                    }
                    .font(.caption2)
                    .padding(.vertical, 6)
                    .padding(.horizontal, 10)
                    .background(Color.white.opacity(0.1))
                    .cornerRadius(6)
                    .foregroundColor(.white)
                }
                
                // Auto-Subtitles Toggle (VLC-exclusive)
                Button(action: { enableAutoSubtitles.toggle() }) {
                    HStack(spacing: 4) {
                        Image(systemName: enableAutoSubtitles ? "captions.bubble.fill" : "captions.bubble")
                        Text("Auto Subs")
                    }
                    .font(.caption2)
                    .padding(.vertical, 6)
                    .padding(.horizontal, 10)
                    .background(enableAutoSubtitles ? Color.blue.opacity(0.3) : Color.white.opacity(0.1))
                    .cornerRadius(6)
                    .foregroundColor(.white)
                }
                .onChange(of: enableAutoSubtitles) { newValue in
                    renderer.enableAutoSubtitles(newValue)
                }
                
                // Subtitle Selection Menu (VLC-exclusive)
                Menu {
                    Button("Off") { renderer.disableSubtitles() }
                    ForEach(0..<availableSubtitles.count, id: \.self) { index in
                        Button(availableSubtitles[index]) {
                            renderer.setSubtitleTrack(id: index)
                        }
                    }
                } label: {
                    HStack(spacing: 4) {
                        Image(systemName: "textbox")
                        Text("Subs")
                    }
                    .font(.caption2)
                    .padding(.vertical, 6)
                    .padding(.horizontal, 10)
                    .background(Color.white.opacity(0.1))
                    .cornerRadius(6)
                    .foregroundColor(.white)
                }
                
                Spacer()
            }
            .padding(.horizontal, 12)
        }
        .onAppear {
            availableSubtitles = renderer.getAvailableSubtitles()
            renderer.setPreferredAudioLanguage(selectedAudioLanguage)
            renderer.enableAutoSubtitles(enableAutoSubtitles)
        }
    }
}

#else

// tvOS/macOS: Stub implementations
class VLCPlayerState: NSObject, ObservableObject {
    @Published var isPlaying = false
    @Published var position: Double = 0
    @Published var duration: Double = 0
    @Published var isLoading = false
    @Published var showControls = true
    @Published var currentPlaybackSpeed: Double = 1.0
    @Published var audioTracks: [(Int, String, String)] = []
    @Published var subtitleTracks: [(Int, String)] = []
    @Published var selectedAudioLanguage = "en"
    @Published var enableAutoSubtitles = true
    
    func scheduleHideControls() {}
}

struct VLCPlayer: UIViewControllerRepresentable {
    let url: URL
    var headers: [String: String]? = nil
    var preset: PlayerPreset? = nil
    var mediaInfo: MediaInfo? = nil
    @ObservedObject var playerState: VLCPlayerState = VLCPlayerState()
    
    func makeUIViewController(context: Context) -> UIViewController {
        return UIViewController()
    }
    
    func updateUIViewController(_ uiViewController: UIViewController, context: Context) {}
}

struct VLCPlayerControlsView: View {
    let renderer: VLCRenderer
    
    var body: some View {
        EmptyView()
    }
}

#endif
