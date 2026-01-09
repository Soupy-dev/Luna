//
//  VLCPlayer.swift
//  Luna
//
//  VLC Player SwiftUI wrapper with anime audio and auto-subtitle features
//  iOS-only implementation - tvOS uses MPV
//

import SwiftUI
import AVFoundation

#if os(iOS)

struct VLCPlayer: UIViewControllerRepresentable {
    let url: URL
    var headers: [String: String]? = nil
    var preset: PlayerPreset? = nil
    @ObservedObject var playerState: VLCPlayerState
    
    func makeUIViewController(context: Context) -> VLCPlayerViewController {
        let controller = VLCPlayerViewController()
        controller.playerState = playerState
        controller.load(url: url, headers: headers, preset: preset)
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
    @Published var audioTracks: [VLCRenderer.AudioTrack] = []
    @Published var subtitleTracks: [VLCRenderer.SubtitleTrack] = []
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

class VLCPlayerViewController: UIViewController, VLCRendererDelegate {
    private let vlcRenderer: VLCRenderer
    var playerState: VLCPlayerState?
    
    private let controlsContainer = UIView()
    private let topControlsView = UIView()
    private let bottomControlsView = UIView()
    private let centerPlayButton = UIButton(type: .system)
    private let progressBar = UIProgressView(progressViewStyle: .bar)
    private let timeLabel = UILabel()
    private let durationLabel = UILabel()
    
    private var positionUpdateTimer: Timer?
    
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
        vlcRenderer.setPreferredAudioLanguage(defaultSubtitleLanguage)
        vlcRenderer.setAnimeAudioLanguage(preferredAnimeAudio)
        
        playerState?.enableAutoSubtitles = enableSubtitles
        playerState?.selectedAudioLanguage = defaultSubtitleLanguage
        
        setupUI()
        setupGestureRecognizers()
        
        do {
            try vlcRenderer.start()
        } catch {
            Logger.shared.log("Failed to start VLC: \(error)", type: "Error")
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
        
        // Progress bar
        progressBar.tintColor = .systemBlue
        bottomControlsView.addSubview(progressBar)
        progressBar.translatesAutoresizingMaskIntoConstraints = false
        
        NSLayoutConstraint.activate([
            progressBar.topAnchor.constraint(equalTo: bottomControlsView.topAnchor),
            progressBar.leadingAnchor.constraint(equalTo: bottomControlsView.leadingAnchor),
            progressBar.trailingAnchor.constraint(equalTo: bottomControlsView.trailingAnchor),
            progressBar.heightAnchor.constraint(equalToConstant: 4)
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
        audioButton.addTarget(self, action: #selector(showAudioMenu), for: .touchUpInside)
        buttonsStackView.addArrangedSubview(audioButton)
        
        // Subtitle button
        let subtitleButton = UIButton(type: .system)
        subtitleButton.setImage(UIImage(systemName: "captions.bubble"), for: .normal)
        subtitleButton.tintColor = .white
        subtitleButton.addTarget(self, action: #selector(showSubtitleMenu), for: .touchUpInside)
        buttonsStackView.addArrangedSubview(subtitleButton)
        
        // Speed button
        let speedButton = UIButton(type: .system)
        speedButton.setTitle("1.0x", for: .normal)
        speedButton.tintColor = .white
        speedButton.addTarget(self, action: #selector(showSpeedMenu), for: .touchUpInside)
        buttonsStackView.addArrangedSubview(speedButton)
        
        // Settings button
        let settingsButton = UIButton(type: .system)
        settingsButton.setImage(UIImage(systemName: "gear"), for: .normal)
        settingsButton.tintColor = .white
        buttonsStackView.addArrangedSubview(settingsButton)
    }
    
    private func setupGestureRecognizers() {
        // Single tap to toggle controls
        let tapGesture = UITapGestureRecognizer(target: self, action: #selector(handleTap))
        view.addGestureRecognizer(tapGesture)
        
        // Double tap to toggle play/pause
        let doubleTapGesture = UITapGestureRecognizer(target: self, action: #selector(togglePlayPause))
        doubleTapGesture.numberOfTapsRequired = 2
        view.addGestureRecognizer(doubleTapGesture)
        
        // Long press for 2x speed
        let longPressGesture = UILongPressGestureRecognizer(target: self, action: #selector(handleLongPress(_:)))
        longPressGesture.minimumPressDuration = 0.5
        view.addGestureRecognizer(longPressGesture)
        
        // Swipe gestures for seek
        let leftSwipe = UISwipeGestureRecognizer(target: self, action: #selector(handleLeftSwipe))
        leftSwipe.direction = .left
        view.addGestureRecognizer(leftSwipe)
        
        let rightSwipe = UISwipeGestureRecognizer(target: self, action: #selector(handleRightSwipe))
        rightSwipe.direction = .right
        view.addGestureRecognizer(rightSwipe)
    }
    
    @objc private func handleTap() {
        playerState?.scheduleHideControls()
    }
    
    @objc private func handleLongPress(_ gesture: UILongPressGestureRecognizer) {
        if gesture.state == .began {
            vlcRenderer.setPlaybackSpeed(2.0)
            playerState?.currentPlaybackSpeed = 2.0
            Logger.shared.log("[VLCPlayer] Long press: 2x speed", type: "Stream")
        } else if gesture.state == .ended {
            vlcRenderer.setPlaybackSpeed(1.0)
            playerState?.currentPlaybackSpeed = 1.0
            Logger.shared.log("[VLCPlayer] Long press released: 1x speed", type: "Stream")
        }
    }
    
    @objc private func togglePlayPause() {
        vlcRenderer.togglePlayPause()
    }
    
    @objc private func handleLeftSwipe() {
        let currentPosition = vlcRenderer.position
        vlcRenderer.seek(to: currentPosition - 10)
    }
    
    @objc private func handleRightSwipe() {
        let currentPosition = vlcRenderer.position
        vlcRenderer.seek(to: currentPosition + 10)
    }
    
    @objc private func showAudioMenu() {
        let audioTracks = vlcRenderer.getAudioTracksDetailed()
        let alert = UIAlertController(title: "Select Audio Track", message: nil, preferredStyle: .actionSheet)
        
        for track in audioTracks {
            let title = "\(track.name) \(track.isDefault ? "✓" : "")"
            alert.addAction(UIAlertAction(title: title, style: .default) { [weak self] _ in
                self?.vlcRenderer.setAudioTrack(track.id)
            })
        }
        
        alert.addAction(UIAlertAction(title: "Cancel", style: .cancel))
        present(alert, animated: true)
    }
    
    @objc private func showSubtitleMenu() {
        let subtitleTracks = vlcRenderer.getSubtitleTracksDetailed()
        let alert = UIAlertController(title: "Select Subtitles", message: nil, preferredStyle: .actionSheet)
        
        alert.addAction(UIAlertAction(title: "None", style: .default) { [weak self] _ in
            self?.vlcRenderer.disableSubtitles()
        })
        
        for track in subtitleTracks {
            let title = "\(track.name) \(track.isDefault ? "✓" : "")"
            alert.addAction(UIAlertAction(title: title, style: .default) { [weak self] _ in
                self?.vlcRenderer.setSubtitleTrack(track.id)
            })
        }
        
        alert.addAction(UIAlertAction(title: "Cancel", style: .cancel))
        present(alert, animated: true)
    }
    
    @objc private func showSpeedMenu() {
        let alert = UIAlertController(title: "Playback Speed", message: nil, preferredStyle: .actionSheet)
        let speeds = [0.5, 0.75, 1.0, 1.25, 1.5, 2.0]
        
        for speed in speeds {
            let isSelected = playerState?.currentPlaybackSpeed == speed
            let title = "\(speed)x \(isSelected ? "✓" : "")"
            alert.addAction(UIAlertAction(title: title, style: .default) { [weak self] _ in
                self?.vlcRenderer.setPlaybackSpeed(speed)
                self?.playerState?.currentPlaybackSpeed = speed
            })
        }
        
        alert.addAction(UIAlertAction(title: "Cancel", style: .cancel))
        present(alert, animated: true)
    }
    
    func load(url: URL, headers: [String: String]?, preset: PlayerPreset?) {
        do {
            try vlcRenderer.loadMedia(url: url, headers: headers, preset: preset)
        } catch {
            Logger.shared.log("Failed to load VLC media: \(error)", type: "Error")
        }
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
            
            if duration > 0 {
                self.progressBar.progress = Float(position / duration)
            }
            
            self.timeLabel.text = self.formatTime(position)
            self.durationLabel.text = self.formatTime(duration)
        }
    }
    
    func renderer(_ renderer: VLCRenderer, didChangePause isPaused: Bool) {
        DispatchQueue.main.async {
            self.playerState?.isPlaying = !isPaused
            let imageName = isPaused ? "play.fill" : "pause.fill"
            self.centerPlayButton.setImage(UIImage(systemName: imageName), for: .normal)
        }
    }
    
    func renderer(_ renderer: VLCRenderer, didChangeLoading isLoading: Bool) {
        DispatchQueue.main.async {
            self.playerState?.isLoading = isLoading
        }
    }
    
    func renderer(_ renderer: VLCRenderer, didBecomeReadyToSeek: Bool) {}
    
    func renderer(_ renderer: VLCRenderer, getSubtitleForTime time: Double) -> NSAttributedString? {
        return nil
    }
    
    func renderer(_ renderer: VLCRenderer, getSubtitleStyle: Void) -> SubtitleStyle {
        return SubtitleStyle(fontSize: 16, color: .white, strokeColor: .black, strokeWidth: 1.5)
    }
    
    func renderer(_ renderer: VLCRenderer, subtitleTrackDidChange trackId: Int) {}
    
    func rendererDidChangeTracks(_ renderer: VLCRenderer) {
        playerState?.audioTracks = renderer.getAudioTracksDetailed()
        playerState?.subtitleTracks = renderer.getSubtitleTracksDetailed()
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
                            renderer.setSubtitleTrack(index)
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
#else

// tvOS/macOS: Stub implementations
class VLCPlayerState: NSObject, ObservableObject {
    @Published var isPlaying = false
    @Published var position: Double = 0
    @Published var duration: Double = 0
    @Published var isLoading = false
    @Published var showControls = true
    @Published var currentPlaybackSpeed: Double = 1.0
    @Published var audioTracks: [VLCRenderer.AudioTrack] = []
    @Published var subtitleTracks: [VLCRenderer.SubtitleTrack] = []
    @Published var selectedAudioLanguage = "en"
    @Published var enableAutoSubtitles = true
    
    func scheduleHideControls() {}
}
struct VLCPlayer: UIViewControllerRepresentable {
    let url: URL
    var headers: [String: String]? = nil
    var preset: PlayerPreset? = nil
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
