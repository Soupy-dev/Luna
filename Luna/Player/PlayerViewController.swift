//
//  PlayerViewController.swift
//  test
//
//  Created by Francesco on 28/09/25.
//

import UIKit
import SwiftUI
import AVFoundation

final class PlayerViewController: UIViewController, UIGestureRecognizerDelegate {
    private let playerLogId = UUID().uuidString.prefix(8)
    private let trackerManager = TrackerManager.shared

    private let videoContainer: UIView = {
        let v = UIView()
        v.translatesAutoresizingMaskIntoConstraints = false
        v.backgroundColor = .black
        v.clipsToBounds = true
        return v
    }()
    
    private let tapOverlayView: UIView = {
        let v = UIView()
        v.translatesAutoresizingMaskIntoConstraints = false
        v.backgroundColor = .clear
        v.isUserInteractionEnabled = true
        return v
    }()
    
    private let displayLayer = AVSampleBufferDisplayLayer()
    
    private func createSymbolButton(symbolName: String, pointSize: CGFloat = 18, weight: UIImage.SymbolWeight = .semibold, backgroundColor: UIColor? = nil) -> UIButton {
        let b = UIButton(type: .system)
        b.translatesAutoresizingMaskIntoConstraints = false
        let cfg = UIImage.SymbolConfiguration(pointSize: pointSize, weight: weight)
        let img = UIImage(systemName: symbolName, withConfiguration: cfg)
        b.setImage(img, for: .normal)
        b.tintColor = .white
        if let bg = backgroundColor {
            b.backgroundColor = bg
            b.layer.cornerRadius = pointSize + 10
            b.clipsToBounds = true
        } else {
            b.alpha = 0.0
        }
        return b
    }
    
    private let centerPlayPauseButton: UIButton = {
        let b = UIButton(type: .system)
        b.translatesAutoresizingMaskIntoConstraints = false
        let configuration = UIImage.SymbolConfiguration(pointSize: 32, weight: .semibold)
        let image = UIImage(systemName: "play.fill", withConfiguration: configuration)
        b.setImage(image, for: .normal)
        b.tintColor = .white
        b.backgroundColor = UIColor(white: 0.2, alpha: 0.5)
        b.layer.cornerRadius = 35
        b.clipsToBounds = true
        return b
    }()
    
    private let loadingIndicator: UIActivityIndicatorView = {
        let v: UIActivityIndicatorView
        v = UIActivityIndicatorView(style: .large)
        v.translatesAutoresizingMaskIntoConstraints = false
        v.hidesWhenStopped = true
        v.color = .white
        v.alpha = 0.0
        return v
    }()
    
    private let controlsOverlayView: UIView = {
        let v = UIView()
        v.translatesAutoresizingMaskIntoConstraints = false
        v.backgroundColor = UIColor(white: 0.0, alpha: 0.4)
        v.alpha = 0.0
        v.isUserInteractionEnabled = false
        v.isHidden = true
        return v
    }()
    
    private lazy var errorBanner: UIView = {
        let container = UIView()
        container.translatesAutoresizingMaskIntoConstraints = false
        container.backgroundColor = UIColor { trait -> UIColor in
            return trait.userInterfaceStyle == .dark ? UIColor(red: 0.85, green: 0.15, blue: 0.15, alpha: 0.95) : UIColor(red: 0.9, green: 0.17, blue: 0.17, alpha: 0.98)
        }
        container.layer.cornerRadius = 10
        container.clipsToBounds = true
        container.alpha = 0.0
        
        let icon = UIImageView(image: UIImage(systemName: "exclamationmark.triangle.fill"))
        icon.tintColor = .white
        icon.translatesAutoresizingMaskIntoConstraints = false
        
        let label = UILabel()
        label.translatesAutoresizingMaskIntoConstraints = false
        label.textColor = .white
        label.font = .systemFont(ofSize: 13, weight: .semibold)
        label.numberOfLines = 2
        label.tag = 101
        
        let btn = UIButton(type: .system)
        btn.translatesAutoresizingMaskIntoConstraints = false
        btn.setTitle("View Logs", for: .normal)
        btn.setTitleColor(.white, for: .normal)
        btn.titleLabel?.font = .systemFont(ofSize: 13, weight: .semibold)
        btn.backgroundColor = UIColor(white: 1.0, alpha: 0.12)
        btn.layer.cornerRadius = 6
        
        if #unavailable(tvOS 15) {
            btn.contentEdgeInsets = UIEdgeInsets(top: 6, left: 10, bottom: 6, right: 10)
        }
        btn.addTarget(self, action: #selector(viewLogsTapped), for: .touchUpInside)
        
        container.addSubview(icon)
        container.addSubview(label)
        container.addSubview(btn)
        
        NSLayoutConstraint.activate([
            icon.leadingAnchor.constraint(equalTo: container.leadingAnchor, constant: 10),
            icon.centerYAnchor.constraint(equalTo: container.centerYAnchor),
            icon.widthAnchor.constraint(equalToConstant: 20),
            icon.heightAnchor.constraint(equalToConstant: 20),
            
            label.leadingAnchor.constraint(equalTo: icon.trailingAnchor, constant: 8),
            label.centerYAnchor.constraint(equalTo: icon.centerYAnchor),
            
            btn.leadingAnchor.constraint(equalTo: label.trailingAnchor, constant: 12),
            btn.trailingAnchor.constraint(equalTo: container.trailingAnchor, constant: -10),
            btn.centerYAnchor.constraint(equalTo: container.centerYAnchor)
        ])
        
        return container
    }()
    
    private let closeButton: UIButton = {
        let b = UIButton(type: .system)
        b.translatesAutoresizingMaskIntoConstraints = false
        let cfg = UIImage.SymbolConfiguration(pointSize: 18, weight: .semibold)
        let img = UIImage(systemName: "xmark", withConfiguration: cfg)
        b.setImage(img, for: .normal)
        b.tintColor = .white
        b.alpha = 0.0
        return b
    }()
    
    private let pipButton: UIButton = {
        let b = UIButton(type: .system)
        b.translatesAutoresizingMaskIntoConstraints = false
        let cfg = UIImage.SymbolConfiguration(pointSize: 18, weight: .semibold)
        let img = UIImage(systemName: "pip.enter", withConfiguration: cfg)
        b.setImage(img, for: .normal)
        b.tintColor = .white
        b.alpha = 0.0
        return b
    }()
    
    private let skipBackwardButton: UIButton = {
        let b = UIButton(type: .system)
        b.translatesAutoresizingMaskIntoConstraints = false
        let cfg = UIImage.SymbolConfiguration(pointSize: 28, weight: .semibold)
        let img = UIImage(systemName: "gobackward.10", withConfiguration: cfg)
        b.setImage(img, for: .normal)
        b.tintColor = .white
        b.alpha = 0.0
        return b
    }()
    
    private let skipForwardButton: UIButton = {
        let b = UIButton(type: .system)
        b.translatesAutoresizingMaskIntoConstraints = false
        let cfg = UIImage.SymbolConfiguration(pointSize: 28, weight: .semibold)
        let img = UIImage(systemName: "goforward.10", withConfiguration: cfg)
        b.setImage(img, for: .normal)
        b.tintColor = .white
        b.alpha = 0.0
        return b
    }()
    
    private let speedIndicatorLabel: UILabel = {
        let label = UILabel()
        label.translatesAutoresizingMaskIntoConstraints = false
        label.textColor = .white
        label.font = .systemFont(ofSize: 16, weight: .bold)
        label.textAlignment = .center
        label.backgroundColor = UIColor(white: 0.2, alpha: 0.8)
        label.layer.cornerRadius = 20
        label.clipsToBounds = true
        label.alpha = 0.0
        return label
    }()
    
    private let subtitleButton: UIButton = {
        let b = UIButton(type: .system)
        b.translatesAutoresizingMaskIntoConstraints = false
        let cfg = UIImage.SymbolConfiguration(pointSize: 16, weight: .semibold)
        let img = UIImage(systemName: "captions.bubble", withConfiguration: cfg)
        b.setImage(img, for: .normal)
        b.tintColor = .white
        b.alpha = 0.0
        b.isHidden = true
        // Will be set dynamically based on renderer type
        b.showsMenuAsPrimaryAction = false
        return b
    }()
    
    private let speedButton: UIButton = {
        let b = UIButton(type: .system)
        b.translatesAutoresizingMaskIntoConstraints = false
        let cfg = UIImage.SymbolConfiguration(pointSize: 16, weight: .semibold)
        let img = UIImage(systemName: "hare.fill", withConfiguration: cfg)
        b.setImage(img, for: .normal)
        b.tintColor = .white
        b.alpha = 0.0
        b.showsMenuAsPrimaryAction = true
        return b
    }()
    
    private let audioButton: UIButton = {
        let b = UIButton(type: .system)
        b.translatesAutoresizingMaskIntoConstraints = false
        let cfg = UIImage.SymbolConfiguration(pointSize: 16, weight: .semibold)
        let img = UIImage(systemName: "speaker.wave.2", withConfiguration: cfg)
        b.setImage(img, for: .normal)
        b.tintColor = .white
        b.alpha = 0.0
        b.showsMenuAsPrimaryAction = true
        return b
    }()

    private let dimmingView: UIView = {
        let v = UIView()
        v.translatesAutoresizingMaskIntoConstraints = false
        v.backgroundColor = .black
        v.alpha = 0.0
        v.isUserInteractionEnabled = false
        return v
    }()

#if !os(tvOS)
    private let brightnessContainer: UIVisualEffectView = {
        let effect: UIBlurEffect
        if #available(iOS 15.0, *) {
            effect = UIBlurEffect(style: .systemThinMaterialDark)
        } else {
            effect = UIBlurEffect(style: .dark)
        }
        let v = UIVisualEffectView(effect: effect)
        v.translatesAutoresizingMaskIntoConstraints = false
        v.layer.cornerRadius = 12
        v.clipsToBounds = true
        v.alpha = 0.0
        v.isHidden = true
        return v
    }()

    private let brightnessSlider: UISlider = {
        let slider = UISlider()
        slider.translatesAutoresizingMaskIntoConstraints = false
        slider.minimumValue = 0.0
        slider.maximumValue = 1.0
        slider.value = 1.0
        slider.minimumTrackTintColor = .white
        slider.maximumTrackTintColor = UIColor.white.withAlphaComponent(0.3)
        slider.thumbTintColor = .white
        slider.transform = CGAffineTransform(rotationAngle: -.pi / 2)
        return slider
    }()

    private let brightnessIcon: UIImageView = {
        let icon = UIImageView(image: UIImage(systemName: "sun.max.fill"))
        icon.translatesAutoresizingMaskIntoConstraints = false
        icon.tintColor = .white
        icon.alpha = 0.8
        return icon
    }()
#endif
    
    private let progressContainer: UIView = {
        let v = UIView()
        v.translatesAutoresizingMaskIntoConstraints = false
        v.backgroundColor = .clear
        return v
    }()
    private var progressHostingController: UIHostingController<AnyView>?
    private var lastHostedDuration: Double = 0
    
    class ProgressModel: ObservableObject {
        @Published var position: Double = 0
        @Published var duration: Double = 1
    }
    private var progressModel = ProgressModel()

    private var containerTapGesture: UITapGestureRecognizer?
    private var leftDoubleTapGesture: UITapGestureRecognizer?
    private var rightDoubleTapGesture: UITapGestureRecognizer?

    private var brightnessLevel: Float = 1.0
    private let twoFingerSettingKey = "mpvTwoFingerTapEnabled"
    private let brightnessLevelKey = "mpvBrightnessLevel"
    
    private lazy var renderer: Any = {
        // Select renderer based on Settings
        let playerChoice = Settings.shared.playerChoice
        
        if playerChoice == .vlc {
            let r = VLCRenderer(displayLayer: displayLayer)
            r.delegate = self
            return r
        } else {
            let r = MPVSoftwareRenderer(displayLayer: displayLayer)
            r.delegate = self
            return r
        }
    }()
    
    // Helper properties to access renderer methods regardless of type
    private var mpvRenderer: MPVSoftwareRenderer? {
        return renderer as? MPVSoftwareRenderer
    }
    
    private var vlcRenderer: VLCRenderer? {
        return renderer as? VLCRenderer
    }

    private var isVLCPlayer: Bool {
        return vlcRenderer != nil
    }
    
    var mediaInfo: MediaInfo?
    // Optional override: when true, treat content as anime regardless of tracker mapping
    var isAnimeHint: Bool?
    private var isSeeking = false
    private var cachedDuration: Double = 0
    private var cachedPosition: Double = 0
    private var isClosing = false
    private var isRunning = false  // Track if renderer has been started
    private var pipController: PiPController?
    private var initialURL: URL?
    private var initialPreset: PlayerPreset?
    private var initialHeaders: [String: String]?
    private var initialSubtitles: [String]?
    private var userSelectedAudioTrack = false
    private var userSelectedSubtitleTrack = false
    private var vlcProxyFallbackTried = false
    
    // Debounce timers for menu updates to avoid excessive rebuilds
    private var audioMenuDebounceTimer: Timer?
    private var subtitleMenuDebounceTimer: Timer?
    
    // MARK: - Renderer Wrapper Methods
    // These methods abstract away differences between MPVSoftwareRenderer and VLCRenderer
    
    private func rendererLoad(url: URL, preset: PlayerPreset, headers: [String: String]?) {
        if let vlc = vlcRenderer {
            vlc.load(url: url, with: preset, headers: headers)
        } else if let mpv = mpvRenderer {
            mpv.load(url: url, with: preset, headers: headers)
        }
    }
    
    private func rendererReloadCurrentItem() {
        if let vlc = vlcRenderer {
            vlc.reloadCurrentItem()
        } else if let mpv = mpvRenderer {
            mpv.reloadCurrentItem()
        }
    }
    
    private func rendererApplyPreset(_ preset: PlayerPreset) {
        if let vlc = vlcRenderer {
            vlc.applyPreset(preset)
        } else if let mpv = mpvRenderer {
            mpv.applyPreset(preset)
        }
    }
    
    private func rendererStart() throws {
        if let vlc = vlcRenderer {
            try vlc.start()
        } else if let mpv = mpvRenderer {
            try mpv.start()
        }
        isRunning = true
    }
    
    private func rendererStop() {
        if let vlc = vlcRenderer {
            vlc.stop()
        } else if let mpv = mpvRenderer {
            mpv.stop()
        }
        isRunning = false
    }
    
    private func rendererPlay() {
        Logger.shared.log("[PlayerViewController.rendererPlay] Play", type: "Stream")
        if let vlc = vlcRenderer {
            Logger.shared.log("[PlayerViewController.rendererPlay] Using VLC renderer", type: "Stream")
            vlc.play()
        } else if let mpv = mpvRenderer {
            Logger.shared.log("[PlayerViewController.rendererPlay] Using MPV renderer", type: "Stream")
            mpv.play()
        }
    }
    
    private func rendererPausePlayback() {
        Logger.shared.log("[PlayerViewController.rendererPausePlayback] Pause", type: "Stream")
        if let vlc = vlcRenderer {
            Logger.shared.log("[PlayerViewController.rendererPausePlayback] Using VLC renderer", type: "Stream")
            vlc.pausePlayback()
        } else if let mpv = mpvRenderer {
            Logger.shared.log("[PlayerViewController.rendererPausePlayback] Using MPV renderer", type: "Stream")
            mpv.pausePlayback()
        }
    }
    
    private func rendererTogglePause() {
        Logger.shared.log("[PlayerViewController.rendererTogglePause] Toggle pause", type: "Stream")
        if let vlc = vlcRenderer {
            Logger.shared.log("[PlayerViewController.rendererTogglePause] Using VLC renderer", type: "Stream")
            vlc.togglePause()
        } else if let mpv = mpvRenderer {
            Logger.shared.log("[PlayerViewController.rendererTogglePause] Using MPV renderer", type: "Stream")
            mpv.togglePause()
        }
    }

    private func rendererSeek(to seconds: Double) {
        Logger.shared.log("[PlayerViewController.rendererSeek] Seek to \(seconds)s", type: "Stream")
        if let vlc = vlcRenderer {
            vlc.seek(to: seconds)
        } else if let mpv = mpvRenderer {
            mpv.seek(to: seconds)
        }
    }
    
    private func rendererSeek(by seconds: Double) {
        Logger.shared.log("[PlayerViewController.rendererSeek] Seek by \(seconds)s", type: "Stream")
        if let vlc = vlcRenderer {
            vlc.seek(by: seconds)
        } else if let mpv = mpvRenderer {
            mpv.seek(by: seconds)
        }
    }
    
    private func rendererSetSpeed(_ speed: Double) {
        Logger.shared.log("[PlayerViewController.rendererSetSpeed] Speed=\(speed)", type: "Stream")
        if let vlc = vlcRenderer {
            vlc.setSpeed(speed)
        } else if let mpv = mpvRenderer {
            mpv.setSpeed(speed)
        }
    }
    
    private func rendererGetSpeed() -> Double {
        if let vlc = vlcRenderer {
            return vlc.getSpeed()
        } else if let mpv = mpvRenderer {
            return mpv.getSpeed()
        }
        return 1.0
    }
    
    private func rendererGetAudioTracksDetailed() -> [(Int, String, String)] {
        if let vlc = vlcRenderer {
            return vlc.getAudioTracksDetailed()
        } else if let mpv = mpvRenderer {
            return mpv.getAudioTracksDetailed()
        }
        return []
    }
    
    private func rendererGetAudioTracks() -> [(Int, String)] {
        if let vlc = vlcRenderer {
            return vlc.getAudioTracks()
        } else if let mpv = mpvRenderer {
            return mpv.getAudioTracks()
        }
        return []
    }
    
    private func rendererSetAudioTrack(id: Int) {
        if let vlc = vlcRenderer {
            vlc.setAudioTrack(id: id)
        } else if let mpv = mpvRenderer {
            mpv.setAudioTrack(id: id)
        }
    }
    
    private func rendererGetCurrentAudioTrackId() -> Int {
        if let vlc = vlcRenderer {
            return vlc.getCurrentAudioTrackId()
        } else if let mpv = mpvRenderer {
            return mpv.getCurrentAudioTrackId()
        }
        return -1
    }
    
    private func rendererGetSubtitleTracks() -> [(Int, String)] {
        if let vlc = vlcRenderer {
            return vlc.getSubtitleTracks()
        } else if let mpv = mpvRenderer {
            return mpv.getSubtitleTracks()
        }
        return []
    }
    
    private func rendererSetSubtitleTrack(id: Int) {
        if let vlc = vlcRenderer {
            vlc.setSubtitleTrack(id: id)
        } else if let mpv = mpvRenderer {
            mpv.setSubtitleTrack(id: id)
        }
    }
    
    private func rendererGetCurrentSubtitleTrackId() -> Int {
        if let vlc = vlcRenderer {
            return vlc.getCurrentSubtitleTrackId()
        } else if let mpv = mpvRenderer {
            return mpv.getCurrentSubtitleTrackId()
        }
        return -1
    }
    
    private func rendererDisableSubtitles() {
        if let vlc = vlcRenderer {
            vlc.disableSubtitles()
        } else if let mpv = mpvRenderer {
            mpv.disableSubtitles()
        }
    }
    
    private func rendererRefreshSubtitleOverlay() {
        if let vlc = vlcRenderer {
            vlc.refreshSubtitleOverlay()
        }
    }
    
    private func rendererLoadExternalSubtitles(urls: [String]) {
        if let vlc = vlcRenderer {
            vlc.loadExternalSubtitles(urls: urls)
        }
    }
    
    private func rendererClearSubtitleCache() {
        if let vlc = vlcRenderer {
            vlc.clearSubtitleCache()
        }
    }
    
    private func rendererIsPausedState() -> Bool {
        if let vlc = vlcRenderer {
            return vlc.isPausedState
        } else if let mpv = mpvRenderer {
            return mpv.isPausedState
        }
        return true
    }
    
    private var subtitleURLs: [String] = []
    private var currentSubtitleIndex: Int = 0
    private var subtitleEntries: [SubtitleEntry] = []

    private func logMPV(_ message: String) {
        Logger.shared.log("[MPV \(playerLogId)] " + message, type: "MPV")
    }
    
    class SubtitleModel: ObservableObject {
        @Published var currentAttributedText: NSAttributedString = NSAttributedString()
        
        private var isLoading: Bool = true
        
        @Published var isVisible: Bool = false {
            didSet {
                if !isLoading { saveSubtitleSettings() }
            }
        }
        @Published var foregroundColor: UIColor = .white {
            didSet {
                if !isLoading { saveSubtitleSettings() }
            }
        }
        @Published var strokeColor: UIColor = .black {
            didSet {
                if !isLoading { saveSubtitleSettings() }
            }
        }
        @Published var strokeWidth: CGFloat = 1.0 {
            didSet {
                if !isLoading { saveSubtitleSettings() }
            }
        }
        @Published var fontSize: CGFloat = 38.0 {
            didSet {
                if !isLoading { saveSubtitleSettings() }
            }
        }
        
        init() {
            loadSubtitleSettings()
            isLoading = false
        }
        
        private func saveSubtitleSettings() {
            let defaults = UserDefaults.standard
            defaults.set(isVisible, forKey: "subtitles_isVisible")
            defaults.set(strokeWidth, forKey: "subtitles_strokeWidth")
            defaults.set(fontSize, forKey: "subtitles_fontSize")
            
            if let foregroundData = try? NSKeyedArchiver.archivedData(withRootObject: foregroundColor, requiringSecureCoding: false) {
                defaults.set(foregroundData, forKey: "subtitles_foregroundColor")
            }
            if let strokeData = try? NSKeyedArchiver.archivedData(withRootObject: strokeColor, requiringSecureCoding: false) {
                defaults.set(strokeData, forKey: "subtitles_strokeColor")
            }
        }
        
        private func loadSubtitleSettings() {
            let defaults = UserDefaults.standard
            
            if defaults.object(forKey: "subtitles_isVisible") != nil {
                isVisible = defaults.bool(forKey: "subtitles_isVisible")
            }
            
            if defaults.object(forKey: "subtitles_strokeWidth") != nil {
                let width = CGFloat(defaults.double(forKey: "subtitles_strokeWidth"))
                strokeWidth = width > 0 ? width : 1.0
            }
            
            if defaults.object(forKey: "subtitles_fontSize") != nil {
                let size = CGFloat(defaults.double(forKey: "subtitles_fontSize"))
                fontSize = size > 0 ? size : 38.0
            }
            
            if let foregroundData = defaults.data(forKey: "subtitles_foregroundColor"),
               let color = try? NSKeyedUnarchiver.unarchivedObject(ofClass: UIColor.self, from: foregroundData) {
                foregroundColor = color
            }
            if let strokeData = defaults.data(forKey: "subtitles_strokeColor"),
               let color = try? NSKeyedUnarchiver.unarchivedObject(ofClass: UIColor.self, from: strokeData) {
                strokeColor = color
            }
        }
    }
    private var subtitleModel = SubtitleModel()

    private var isTwoFingerTapEnabled: Bool {
        if UserDefaults.standard.object(forKey: twoFingerSettingKey) == nil {
            return true
        }
        return UserDefaults.standard.bool(forKey: twoFingerSettingKey)
    }
    private var isBrightnessControlEnabled: Bool {
        return false
    }
    
    private var originalSpeed: Double = 1.0
    private var holdGesture: UILongPressGestureRecognizer?
    
    private var controlsHideWorkItem: DispatchWorkItem?
    private var controlsVisible: Bool = true
    private var pendingSeekTime: Double?
    
    override func viewDidLoad() {
        super.viewDidLoad()
        view.backgroundColor = .black
        logMPV("viewDidLoad, initialURL=")
        
#if !os(tvOS)
        modalPresentationCapturesStatusBarAppearance = true
#endif
        setupLayout()
        
        setupActions()
        setupHoldGesture()
        if isVLCPlayer {
            setupDoubleTapSkipGestures()
        }
    #if !os(tvOS)
        if isVLCPlayer {
            setupBrightnessControls()
        }
    #endif

        if !isVLCPlayer {
            let cfg = UIImage.SymbolConfiguration(pointSize: 28, weight: .semibold)
            skipBackwardButton.setImage(UIImage(systemName: "gobackward.15", withConfiguration: cfg), for: .normal)
            skipForwardButton.setImage(UIImage(systemName: "goforward.15", withConfiguration: cfg), for: .normal)
            subtitleButton.showsMenuAsPrimaryAction = true
        }

        NotificationCenter.default.addObserver(self, selector: #selector(handleLoggerNotification(_:)), name: NSNotification.Name("LoggerNotification"), object: nil)
        
        do {
            try rendererStart()
            logMPV("renderer.start succeeded")
        } catch {
            let rendererName = vlcRenderer != nil ? "VLC" : "MPV"
            Logger.shared.log("Failed to start \(rendererName) renderer: \(error)", type: "Error")
        }
        
        // PiP is only supported with MPV renderer
        if vlcRenderer == nil {
            pipController = PiPController(sampleBufferDisplayLayer: displayLayer)
            pipController?.delegate = self
        }
        
        showControlsTemporarily()
        
        if let url = initialURL, let preset = initialPreset {
            logMPV("loading initial url=\(url.absoluteString) preset=\(preset.id.rawValue)")
            load(url: url, preset: preset, headers: initialHeaders)
        }
        
        updateProgressHostingController()
        if isVLCPlayer {
            updateSpeedMenu()
        }
        
        NotificationCenter.default.addObserver(self, selector: #selector(appDidEnterBackground), name: UIApplication.didEnterBackgroundNotification, object: nil)
        NotificationCenter.default.addObserver(self, selector: #selector(appWillEnterForeground), name: UIApplication.willEnterForegroundNotification, object: nil)
    }
    
    override func viewDidAppear(_ animated: Bool) {
        super.viewDidAppear(animated)
        view.bringSubviewToFront(errorBanner)
    }
    
#if !os(tvOS)
    override var prefersStatusBarHidden: Bool { true }
    override var preferredStatusBarUpdateAnimation: UIStatusBarAnimation { .fade }
    
    override var supportedInterfaceOrientations: UIInterfaceOrientationMask {
        if UserDefaults.standard.bool(forKey: "alwaysLandscape") {
            return .landscape
        } else {
            return .all
        }
    }
    
    override func viewWillAppear(_ animated: Bool) {
        super.viewWillAppear(animated)
        setNeedsStatusBarAppearanceUpdate()
    }
    
    override func viewWillDisappear(_ animated: Bool) {
        super.viewWillDisappear(animated)
        setNeedsStatusBarAppearanceUpdate()
    }
#endif
    
    override func viewDidLayoutSubviews() {
        super.viewDidLayoutSubviews()
        
        CATransaction.begin()
        CATransaction.setDisableActions(true)
        
        // Only update displayLayer frame when using MPV
        if vlcRenderer == nil {
            displayLayer.frame = videoContainer.bounds
        }
        
        if let gradientLayer = controlsOverlayView.layer.sublayers?.first(where: { $0.name == "gradientLayer" }) {
            gradientLayer.frame = controlsOverlayView.bounds
        }
        
        CATransaction.commit()
    }
    
    deinit {
        isClosing = true
        audioMenuDebounceTimer?.invalidate()
        subtitleMenuDebounceTimer?.invalidate()
        if let mpv = mpvRenderer {
            mpv.delegate = nil
        } else if let vlc = vlcRenderer {
            vlc.delegate = nil
        }
        logMPV("deinit; stopping renderer and restoring state")
        pipController?.delegate = nil
        if pipController?.isPictureInPictureActive == true {
            pipController?.stopPictureInPicture()
        }
        pipController?.invalidate()
        rendererStop()
        
        // Only remove displayLayer if it was added (MPV only)
        if vlcRenderer == nil {
            displayLayer.removeFromSuperlayer()
        }
        
        NotificationCenter.default.removeObserver(self)
    }
    
    convenience init(url: URL, preset: PlayerPreset, headers: [String: String]? = nil, subtitles: [String]? = nil, mediaInfo: MediaInfo? = nil) {
        self.init(nibName: nil, bundle: nil)
        self.initialURL = url
        self.initialPreset = preset
        self.initialHeaders = headers
        self.initialSubtitles = subtitles
        self.mediaInfo = mediaInfo
        Logger.shared.log("[PlayerViewController.init] URL=\(url.absoluteString) preset=\(preset.id.rawValue) headers=\(headers?.count ?? 0) subtitles=\(subtitles?.count ?? 0) mediaInfo=\(mediaInfo != nil)", type: "Stream")
    }
    
    func load(url: URL, preset: PlayerPreset, headers: [String: String]? = nil) {
        logMPV("load url=\(url.absoluteString) preset=\(preset.id.rawValue) headers=\(headers?.count ?? 0)")
        let mediaInfoLabel: String = {
            guard let info = mediaInfo else { return "nil" }
            switch info {
            case .movie(let id, let title, _, let isAnime):
                return "movie id=\(id) title=\(title) isAnime=\(isAnime)"
            case .episode(let showId, let seasonNumber, let episodeNumber, let showTitle, _, let isAnime):
                return "episode showId=\(showId) s=\(seasonNumber) e=\(episodeNumber) title=\(showTitle) isAnime=\(isAnime)"
            }
        }()
        Logger.shared.log("PlayerViewController.load: isAnimeHint=\(isAnimeHint ?? false) mediaInfo=\(mediaInfoLabel)", type: "Stream")
        
        // Ensure renderer is started before loading media
        if !isRunning {
            do {
                try rendererStart()
            } catch {
                return
            }
        }
        
        userSelectedAudioTrack = false
        userSelectedSubtitleTrack = false
        rendererLoad(url: url, preset: preset, headers: headers)
        if let info = mediaInfo {
            prepareSeekToLastPosition(for: info)
        }
        
        if let subs = initialSubtitles, !subs.isEmpty {
            loadSubtitles(subs)
        }
    }
    
    // Convenience wrapper for SwiftUI
    func loadMedia(url: URL, preset: PlayerPreset, headers: [String: String]? = nil) {
        load(url: url, preset: preset, headers: headers)
    }
    
    private func prepareSeekToLastPosition(for mediaInfo: MediaInfo) {
        let lastPlayedTime: Double
        
        switch mediaInfo {
        case .movie(let id, let title, _, _):
            lastPlayedTime = ProgressManager.shared.getMovieCurrentTime(movieId: id, title: title)
            
        case .episode(let showId, let seasonNumber, let episodeNumber, _, _, _):
            lastPlayedTime = ProgressManager.shared.getEpisodeCurrentTime(showId: showId, seasonNumber: seasonNumber, episodeNumber: episodeNumber)
        }
        
        if lastPlayedTime != 0 {
            let progress: Double
            switch mediaInfo {
            case .movie(let id, let title, _, _):
                progress = ProgressManager.shared.getMovieProgress(movieId: id, title: title)
            case .episode(let showId, let seasonNumber, let episodeNumber, _, _, _):
                progress = ProgressManager.shared.getEpisodeProgress(showId: showId, seasonNumber: seasonNumber, episodeNumber: episodeNumber)
            }
            
            if progress < 0.95 {
                pendingSeekTime = lastPlayedTime
            }
        }
    }
    
    private func setupLayout() {
        view.addSubview(videoContainer)
        
        // Only add displayLayer for MPV; VLC uses its own UIView rendering
        if vlcRenderer == nil {
            displayLayer.frame = videoContainer.bounds
            // Keep full video visible; avoid cropping for downloaded media
            displayLayer.videoGravity = .resizeAspect
            displayLayer.isOpaque = true
#if compiler(>=6.0)
            if #available(iOS 26.0, tvOS 26.0, *) {
                displayLayer.preferredDynamicRange = .automatic
            } else {
#if !os(tvOS)
                if #available(iOS 17.0, *) {
                    displayLayer.wantsExtendedDynamicRangeContent = true
                }
#endif
            }
#elseif !os(tvOS)
            if #available(iOS 17.0, *) {
                displayLayer.wantsExtendedDynamicRangeContent = true
            }
#endif
            displayLayer.backgroundColor = UIColor.black.cgColor
            
            videoContainer.layer.addSublayer(displayLayer)
        }
        
        // Add VLC rendering view FIRST (before all UI elements) so it renders behind controls
        if let vlc = vlcRenderer {
            let vlcView = vlc.getRenderingView()
            videoContainer.addSubview(vlcView)
            vlcView.translatesAutoresizingMaskIntoConstraints = false
            // Ensure container remains interactive for gesture recognition
            videoContainer.isUserInteractionEnabled = true
            NSLayoutConstraint.activate([
                vlcView.topAnchor.constraint(equalTo: videoContainer.topAnchor),
                vlcView.bottomAnchor.constraint(equalTo: videoContainer.bottomAnchor),
                vlcView.leadingAnchor.constraint(equalTo: videoContainer.leadingAnchor),
                vlcView.trailingAnchor.constraint(equalTo: videoContainer.trailingAnchor)
            ])
        }
        
        videoContainer.addSubview(dimmingView)
        videoContainer.addSubview(controlsOverlayView)
        videoContainer.addSubview(loadingIndicator)
        view.addSubview(errorBanner)
        videoContainer.addSubview(centerPlayPauseButton)
        videoContainer.addSubview(progressContainer)
        videoContainer.addSubview(closeButton)
        videoContainer.addSubview(pipButton)
        videoContainer.addSubview(skipBackwardButton)
        videoContainer.addSubview(skipForwardButton)
        videoContainer.addSubview(speedIndicatorLabel)
        videoContainer.addSubview(subtitleButton)
        if isVLCPlayer {
            videoContainer.addSubview(speedButton)
            videoContainer.addSubview(audioButton)
        }
    #if !os(tvOS)
        videoContainer.addSubview(brightnessContainer)
        brightnessContainer.contentView.addSubview(brightnessSlider)
        brightnessContainer.contentView.addSubview(brightnessIcon)
    #endif

        // Hide PiP control when VLC is active (PiP remains MPV-only)
        pipButton.isHidden = (vlcRenderer != nil)
        
        NSLayoutConstraint.activate([
            videoContainer.topAnchor.constraint(equalTo: view.topAnchor),
            videoContainer.leadingAnchor.constraint(equalTo: view.leadingAnchor),
            videoContainer.trailingAnchor.constraint(equalTo: view.trailingAnchor),
            videoContainer.bottomAnchor.constraint(equalTo: view.bottomAnchor),
            
            progressContainer.leadingAnchor.constraint(equalTo: view.safeAreaLayoutGuide.leadingAnchor, constant: 12),
            progressContainer.trailingAnchor.constraint(equalTo: view.safeAreaLayoutGuide.trailingAnchor, constant: -12),
            progressContainer.bottomAnchor.constraint(equalTo: view.safeAreaLayoutGuide.bottomAnchor),
            progressContainer.heightAnchor.constraint(equalToConstant: 44),

            dimmingView.topAnchor.constraint(equalTo: videoContainer.topAnchor),
            dimmingView.leadingAnchor.constraint(equalTo: videoContainer.leadingAnchor),
            dimmingView.trailingAnchor.constraint(equalTo: videoContainer.trailingAnchor),
            dimmingView.bottomAnchor.constraint(equalTo: videoContainer.bottomAnchor),
            
            controlsOverlayView.topAnchor.constraint(equalTo: videoContainer.topAnchor),
            controlsOverlayView.leadingAnchor.constraint(equalTo: videoContainer.leadingAnchor),
            controlsOverlayView.trailingAnchor.constraint(equalTo: videoContainer.trailingAnchor),
            controlsOverlayView.bottomAnchor.constraint(equalTo: videoContainer.bottomAnchor),
        ])
        
        NSLayoutConstraint.activate([
            errorBanner.topAnchor.constraint(equalTo: view.safeAreaLayoutGuide.topAnchor, constant: 12),
            errorBanner.centerXAnchor.constraint(equalTo: view.centerXAnchor),
            errorBanner.widthAnchor.constraint(lessThanOrEqualTo: view.widthAnchor, multiplier: 0.92),
            errorBanner.heightAnchor.constraint(greaterThanOrEqualToConstant: 40),
            
            centerPlayPauseButton.centerXAnchor.constraint(equalTo: videoContainer.centerXAnchor),
            centerPlayPauseButton.centerYAnchor.constraint(equalTo: videoContainer.centerYAnchor),
            centerPlayPauseButton.widthAnchor.constraint(equalToConstant: 70),
            centerPlayPauseButton.heightAnchor.constraint(equalToConstant: 70),
            
            loadingIndicator.centerXAnchor.constraint(equalTo: centerPlayPauseButton.centerXAnchor),
            loadingIndicator.centerYAnchor.constraint(equalTo: centerPlayPauseButton.centerYAnchor),
            
            closeButton.topAnchor.constraint(equalTo: view.safeAreaLayoutGuide.topAnchor, constant: 16),
            closeButton.leadingAnchor.constraint(equalTo: progressContainer.leadingAnchor, constant: 4),
            closeButton.widthAnchor.constraint(equalToConstant: 36),
            closeButton.heightAnchor.constraint(equalToConstant: 36),
            
            pipButton.centerYAnchor.constraint(equalTo: closeButton.centerYAnchor),
            pipButton.leadingAnchor.constraint(equalTo: closeButton.trailingAnchor, constant: 16),
            pipButton.widthAnchor.constraint(equalToConstant: 36),
            pipButton.heightAnchor.constraint(equalToConstant: 36),
            
            skipBackwardButton.centerYAnchor.constraint(equalTo: centerPlayPauseButton.centerYAnchor),
            skipBackwardButton.trailingAnchor.constraint(equalTo: centerPlayPauseButton.leadingAnchor, constant: -48),
            skipBackwardButton.widthAnchor.constraint(equalToConstant: 50),
            skipBackwardButton.heightAnchor.constraint(equalToConstant: 50),
            
            skipForwardButton.centerYAnchor.constraint(equalTo: centerPlayPauseButton.centerYAnchor),
            skipForwardButton.leadingAnchor.constraint(equalTo: centerPlayPauseButton.trailingAnchor, constant: 48),
            skipForwardButton.widthAnchor.constraint(equalToConstant: 50),
            skipForwardButton.heightAnchor.constraint(equalToConstant: 50),
            
            speedIndicatorLabel.topAnchor.constraint(equalTo: videoContainer.safeAreaLayoutGuide.topAnchor, constant: 20),
            speedIndicatorLabel.centerXAnchor.constraint(equalTo: videoContainer.centerXAnchor),
            speedIndicatorLabel.widthAnchor.constraint(equalToConstant: 100),
            speedIndicatorLabel.heightAnchor.constraint(equalToConstant: 40),
            
            subtitleButton.trailingAnchor.constraint(equalTo: progressContainer.trailingAnchor, constant: 0),
            subtitleButton.bottomAnchor.constraint(equalTo: progressContainer.topAnchor, constant: -8),
            subtitleButton.widthAnchor.constraint(equalToConstant: 32),
            subtitleButton.heightAnchor.constraint(equalToConstant: 32)
        ])
        if isVLCPlayer {
            NSLayoutConstraint.activate([
                speedButton.trailingAnchor.constraint(equalTo: subtitleButton.leadingAnchor, constant: -8),
                speedButton.centerYAnchor.constraint(equalTo: subtitleButton.centerYAnchor),
                speedButton.widthAnchor.constraint(equalToConstant: 32),
                speedButton.heightAnchor.constraint(equalToConstant: 32),

                audioButton.trailingAnchor.constraint(equalTo: speedButton.leadingAnchor, constant: -8),
                audioButton.centerYAnchor.constraint(equalTo: subtitleButton.centerYAnchor),
                audioButton.widthAnchor.constraint(equalToConstant: 32),
                audioButton.heightAnchor.constraint(equalToConstant: 32)
            ])
        }
#if !os(tvOS)
        NSLayoutConstraint.activate([
            brightnessContainer.leadingAnchor.constraint(equalTo: view.safeAreaLayoutGuide.leadingAnchor, constant: 12),
            brightnessContainer.centerYAnchor.constraint(equalTo: videoContainer.centerYAnchor),
            brightnessContainer.widthAnchor.constraint(equalToConstant: 52),
            brightnessContainer.heightAnchor.constraint(equalToConstant: 220),

            brightnessSlider.centerXAnchor.constraint(equalTo: brightnessContainer.contentView.centerXAnchor),
            brightnessSlider.centerYAnchor.constraint(equalTo: brightnessContainer.contentView.centerYAnchor),
            brightnessSlider.widthAnchor.constraint(equalTo: brightnessContainer.contentView.heightAnchor, multiplier: 0.82),
            brightnessSlider.heightAnchor.constraint(equalToConstant: 34),

            brightnessIcon.centerXAnchor.constraint(equalTo: brightnessContainer.contentView.centerXAnchor),
            brightnessIcon.topAnchor.constraint(equalTo: brightnessContainer.contentView.topAnchor, constant: 8),
            brightnessIcon.heightAnchor.constraint(equalToConstant: 20),
            brightnessIcon.widthAnchor.constraint(equalToConstant: 20)
        ])
#endif
        
        // CRITICAL: After all UI elements are added, ensure VLC view is at the very back
        if let vlc = vlcRenderer {
            let vlcView = vlc.getRenderingView()
            videoContainer.sendSubviewToBack(vlcView)
            // Double-ensure VLC view doesn't steal touches
            vlcView.isUserInteractionEnabled = false
            #if !os(tvOS)
            vlcView.isExclusiveTouch = false
            #endif
            
            // Add transparent tap overlay on top to guarantee tap detection
            videoContainer.addSubview(tapOverlayView)
            NSLayoutConstraint.activate([
                tapOverlayView.topAnchor.constraint(equalTo: videoContainer.topAnchor),
                tapOverlayView.leadingAnchor.constraint(equalTo: videoContainer.leadingAnchor),
                tapOverlayView.trailingAnchor.constraint(equalTo: videoContainer.trailingAnchor),
                tapOverlayView.bottomAnchor.constraint(equalTo: videoContainer.bottomAnchor)
            ])
        }
    }
    
    private func setupActions() {
        centerPlayPauseButton.addTarget(self, action: #selector(centerPlayPauseTapped), for: .touchUpInside)
        closeButton.addTarget(self, action: #selector(closeTapped), for: .touchUpInside)
        pipButton.addTarget(self, action: #selector(pipTapped), for: .touchUpInside)
        skipBackwardButton.addTarget(self, action: #selector(skipBackwardTapped), for: .touchUpInside)
        skipForwardButton.addTarget(self, action: #selector(skipForwardTapped), for: .touchUpInside)
        if isVLCPlayer {
            subtitleButton.addTarget(self, action: #selector(subtitleButtonTapped), for: .touchUpInside)
        }
        
        // Ensure buttons work with VLC
        if vlcRenderer != nil {
            [centerPlayPauseButton, closeButton, pipButton, skipBackwardButton,
             skipForwardButton, subtitleButton, speedButton, audioButton].forEach {
                $0.isUserInteractionEnabled = true
            }
        }
        
        let tap = UITapGestureRecognizer(target: self, action: #selector(containerTapped))
        if vlcRenderer != nil {
            tap.delegate = self
            tap.cancelsTouchesInView = false
            tap.delaysTouchesBegan = false
            tapOverlayView.addGestureRecognizer(tap)
        } else {
            videoContainer.addGestureRecognizer(tap)
        }
        containerTapGesture = tap
    }
    
    private func setupHoldGesture() {
        holdGesture = UILongPressGestureRecognizer(target: self, action: #selector(handleHoldGesture(_:)))
        holdGesture?.minimumPressDuration = 0.5
        if let holdGesture = holdGesture {
            videoContainer.addGestureRecognizer(holdGesture)
        }
    }
    
    private func setupDoubleTapSkipGestures() {
        let leftDoubleTap = UITapGestureRecognizer(target: self, action: #selector(leftSideDoubleTapped))
        leftDoubleTap.numberOfTapsRequired = 2
        leftDoubleTap.delegate = self
        leftDoubleTapGesture = leftDoubleTap
        videoContainer.addGestureRecognizer(leftDoubleTap)
        
        let rightDoubleTap = UITapGestureRecognizer(target: self, action: #selector(rightSideDoubleTapped))
        rightDoubleTap.numberOfTapsRequired = 2
        rightDoubleTap.delegate = self
        rightDoubleTapGesture = rightDoubleTap
        videoContainer.addGestureRecognizer(rightDoubleTap)
        
        if let tap = containerTapGesture {
            tap.require(toFail: leftDoubleTap)
            tap.require(toFail: rightDoubleTap)
        }
        
        #if !os(tvOS)
        if isTwoFingerTapEnabled {
            let twoFingerTap = UITapGestureRecognizer(target: self, action: #selector(twoFingerTapped))
            twoFingerTap.numberOfTouchesRequired = 2
            twoFingerTap.delegate = self
            videoContainer.addGestureRecognizer(twoFingerTap)
        }
        #endif
    }

    @objc private func leftSideDoubleTapped(_ gesture: UITapGestureRecognizer) {
        let location = gesture.location(in: videoContainer)
        let isLeftSide = location.x < videoContainer.bounds.width / 2
        guard isLeftSide else { return }
        rendererSeek(by: -10)
        animateButtonTap(skipBackwardButton)
    }

    @objc private func rightSideDoubleTapped(_ gesture: UITapGestureRecognizer) {
        let location = gesture.location(in: videoContainer)
        let isRightSide = location.x >= videoContainer.bounds.width / 2
        guard isRightSide else { return }
        rendererSeek(by: 10)
        animateButtonTap(skipForwardButton)
    }

    @objc private func twoFingerTapped(_ gesture: UITapGestureRecognizer) {
        // Two-finger tap: toggle play/pause without showing UI
        if rendererIsPausedState() {
            rendererPlay()
            updatePlayPauseButton(isPaused: false, shouldShowControls: false)
        } else {
            rendererPausePlayback()
            updatePlayPauseButton(isPaused: true, shouldShowControls: false)
        }
    }

    private func setupBrightnessControls() {
#if !os(tvOS)
        brightnessSlider.addTarget(self, action: #selector(brightnessSliderChanged(_:)), for: .valueChanged)
        loadBrightnessLevel()
        updateBrightnessControlVisibility()
#endif
    }

#if !os(tvOS)
    private func loadBrightnessLevel() {
        if UserDefaults.standard.object(forKey: brightnessLevelKey) == nil {
            UserDefaults.standard.set(Float(UIScreen.main.brightness), forKey: brightnessLevelKey)
        }
        let stored = UserDefaults.standard.float(forKey: brightnessLevelKey)
        brightnessLevel = max(0.0, min(stored, 1.0))
        brightnessSlider.value = brightnessLevel
        applyBrightnessLevel(brightnessLevel)
    }

    @objc private func brightnessSliderChanged(_ sender: UISlider) {
        applyBrightnessLevel(sender.value)
        showControlsTemporarily()
    }

    private func applyBrightnessLevel(_ value: Float) {
        if isClosing { return }
        let clamped = max(0.0, min(value, 1.0))
        brightnessLevel = clamped
        UserDefaults.standard.set(clamped, forKey: brightnessLevelKey)
        DispatchQueue.main.async { [weak self] in
            guard let self else { return }
            if self.isClosing { return }
            self.dimmingView.alpha = 0.0
        }
    }

    private func updateBrightnessControlVisibility() {
        if isClosing { return }
        brightnessContainer.isHidden = true
        brightnessContainer.alpha = 0.0
    }

#else
    // tvOS stub to satisfy shared call sites when brightness UI is unavailable
    private func updateBrightnessControlVisibility() { }
#endif

    @objc private func handleHoldGesture(_ gesture: UILongPressGestureRecognizer) {
        switch gesture.state {
        case .began:
            beginHoldSpeed()
        case .ended, .cancelled:
            endHoldSpeed()
        default:
            break
        }
    }
    
    private func beginHoldSpeed() {
        originalSpeed = rendererGetSpeed()
        let holdSpeed = UserDefaults.standard.float(forKey: "holdSpeedPlayer")
        let targetSpeed = holdSpeed > 0 ? Double(holdSpeed) : 2.0
        rendererSetSpeed(targetSpeed)
        
        DispatchQueue.main.async { [weak self] in
            guard let self = self else { return }
            self.speedIndicatorLabel.text = String(format: "%.1fx", targetSpeed)
            UIView.animate(withDuration: 0.2) {
                self.speedIndicatorLabel.alpha = 1.0
            }
        }
    }
    
    private func endHoldSpeed() {
        rendererSetSpeed(originalSpeed)
        
        DispatchQueue.main.async { [weak self] in
            UIView.animate(withDuration: 0.2) {
                self?.speedIndicatorLabel.alpha = 0.0
            }
        }
    }
    
    @objc private func playPauseTapped() {
        if rendererIsPausedState() {
            rendererPlay()
            updatePlayPauseButton(isPaused: false)
        } else {
            rendererPausePlayback()
            updatePlayPauseButton(isPaused: true)
        }
    }
    
    @objc private func centerPlayPauseTapped() {
        playPauseTapped()
    }
    
    @objc private func skipBackwardTapped() {
        rendererSeek(by: isVLCPlayer ? -10 : -15)
        animateButtonTap(skipBackwardButton)
        showControlsTemporarily()
    }
    
    @objc private func skipForwardTapped() {
        rendererSeek(by: isVLCPlayer ? 10 : 15)
        animateButtonTap(skipForwardButton)
        showControlsTemporarily()
    }
    private func updateSubtitleMenu() {
        var trackActions: [UIAction] = []
        
        let disableAction = UIAction(
            title: "Disable Subtitles",
            image: UIImage(systemName: "xmark"),
            state: subtitleModel.isVisible ? .off : .on
        ) { [weak self] _ in
            self?.subtitleModel.isVisible = false
            self?.updateSubtitleButtonAppearance()
            self?.updateSubtitleMenu()
        }
        trackActions.append(disableAction)
        
        for (index, _) in subtitleURLs.enumerated() {
            let isSelected = subtitleModel.isVisible && currentSubtitleIndex == index
            let action = UIAction(
                title: "Subtitle \(index + 1)",
                image: UIImage(systemName: "captions.bubble"),
                state: isSelected ? .on : .off
            ) { [weak self] _ in
                self?.currentSubtitleIndex = index
                self?.subtitleModel.isVisible = true
                self?.loadCurrentSubtitle()
                self?.updateSubtitleButtonAppearance()
                self?.updateSubtitleMenu()
            }
            trackActions.append(action)
        }
        
        let trackMenu = UIMenu(title: "Select Track", image: UIImage(systemName: "list.bullet"), children: trackActions)
        
        let appearanceMenu = createAppearanceMenu()
        
        let mainMenu = UIMenu(title: "Subtitles", children: [trackMenu, appearanceMenu])
        subtitleButton.menu = mainMenu
    }
    
    private func createAppearanceMenu() -> UIMenu {
        let foregroundColors: [(String, UIColor)] = [
            ("White", .white),
            ("Yellow", .yellow),
            ("Cyan", .cyan),
            ("Green", .green),
            ("Magenta", .magenta)
        ]
        
        let foregroundColorActions = foregroundColors.map { (name, color) in
            UIAction(
                title: name,
                state: subtitleModel.foregroundColor == color ? .on : .off
            ) { [weak self] _ in
                self?.subtitleModel.foregroundColor = color
                self?.updateCurrentSubtitleAppearance()
                self?.updateSubtitleMenu()
            }
        }
        
        let foregroundColorMenu = UIMenu(title: "Text Color", image: UIImage(systemName: "paintpalette"), children: foregroundColorActions)
        
        let strokeColors: [(String, UIColor)] = [
            ("Black", .black),
            ("Dark Gray", .darkGray),
            ("White", .white),
            ("None", .clear)
        ]
        
        let strokeColorActions = strokeColors.map { (name, color) in
            UIAction(
                title: name,
                state: subtitleModel.strokeColor == color ? .on : .off
            ) { [weak self] _ in
                self?.subtitleModel.strokeColor = color
                self?.updateCurrentSubtitleAppearance()
                self?.updateSubtitleMenu()
            }
        }
        
        let strokeColorMenu = UIMenu(title: "Stroke Color", image: UIImage(systemName: "pencil.tip"), children: strokeColorActions)
        
        let strokeWidths: [(String, CGFloat)] = [
            ("None", 0.0),
            ("Thin", 0.5),
            ("Normal", 1.0),
            ("Medium", 1.5),
            ("Thick", 2.0)
        ]
        
        let strokeWidthActions = strokeWidths.map { (name, width) in
            UIAction(
                title: name,
                state: subtitleModel.strokeWidth == width ? .on : .off
            ) { [weak self] _ in
                self?.subtitleModel.strokeWidth = width
                self?.updateCurrentSubtitleAppearance()
                self?.updateSubtitleMenu()
            }
        }
        
        let strokeWidthMenu = UIMenu(title: "Stroke Width", image: UIImage(systemName: "lineweight"), children: strokeWidthActions)
        
        let fontSizes: [(String, CGFloat)] = [
            ("Small", 34.0),
            ("Medium", 38.0),
            ("Large", 42.0),
            ("Extra Large", 46.0),
            ("Huge", 56.0),
            ("Extra Huge", 66.0)
        ]
        
        let fontSizeActions = fontSizes.map { (name, size) in
            UIAction(
                title: name,
                state: subtitleModel.fontSize == size ? .on : .off
            ) { [weak self] _ in
                self?.subtitleModel.fontSize = size
                self?.updateCurrentSubtitleAppearance()
                self?.updateSubtitleMenu()
            }
        }
        
        let fontSizeMenu = UIMenu(title: "Font Size", image: UIImage(systemName: "textformat.size"), children: fontSizeActions)
        
        return UIMenu(title: "Appearance", image: UIImage(systemName: "paintbrush"), children: [
            foregroundColorMenu,
            strokeColorMenu,
            strokeWidthMenu,
            fontSizeMenu
        ])
    }
    
    private func updateCurrentSubtitleAppearance() {
        if subtitleModel.isVisible && currentSubtitleIndex < subtitleURLs.count {
            loadCurrentSubtitle()
        }
    }
    
    private func updateSubtitleButtonAppearance() {
        let cfg = UIImage.SymbolConfiguration(pointSize: 16, weight: .semibold)
        let imageName = subtitleModel.isVisible ? "captions.bubble.fill" : "captions.bubble"
        let img = UIImage(systemName: imageName, withConfiguration: cfg)
        subtitleButton.setImage(img, for: .normal)
    }
    
    private func updateSpeedMenu() {
        let currentSpeed = rendererGetSpeed()
        let speeds: [(String, Double)] = [
            ("0.25x", 0.25),
            ("0.5x", 0.5),
            ("0.75x", 0.75),
            ("1.0x", 1.0),
            ("1.25x", 1.25),
            ("1.5x", 1.5),
            ("1.75x", 1.75),
            ("2.0x", 2.0)
        ]
        
        let speedActions = speeds.map { (name, speed) in
            UIAction(
                title: name,
                state: abs(currentSpeed - speed) < 0.01 ? .on : .off
            ) { [weak self] _ in
                self?.rendererSetSpeed(speed)
                self?.speedIndicatorLabel.text = String(format: "%.2fx", speed)
                DispatchQueue.main.async {
                    UIView.animate(withDuration: 0.2) {
                        self?.speedIndicatorLabel.alpha = 1.0
                    } completion: { _ in
                        DispatchQueue.main.asyncAfter(deadline: .now() + 1.5) {
                            UIView.animate(withDuration: 0.2) {
                                self?.speedIndicatorLabel.alpha = 0.0
                            }
                        }
                    }
                }
                self?.updateSpeedMenu()
            }
        }
        
        let speedMenu = UIMenu(title: "Playback Speed", image: UIImage(systemName: "hare.fill"), children: speedActions)
        speedButton.menu = speedMenu
    }
    
    private func updateAudioTracksMenuWhenReady() {
        guard isVLCPlayer else { return }
        // Stop retrying if user manually selected a track
        if userSelectedAudioTrack {
            updateAudioTracksMenu()
            return
        }
        
        let detailedTracks = rendererGetAudioTracksDetailed()
        
        // If tracks are populated, proceed with auto-selection
        if !detailedTracks.isEmpty {
            updateAudioTracksMenu()
            return
        }
        
        // Tracks not ready yet - retry shortly (works for both VLC and MPV)
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.2) { [weak self] in
            self?.updateAudioTracksMenuWhenReady()
        }
    }

    private func updateSubtitleTracksMenuWhenReady(attempt: Int = 0) {
        guard isVLCPlayer else { return }
        if userSelectedSubtitleTrack {
            updateSubtitleTracksMenu()
            return
        }

        if !subtitleURLs.isEmpty && vlcRenderer == nil {
            updateSubtitleTracksMenu()
            return
        }

        let tracks = rendererGetSubtitleTracks()
        if !tracks.isEmpty || attempt >= 20 {
            updateSubtitleTracksMenu()
            return
        }

        DispatchQueue.main.asyncAfter(deadline: .now() + 0.2) { [weak self] in
            self?.updateSubtitleTracksMenuWhenReady(attempt: attempt + 1)
        }
    }
    
    private func updateAudioTracksMenu() {
        guard isVLCPlayer else {
            audioButton.isHidden = true
            return
        }
        let detailedTracks = rendererGetAudioTracksDetailed()
        let tracks = detailedTracks.map { ($0.0, $0.1) }
        var trackActions: [UIAction] = []
        
        // Always show the audio button so the user can view the menu even when empty
        audioButton.isHidden = false

        Logger.shared.log("PlayerViewController: audio tracks count=\(tracks.count) isAnime=\(isAnimeContent()) userSelected=\(userSelectedAudioTrack) renderer=\(vlcRenderer != nil ? "VLC" : "MPV")", type: "Player")
        
        if tracks.isEmpty {
            let noTracksAction = UIAction(title: "No audio tracks available", state: .off) { _ in }
            let audioMenu = UIMenu(title: "Audio Tracks", image: UIImage(systemName: "speaker.wave.2"), children: [noTracksAction])
            audioButton.menu = audioMenu
            return
        }

        let currentAudioTrackId = rendererGetCurrentAudioTrackId()
        trackActions = tracks.map { (id, name) in
            UIAction(
                title: name,
                state: id == currentAudioTrackId ? .on : .off
            ) { [weak self] _ in
                self?.userSelectedAudioTrack = true
                self?.rendererSetAudioTrack(id: id)
                // Debounce menu update to avoid lag - only update after 0.3s of no selection changes
                self?.audioMenuDebounceTimer?.invalidate()
                self?.audioMenuDebounceTimer = Timer.scheduledTimer(withTimeInterval: 0.3, repeats: false) { _ in
                    DispatchQueue.main.async { [weak self] in
                        self?.updateAudioTracksMenu()
                    }
                }
            }
        }

        // Auto-select preferred anime audio language when applicable and user hasn't picked a track yet
        if isAnimeContent() && !userSelectedAudioTrack {
            let preferredLang = Settings.shared.preferredAnimeAudioLanguage.lowercased()
            let tokens = languageTokens(for: preferredLang)

            if !preferredLang.isEmpty {
                Logger.shared.log("PlayerViewController: Auto anime audio - preferredLang=\(preferredLang), tokens=\(tokens.joined(separator: ",")), detailedTracks=\(detailedTracks.count)", type: "Player")

                if let matching = detailedTracks.first(where: {
                    let langCode = $0.2.lowercased()
                    let title = $0.1.lowercased()
                    return tokens.contains(where: { token in
                        langCode.contains(token) || title.contains(token)
                    })
                }) {
                    Logger.shared.log("PlayerViewController: Auto-selected anime audio track: \(matching.1) (ID: \(matching.0))", type: "Player")
                    userSelectedAudioTrack = true
                    rendererSetAudioTrack(id: matching.0)
                } else {
                    Logger.shared.log("PlayerViewController: No matching anime audio track found for lang=\(preferredLang)", type: "Player")
                }
            } else {
                Logger.shared.log("PlayerViewController: Auto anime audio skipped (preferred language empty)", type: "Player")
            }
        } else if !isAnimeContent() {
            Logger.shared.log("PlayerViewController: Auto anime audio skipped (isAnime=false)", type: "Player")
        } else if userSelectedAudioTrack {
            Logger.shared.log("PlayerViewController: Auto anime audio skipped (user already selected)", type: "Player")
        }
        
        let audioMenu = UIMenu(title: "Audio Tracks", image: UIImage(systemName: "speaker.wave.2"), children: trackActions)
        audioButton.menu = audioMenu
    }

    private func isAnimeContent() -> Bool {
        if let hint = isAnimeHint, hint == true { return true }
        guard let info = mediaInfo else { return false }
        switch info {
        case .movie(_, _, _, let isAnime):
            return isAnime
        case .episode(let showId, _, _, _, _, let isAnime):
            if isAnime { return true }
            return trackerManager.cachedAniListId(for: showId) != nil
        }
    }

    private func isLocalFile() -> Bool {
        return initialURL?.isFileURL == true
    }

    private func languageName(for code: String) -> String {
        switch code.lowercased() {
        case "jpn", "ja", "jp": return "japanese"
        case "eng", "en", "us", "uk": return "english"
        case "spa", "es", "esp": return "spanish"
        case "fre", "fra", "fr": return "french"
        case "ger", "deu", "de": return "german"
        case "ita", "it": return "italian"
        case "por", "pt": return "portuguese"
        case "rus", "ru": return "russian"
        case "chi", "zho", "zh": return "chinese"
        case "kor", "ko": return "korean"
        default: return ""
        }
    }

    private func languageTokens(for preferred: String) -> [String] {
        let lower = preferred.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        guard !lower.isEmpty else { return [] }

        let map: [String: [String]] = [
            "jpn": ["jpn", "ja", "jp", "japanese"],
            "eng": ["eng", "en", "us", "uk", "english"],
            "spa": ["spa", "es", "esp", "spanish", "lat"],
            "fre": ["fre", "fra", "fr", "french"],
            "ger": ["ger", "deu", "de", "german"],
            "ita": ["ita", "it", "italian"],
            "por": ["por", "pt", "br", "portuguese"],
            "rus": ["rus", "ru", "russian"],
            "chi": ["chi", "zho", "zh", "chinese", "mandarin", "cantonese"],
            "kor": ["kor", "ko", "korean"]
        ]

        if let tokens = map[lower] {
            return tokens
        }

        let name = languageName(for: lower)
        if name.isEmpty {
            return [lower]
        }
        return [lower, name]
    }

    #if !os(tvOS)
    private func buildProxyHeaders(for url: URL, baseHeaders: [String: String]) -> [String: String] {
        var headers = baseHeaders
        if headers["User-Agent"] == nil {
            headers["User-Agent"] = URLSession.randomUserAgent
        }
        if headers["Origin"] == nil, let host = url.host, let scheme = url.scheme {
            headers["Origin"] = "\(scheme)://\(host)"
        }
        if headers["Referer"] == nil {
            headers["Referer"] = url.absoluteString
        }
        return headers
    }

    private func proxySubtitleURLs(_ urls: [String], headers: [String: String]) -> [String] {
        let proxied = urls.compactMap { urlString -> String? in
            guard let url = URL(string: urlString),
                  let scheme = url.scheme?.lowercased(),
                  scheme == "http" || scheme == "https" else {
                Logger.shared.log("PlayerViewController: subtitle proxy skipped (invalid URL or scheme)", type: "Stream")
                return nil
            }

            let proxyHeaders = buildProxyHeaders(for: url, baseHeaders: headers)
            guard let proxiedURL = VLCHeaderProxy.shared.makeProxyURL(for: url, headers: proxyHeaders) else {
                Logger.shared.log("PlayerViewController: subtitle proxy URL creation failed", type: "Stream")
                return nil
            }
            return proxiedURL.absoluteString
        }
        Logger.shared.log("PlayerViewController: subtitle proxy result count=\(proxied.count) of \(urls.count)", type: "Stream")
        return proxied
    }

    private func attemptVlcProxyFallbackIfNeeded() -> Bool {
        guard vlcRenderer != nil else { return false }
        guard !vlcProxyFallbackTried else { return false }
        guard let originalURL = initialURL, originalURL.host != "127.0.0.1" else { return false }
        guard let headers = initialHeaders, !headers.isEmpty else { return false }

        let proxyEnabled = UserDefaults.standard.object(forKey: "vlcHeaderProxyEnabled") as? Bool ?? true
        guard proxyEnabled else { return false }
        guard let preset = initialPreset else { return false }

        let proxyHeaders = buildProxyHeaders(for: originalURL, baseHeaders: headers)
        guard let proxyURL = VLCHeaderProxy.shared.makeProxyURL(for: originalURL, headers: proxyHeaders) else {
            return false
        }

        let fallbackSubtitles: [String]?
        if let subs = initialSubtitles, !subs.isEmpty {
            Logger.shared.log("PlayerViewController: proxy fallback subtitle count=\(subs.count)", type: "Stream")
            let proxiedSubs = proxySubtitleURLs(subs, headers: headers)
            if proxiedSubs.count == subs.count {
                Logger.shared.log("PlayerViewController: proxy fallback subtitles ready", type: "Stream")
                fallbackSubtitles = proxiedSubs
            } else {
                Logger.shared.log("PlayerViewController: proxy fallback subtitles incomplete; using direct URLs", type: "Stream")
                fallbackSubtitles = subs
            }
        } else {
            fallbackSubtitles = nil
        }

        vlcProxyFallbackTried = true
        initialSubtitles = fallbackSubtitles

        Logger.shared.log("PlayerViewController: VLC proxy fallback activated", type: "Stream")
        load(url: proxyURL, preset: preset, headers: nil)
        return true
    }
    #else
    private func attemptVlcProxyFallbackIfNeeded() -> Bool {
        return false
    }
    #endif
    
    private func updateSubtitleTracksMenu() {
        guard isVLCPlayer else {
            return
        }
        let useExternalMenu = !subtitleURLs.isEmpty && vlcRenderer == nil
        let rawTracks: [(Int, String)] = useExternalMenu
            ? subtitleURLs.enumerated().map { ($0.offset, "Subtitle \($0.offset + 1)") }
            : rendererGetSubtitleTracks()
        let tracks = useExternalMenu
            ? rawTracks
            : rawTracks.filter { $0.0 >= 0 && !isDisabledTrackName($0.1) }

        Logger.shared.log("PlayerViewController: subtitle tracks count=\(tracks.count) external=\(useExternalMenu) userSelected=\(userSelectedSubtitleTrack) renderer=\(vlcRenderer != nil ? "VLC" : "MPV")", type: "Player")

        // Always show the subtitle button so the user can view the menu even when empty
        subtitleButton.isHidden = false

        // Use menu-only behavior for both VLC and MPV so the UI looks consistent
        subtitleButton.showsMenuAsPrimaryAction = true

        // Apply default subtitle settings if enabled and tracks exist
        if !tracks.isEmpty && !userSelectedSubtitleTrack {
            let settings = Settings.shared
            if settings.enableSubtitlesByDefault {
                let preferredLang = settings.defaultSubtitleLanguage
                let tokens = languageTokens(for: preferredLang)
                let matchingTrack = tracks.first(where: { track in
                    let nameLower = track.1.lowercased()
                    if tokens.contains(where: { nameLower.contains($0) }) {
                        return true
                    }
                    if useExternalMenu, track.0 < subtitleURLs.count {
                        let urlLower = subtitleURLs[track.0].lowercased()
                        return tokens.contains(where: { urlLower.contains($0) })
                    }
                    return false
                })
                Logger.shared.log("PlayerViewController: default subtitles enabled lang=\(preferredLang) tokens=\(tokens.joined(separator: ",")) match=\(matchingTrack?.1 ?? "nil")", type: "Player")
                let selectedTrack = matchingTrack ?? tracks.first
                if let selectedTrack {
                    if useExternalMenu {
                        currentSubtitleIndex = selectedTrack.0
                        loadCurrentSubtitle()
                    } else {
                        rendererSetSubtitleTrack(id: selectedTrack.0)
                    }
                    userSelectedSubtitleTrack = true
                    subtitleModel.isVisible = true
                    updateSubtitleButtonAppearance()
                }
            }
        }
        
        var trackActions: [UIAction] = []

        let disableAction = UIAction(
            title: "Disable Subtitles",
            image: UIImage(systemName: "xmark"),
            state: .off
        ) { [weak self] _ in
            self?.subtitleModel.isVisible = false
            self?.userSelectedSubtitleTrack = true
            if useExternalMenu {
                self?.rendererRefreshSubtitleOverlay()
            } else {
                self?.rendererDisableSubtitles()
            }
            self?.updateSubtitleButtonAppearance()
            self?.updateSubtitleTracksMenu()
        }
        trackActions.append(disableAction)
        
        if tracks.isEmpty {
            // Inform the user; keep menu available
            let noTracksAction = UIAction(title: "No subtitles in stream", state: .off) { _ in }
            trackActions.append(noTracksAction)
        } else {
            let currentSubtitleTrackId = useExternalMenu ? currentSubtitleIndex : rendererGetCurrentSubtitleTrackId()
            let subtitleActions = tracks.map { (id, name) in
                UIAction(
                    title: name,
                    image: UIImage(systemName: "captions.bubble"),
                    state: id == currentSubtitleTrackId ? .on : .off
                ) { [weak self] _ in
                    guard let self else { return }
                    self.subtitleModel.isVisible = true
                    self.userSelectedSubtitleTrack = true
                    if useExternalMenu {
                        self.currentSubtitleIndex = id
                        self.loadCurrentSubtitle()
                    } else {
                        self.rendererSetSubtitleTrack(id: id)
                    }
                    self.updateSubtitleButtonAppearance()
                    // Debounce menu update to avoid lag - only update after 0.3s of no selection changes
                    self.subtitleMenuDebounceTimer?.invalidate()
                    self.subtitleMenuDebounceTimer = Timer.scheduledTimer(withTimeInterval: 0.3, repeats: false) { _ in
                        DispatchQueue.main.async { [weak self] in
                            self?.updateSubtitleTracksMenu()
                        }
                    }
                }
            }
            trackActions.append(contentsOf: subtitleActions)
        }
        
        let subtitleMenu = UIMenu(title: "Subtitles", image: UIImage(systemName: "captions.bubble"), children: trackActions)
        subtitleButton.menu = subtitleMenu
    }

    private func isDisabledTrackName(_ name: String) -> Bool {
        let lower = name.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        return lower.contains("disable") || lower.contains("off") || lower.contains("none")
    }
    private func loadSubtitles(_ urls: [String]) {
        subtitleURLs = urls
        userSelectedSubtitleTrack = false
        
        if !urls.isEmpty {
            Logger.shared.log("PlayerViewController: loadSubtitles count=\(urls.count) renderer=\(vlcRenderer != nil ? "VLC" : "MPV")", type: "Stream")
            subtitleButton.isHidden = false
            currentSubtitleIndex = 0
            let enableByDefault = isVLCPlayer ? Settings.shared.enableSubtitlesByDefault : true
            subtitleModel.isVisible = enableByDefault
            
            // VLC can load external subtitles natively; MPV uses manual parsing
            if vlcRenderer != nil {
                rendererLoadExternalSubtitles(urls: urls)
                // Update subtitle menu after VLC loads the external subs
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) { [weak self] in
                    self?.updateSubtitleTracksMenu()
                }
                DispatchQueue.main.asyncAfter(deadline: .now() + 1.5) { [weak self] in
                    guard let self else { return }
                    let tracks = self.rendererGetSubtitleTracks()
                    if tracks.isEmpty {
                        Logger.shared.log("PlayerViewController: VLC external subtitles not detected after load", type: "Stream")
                    } else {
                        Logger.shared.log("PlayerViewController: VLC subtitle tracks available count=\(tracks.count)", type: "Stream")
                        if enableByDefault, !self.userSelectedSubtitleTrack, self.rendererGetCurrentSubtitleTrackId() == -1 {
                            self.rendererSetSubtitleTrack(id: tracks[0].0)
                            self.subtitleModel.isVisible = true
                            self.userSelectedSubtitleTrack = true
                            self.updateSubtitleButtonAppearance()
                        }
                    }
                }
            } else {
                loadCurrentSubtitle()
            }
            
            updateSubtitleButtonAppearance()
            if isVLCPlayer {
                updateSubtitleTracksMenu()
            } else {
                updateSubtitleMenu()
            }
        } else {
            Logger.shared.log("No subtitle URLs to load", type: "Info")
        }
    }
    
    private func loadCurrentSubtitle() {
        guard currentSubtitleIndex < subtitleURLs.count else { return }
        let urlString = subtitleURLs[currentSubtitleIndex]

        if !isVLCPlayer {
            guard let url = URL(string: urlString) else {
                Logger.shared.log("Invalid subtitle URL: \(urlString)", type: "Error")
                return
            }

            URLSession.custom.dataTask(with: url) { [weak self] data, _, error in
                guard let self else { return }

                if let error = error {
                    Logger.shared.log("Failed to download subtitles: \(error.localizedDescription)", type: "Error")
                    return
                }

                guard let data = data, let subtitleContent = String(data: data, encoding: .utf8) else {
                    Logger.shared.log("Failed to parse subtitle data", type: "Error")
                    return
                }

                self.parseAndDisplaySubtitles(subtitleContent)
            }.resume()
            return
        }
        
        Logger.shared.log("Loading subtitle from: \(urlString)", type: "Info")
        
        guard let url = URL(string: urlString) else {
            Logger.shared.log("Invalid subtitle URL: \(urlString)", type: "Error")
            return
        }
        
        var request = URLRequest(url: url)
        request.setValue(URLSession.randomUserAgent, forHTTPHeaderField: "User-Agent")
        request.setValue(url.scheme! + "://" + (url.host ?? ""), forHTTPHeaderField: "Origin")
        request.setValue(url.absoluteString, forHTTPHeaderField: "Referer")
        request.timeoutInterval = 30
        
        // Download on background queue to avoid blocking main thread
        DispatchQueue.global(qos: .userInitiated).async { [weak self] in
            guard let self = self else { return }
            
            URLSession.custom.dataTask(with: request) { [weak self] data, response, error in
                guard let self = self else { return }
                
                if let error = error {
                    Logger.shared.log("Failed to download subtitles: \(error.localizedDescription)", type: "Error")
                    return
                }
                
                if let httpResponse = response as? HTTPURLResponse {
                    Logger.shared.log("Subtitle download response: \(httpResponse.statusCode)", type: "Info")
                    if httpResponse.statusCode != 200 {
                        Logger.shared.log("Subtitle download failed with status \(httpResponse.statusCode)", type: "Error")
                        return
                    }
                }
                
                guard let data = data, let subtitleContent = String(data: data, encoding: .utf8) else {
                    Logger.shared.log("Failed to parse subtitle data (size: \(data?.count ?? 0) bytes)", type: "Error")
                    return
                }
                
                Logger.shared.log("Subtitle content loaded: \(subtitleContent.prefix(100))...", type: "Info")
                
                // Parse subtitles on background queue (heavy text processing)
                DispatchQueue.global(qos: .userInitiated).async { [weak self] in
                    guard let self = self else { return }
                    self.parseAndDisplaySubtitles(subtitleContent)
                }
            }.resume()
        }
    }
    
    private func parseAndDisplaySubtitles(_ content: String) {
        if !isVLCPlayer {
            subtitleEntries = SubtitleLoader.parseSubtitles(from: content, fontSize: subtitleModel.fontSize, foregroundColor: subtitleModel.foregroundColor)
            Logger.shared.log("Loaded \(subtitleEntries.count) subtitle entries", type: "Info")
            return
        }

        DispatchQueue.main.async { [weak self] in
            guard let self = self else { return }
            self.subtitleEntries = SubtitleLoader.parseSubtitles(from: content, fontSize: self.subtitleModel.fontSize, foregroundColor: self.subtitleModel.foregroundColor)
            Logger.shared.log("Loaded \(self.subtitleEntries.count) subtitle entries", type: "Info")
            self.rendererRefreshSubtitleOverlay()
        }
    }
    
    @objc private func subtitleButtonTapped() {
        // Menu-first UI (VLC + MPV). When menu is primary, do not show action sheets.
        if subtitleButton.showsMenuAsPrimaryAction {
            return
        }

        // VLC uses menu system directly; this handler is for MPV only
        if vlcRenderer != nil {
            return
        }
        
        // External subtitles present (MPV)
        if !subtitleURLs.isEmpty {
            if subtitleURLs.count == 1 {
                subtitleModel.isVisible.toggle()
                rendererRefreshSubtitleOverlay()
                updateSubtitleButtonAppearance()
            } else {
                showSubtitleSelectionMenu()
            }
            showControlsTemporarily()
            Logger.shared.log("subtitleButtonTapped: handled external subtitle flow", type: "Info")
            return
        }

        // Embedded subtitles flow (MPV only at this point)
        let embeddedTracks = rendererGetSubtitleTracks()
        Logger.shared.log("subtitleButtonTapped: embedded flow, tracks=\(embeddedTracks.count)", type: "Info")

        let alert = UIAlertController(title: "Select Subtitle", message: nil, preferredStyle: .actionSheet)

        let disable = UIAlertAction(title: "Disable Subtitles", style: .destructive) { [weak self] _ in
            Logger.shared.log("Embedded subtitles disabled via action sheet", type: "Info")
            self?.userSelectedSubtitleTrack = true
            self?.rendererDisableSubtitles()
            self?.updateSubtitleTracksMenu()
        }
        alert.addAction(disable)

        if embeddedTracks.isEmpty {
            alert.addAction(UIAlertAction(title: "No subtitles in stream", style: .cancel, handler: nil))
        } else {
            for (id, name) in embeddedTracks {
                alert.addAction(UIAlertAction(title: name, style: .default) { [weak self] _ in
                    Logger.shared.log("Embedded subtitle selected via action sheet: id=\(id) name=\(name)", type: "Info")
                    self?.userSelectedSubtitleTrack = true
                    self?.rendererSetSubtitleTrack(id: id)
                    self?.updateSubtitleTracksMenu()
                })
            }
        }

        alert.addAction(UIAlertAction(title: "Cancel", style: .cancel, handler: nil))

        if let pop = alert.popoverPresentationController {
            pop.sourceView = subtitleButton
            pop.sourceRect = subtitleButton.bounds
        }

        present(alert, animated: true)
        showControlsTemporarily()
    }
    
    private func showSubtitleSelectionMenu() {
        let alert = UIAlertController(title: "Select Subtitle", message: nil, preferredStyle: .actionSheet)
        
        let disableAction = UIAlertAction(title: "Disable Subtitles", style: .default) { [weak self] _ in
            self?.subtitleModel.isVisible = false
            self?.userSelectedSubtitleTrack = true
            self?.rendererRefreshSubtitleOverlay()
            self?.updateSubtitleButtonAppearance()
        }
        alert.addAction(disableAction)
        
        for (index, _) in subtitleURLs.enumerated() {
            let action = UIAlertAction(title: "Subtitle \(index + 1)", style: .default) { [weak self] _ in
                self?.currentSubtitleIndex = index
                self?.subtitleModel.isVisible = true
                self?.userSelectedSubtitleTrack = true
                self?.loadCurrentSubtitle()
                self?.updateSubtitleButtonAppearance()
            }
            alert.addAction(action)
        }
        
        let cancelAction = UIAlertAction(title: "Cancel", style: .cancel, handler: nil)
        alert.addAction(cancelAction)
        
        if let popover = alert.popoverPresentationController {
            popover.sourceView = subtitleButton
            popover.sourceRect = subtitleButton.bounds
        }
        
        present(alert, animated: true, completion: nil)
    }
    
    private func animateButtonTap(_ button: UIButton) {
        UIView.animate(withDuration: 0.1, delay: 0, options: [.curveEaseOut]) {
            button.transform = CGAffineTransform(scaleX: 1.2, y: 1.2)
        } completion: { _ in
            UIView.animate(withDuration: 0.15, delay: 0, options: [.curveEaseIn]) {
                button.transform = .identity
            }
        }
    }
    
    private func updateProgressHostingController() {
        struct ProgressHostView: View {
            @ObservedObject var model: ProgressModel
            var onEditingChanged: (Bool) -> Void
            var body: some View {
                MusicProgressSlider(value: Binding(get: { model.position }, set: { model.position = $0 }), inRange: 0...max(model.duration, 1.0), activeFillColor: .white, fillColor: .white, textColor: .white.opacity(0.7), emptyColor: .white.opacity(0.3), height: 33, onEditingChanged: onEditingChanged)
            }
        }
        
        if progressHostingController != nil {
            return
        }
        
        let host = UIHostingController(rootView: AnyView(ProgressHostView(model: progressModel, onEditingChanged: { [weak self] editing in
            guard let self = self else { return }
            self.isSeeking = editing
            if !editing {
                self.rendererSeek(to: max(0, self.progressModel.position))
            }
        })))

        addChild(host)
        host.view.translatesAutoresizingMaskIntoConstraints = false
        host.view.backgroundColor = .clear
        host.view.isOpaque = false
        progressContainer.addSubview(host.view)
        NSLayoutConstraint.activate([
            host.view.topAnchor.constraint(equalTo: progressContainer.topAnchor),
            host.view.bottomAnchor.constraint(equalTo: progressContainer.bottomAnchor),
            host.view.leadingAnchor.constraint(equalTo: progressContainer.leadingAnchor),
            host.view.trailingAnchor.constraint(equalTo: progressContainer.trailingAnchor)
        ])
        host.didMove(toParent: self)
        progressHostingController = host
    }
    
    private func updatePlayPauseButton(isPaused: Bool, shouldShowControls: Bool = true) {
        DispatchQueue.main.async {
            let config = UIImage.SymbolConfiguration(pointSize: 32, weight: .semibold)
            let name = isPaused ? "play.fill" : "pause.fill"
            let img = UIImage(systemName: name, withConfiguration: config)
            self.centerPlayPauseButton.setImage(img, for: .normal)
            self.centerPlayPauseButton.isHidden = false
            
            UIView.animate(withDuration: 0.2, delay: 0, options: [.curveEaseInOut]) {
                self.centerPlayPauseButton.transform = CGAffineTransform(scaleX: 1.1, y: 1.1)
            } completion: { _ in
                UIView.animate(withDuration: 0.15) {
                    self.centerPlayPauseButton.transform = .identity
                }
            }
            
            if shouldShowControls {
                self.showControlsTemporarily()
            }
        }
    }
    
    // MARK: - Error display helpers
    private func presentErrorAlert(title: String, message: String) {
        DispatchQueue.main.async {
            let ac = UIAlertController(title: title, message: message, preferredStyle: .alert)
            ac.addAction(UIAlertAction(title: "OK", style: .default, handler: nil))
            ac.addAction(UIAlertAction(title: "View Logs", style: .default, handler: { _ in
                self.viewLogsTapped()
            }))
            self.showErrorBanner(message)
            if self.presentedViewController == nil {
                self.present(ac, animated: true, completion: nil)
            }
        }
    }
    
    private func showTransientErrorBanner(_ message: String, duration: TimeInterval = 4.0) {
        DispatchQueue.main.async {
            self.showErrorBanner(message)
            NSObject.cancelPreviousPerformRequests(withTarget: self, selector: #selector(self.hideErrorBanner), object: nil)
            self.perform(#selector(self.hideErrorBanner), with: nil, afterDelay: duration)
        }
    }
    
    @objc private func hideErrorBanner() {
        DispatchQueue.main.async {
            UIView.animate(withDuration: 0.25) {
                self.errorBanner.alpha = 0.0
            }
        }
    }
    
    @objc private func handleLoggerNotification(_ note: Notification) {
        guard let info = note.userInfo,
              let message = info["message"] as? String,
              let type = info["type"] as? String else { return }

        let lower = type.lowercased()
        if lower == "error" || lower == "warn" || message.lowercased().contains("error") || message.lowercased().contains("warn") {
            showTransientErrorBanner(message)
        }
    }
    
    private func showErrorBanner(_ message: String) {
        DispatchQueue.main.async {
            guard let label = self.errorBanner.viewWithTag(101) as? UILabel else { return }
            label.text = message
            self.view.bringSubviewToFront(self.errorBanner)
            UIView.animate(withDuration: 0.28, delay: 0, usingSpringWithDamping: 0.8, initialSpringVelocity: 0.6, options: [.curveEaseOut], animations: {
                self.errorBanner.alpha = 1.0
                self.errorBanner.transform = CGAffineTransform(translationX: 0, y: 4)
            }, completion: nil)
        }
    }
    
    @objc private func viewLogsTapped() {
        Task { @MainActor in
            let logs = await Logger.shared.getLogsAsync()
            let vc = UIViewController()
            vc.view.backgroundColor = UIColor(named: "background")
            let tv = UITextView()
            tv.translatesAutoresizingMaskIntoConstraints = false
            
#if !os(tvOS)
            tv.isEditable = false
#endif
            tv.text = logs
            tv.font = .monospacedSystemFont(ofSize: 12, weight: .regular)
            vc.view.addSubview(tv)
            NSLayoutConstraint.activate([
                tv.topAnchor.constraint(equalTo: vc.view.safeAreaLayoutGuide.topAnchor, constant: 12),
                tv.leadingAnchor.constraint(equalTo: vc.view.leadingAnchor, constant: 12),
                tv.trailingAnchor.constraint(equalTo: vc.view.trailingAnchor, constant: -12),
                tv.bottomAnchor.constraint(equalTo: vc.view.bottomAnchor, constant: -12),
            ])
            vc.navigationItem.title = "Logs"
            let nav = UINavigationController(rootViewController: vc)
            
#if !os(tvOS)
            nav.modalPresentationStyle = .pageSheet
#endif
            
            let close: UIBarButtonItem
            
#if compiler(>=6.0)
            if #available(iOS 26.0, tvOS 26.0, *) {
                close = UIBarButtonItem(title: "Close", style: .prominent, target: self, action: #selector(dismissLogs))
            } else {
                close = UIBarButtonItem(title: "Close", style: .done, target: self, action: #selector(dismissLogs))
            }
#else
            close = UIBarButtonItem(title: "Close", style: .done, target: self, action: #selector(dismissLogs))
#endif
            vc.navigationItem.rightBarButtonItem = close
            self.present(nav, animated: true, completion: nil)
        }
    }
    
    @objc private func dismissLogs() {
        dismiss(animated: true, completion: nil)
    }
    
    @objc private func containerTapped() {
        if controlsVisible {
            hideControls()
        } else {
            showControlsTemporarily()
        }
    }
    
    private func showControlsTemporarily() {
        controlsHideWorkItem?.cancel()
        controlsVisible = true
        updateBrightnessControlVisibility()

        // Ensure controls sit above the video layer/view
        videoContainer.bringSubviewToFront(controlsOverlayView)
        videoContainer.bringSubviewToFront(centerPlayPauseButton)
        videoContainer.bringSubviewToFront(progressContainer)
        videoContainer.bringSubviewToFront(closeButton)
        videoContainer.bringSubviewToFront(pipButton)
        videoContainer.bringSubviewToFront(skipBackwardButton)
        videoContainer.bringSubviewToFront(skipForwardButton)
        videoContainer.bringSubviewToFront(speedIndicatorLabel)
        videoContainer.bringSubviewToFront(subtitleButton)
        if isVLCPlayer {
            videoContainer.bringSubviewToFront(speedButton)
            videoContainer.bringSubviewToFront(audioButton)
        }
#if !os(tvOS)
        videoContainer.bringSubviewToFront(brightnessContainer)
#endif
        
        DispatchQueue.main.async {
            self.controlsOverlayView.isHidden = false
            UIView.animate(withDuration: 0.25, delay: 0, options: [.curveEaseOut]) {
                self.centerPlayPauseButton.alpha = 1.0
                self.controlsOverlayView.alpha = 1.0
                self.progressContainer.alpha = 1.0
                self.closeButton.alpha = 1.0
                self.pipButton.alpha = 1.0
                self.skipBackwardButton.alpha = 1.0
                self.skipForwardButton.alpha = 1.0
                if !self.subtitleButton.isHidden {
                    self.subtitleButton.alpha = 1.0
                }
                if self.isVLCPlayer {
                    self.speedButton.alpha = 1.0
                    if !self.audioButton.isHidden {
                        self.audioButton.alpha = 1.0
                    }
                }
#if !os(tvOS)
                if self.isBrightnessControlEnabled {
                    self.brightnessContainer.isHidden = false
                    self.brightnessContainer.alpha = 1.0
                }
#endif
            }
        }
        
        let work = DispatchWorkItem { [weak self] in
            self?.hideControls()
        }
        controlsHideWorkItem = work
        DispatchQueue.main.asyncAfter(deadline: .now() + 4.0, execute: work)
    }
    
    private func hideControls() {
        controlsHideWorkItem?.cancel()
        controlsVisible = false
        
        DispatchQueue.main.async {
            UIView.animate(withDuration: 0.25, delay: 0, options: [.curveEaseIn]) {
                self.centerPlayPauseButton.alpha = 0.0
                self.controlsOverlayView.alpha = 0.0
                self.progressContainer.alpha = 0.0
                self.closeButton.alpha = 0.0
                self.pipButton.alpha = 0.0
                self.skipBackwardButton.alpha = 0.0
                self.skipForwardButton.alpha = 0.0
                self.subtitleButton.alpha = 0.0
                if self.isVLCPlayer {
                    self.speedButton.alpha = 0.0
                    self.audioButton.alpha = 0.0
                }
#if !os(tvOS)
                self.brightnessContainer.alpha = 0.0
#endif
            } completion: { _ in
                self.controlsOverlayView.isHidden = true
            }
        }

        DispatchQueue.main.async { [weak self] in
            self?.updateBrightnessControlVisibility()
        }
    }

    func gestureRecognizer(_ gestureRecognizer: UIGestureRecognizer, shouldReceive touch: UITouch) -> Bool {
        #if !os(tvOS)
        if isBrightnessControlEnabled {
            let location = touch.location(in: brightnessContainer)
            if brightnessContainer.bounds.contains(location) {
                return false
            }
        }
        #endif
        
        // Filter double-tap gestures by screen side
        let location = touch.location(in: videoContainer)
        let isLeftSide = location.x < videoContainer.bounds.width / 2
        
        if gestureRecognizer === leftDoubleTapGesture {
            return isLeftSide
        } else if gestureRecognizer === rightDoubleTapGesture {
            return !isLeftSide
        }
        
        return true
    }
    
    @objc private func closeTapped() {
        isClosing = true
        logMPV("closeTapped; pipActive=\(pipController?.isPictureInPictureActive == true); mediaInfo=\(String(describing: mediaInfo))")
        if let mpv = mpvRenderer {
            mpv.delegate = nil
        } else if let vlc = vlcRenderer {
            vlc.delegate = nil
        }
        pipController?.delegate = nil
        if pipController?.isPictureInPictureActive == true {
            pipController?.stopPictureInPicture()
        }
        
        rendererStop()
        logMPV("renderer.stop called from closeTapped")
        
        if presentingViewController != nil {
            dismiss(animated: true, completion: nil)
        } else {
            view.window?.rootViewController?.dismiss(animated: true, completion: nil)
        }
    }
    
    @objc private func pipTapped() {
        guard vlcRenderer == nil, let pip = pipController else { return }
        if pip.isPictureInPictureActive {
            pip.stopPictureInPicture()
        } else if pip.isPictureInPicturePossible {
            pip.startPictureInPicture()
        }
    }

    private func updatePosition(_ position: Double, duration: Double) {
        // Some VLC/HLS sources report 0 duration for a while; keep the last good duration so progress persists.
        let effectiveDuration: Double
        if duration.isFinite, duration > 0 {
            effectiveDuration = duration
        } else {
            effectiveDuration = cachedDuration
        }

        DispatchQueue.main.async {
            if duration.isFinite, duration > 0 {
                self.cachedDuration = duration
            }
            self.cachedPosition = position
            if effectiveDuration > 0 {
                self.updateProgressHostingController()
            }
            self.progressModel.position = position
            self.progressModel.duration = max(effectiveDuration, 1.0)
            
            if self.pipController?.isPictureInPictureActive == true {
                self.pipController?.updatePlaybackState()
            }

            // If playback is progressing, force-hide any lingering loading spinner
            if self.loadingIndicator.alpha > 0.0 || self.loadingIndicator.isAnimating {
                self.loadingIndicator.stopAnimating()
                self.loadingIndicator.alpha = 0.0
                self.centerPlayPauseButton.isHidden = false
            }
        }
        
        guard effectiveDuration.isFinite, effectiveDuration > 0, position >= 0, let info = mediaInfo else { return }
        
        switch info {
        case .movie(let id, let title, _, _):
            ProgressManager.shared.updateMovieProgress(movieId: id, title: title, currentTime: position, totalDuration: effectiveDuration)
        case .episode(let showId, let seasonNumber, let episodeNumber, let showTitle, let showPosterURL, _):
            ProgressManager.shared.updateEpisodeProgress(showId: showId, seasonNumber: seasonNumber, episodeNumber: episodeNumber, currentTime: position, totalDuration: effectiveDuration, showTitle: showTitle, showPosterURL: showPosterURL)
        }
    }
    
    private func formatTime(_ seconds: Double) -> String {
        guard seconds.isFinite && seconds > 0 else { return "00:00" }
        let total = Int(round(seconds))
        let s = total % 60
        let m = (total / 60) % 60
        let h = total / 3600
        if h > 0 {
            return String(format: "%d:%02d:%02d", h, m, s)
        } else {
            return String(format: "%02d:%02d", m, s)
        }
    }
}

// MARK: - MPVSoftwareRendererDelegate
extension PlayerViewController: MPVSoftwareRendererDelegate {
    func renderer(_ renderer: MPVSoftwareRenderer, didUpdatePosition position: Double, duration: Double) {
        if isClosing { return }
        updatePosition(position, duration: duration)
    }
    
    func renderer(_ renderer: MPVSoftwareRenderer, didChangePause isPaused: Bool) {
        if isClosing { return }
        updatePlayPauseButton(isPaused: isPaused)
        pipController?.updatePlaybackState()
    }
    
    func renderer(_ renderer: MPVSoftwareRenderer, didChangeLoading isLoading: Bool) {
        if isClosing { return }
        DispatchQueue.main.async { [weak self] in
            guard let self else { return }
            if isLoading {
                self.centerPlayPauseButton.isHidden = true
                self.loadingIndicator.alpha = 1.0
                self.loadingIndicator.startAnimating()
            } else {
                self.loadingIndicator.stopAnimating()
                self.loadingIndicator.alpha = 0.0
                self.centerPlayPauseButton.isHidden = false
                self.updatePlayPauseButton(isPaused: self.rendererIsPausedState())
            }
        }
    }
    
    func renderer(_ renderer: MPVSoftwareRenderer, didBecomeReadyToSeek: Bool) {
        if isClosing { return }
        DispatchQueue.main.async { [weak self] in
            guard let self else { return }
            
            if let seekTime = self.pendingSeekTime {
                self.rendererSeek(to: seekTime)
                Logger.shared.log("Resumed MPV playback from \(Int(seekTime))s", type: "Progress")
                self.pendingSeekTime = nil
            }
        }
    }

    func rendererDidChangeTracks(_ renderer: MPVSoftwareRenderer) {
        if isClosing { return }
    }
    
    func renderer(_ renderer: MPVSoftwareRenderer, getSubtitleForTime time: Double) -> NSAttributedString? {
        guard subtitleModel.isVisible, !subtitleEntries.isEmpty else {
            return nil
        }
        
        if let entry = subtitleEntries.first(where: { $0.startTime <= time && time <= $0.endTime }) {
            return entry.attributedText
        }
        
        return nil
    }
    
    func renderer(_ renderer: MPVSoftwareRenderer, getSubtitleStyle: Void) -> SubtitleStyle {
        let style = SubtitleStyle(
            foregroundColor: subtitleModel.foregroundColor,
            strokeColor: subtitleModel.strokeColor,
            strokeWidth: subtitleModel.strokeWidth,
            fontSize: subtitleModel.fontSize,
            isVisible: subtitleModel.isVisible
        )
        return style
    }
    
    func renderer(_ renderer: MPVSoftwareRenderer, subtitleTrackDidChange trackId: Int) {
        if isClosing { return }
        // When an embedded subtitle track is selected, enable subtitle display
        DispatchQueue.main.async { [weak self] in
            guard let self else { return }
            self.subtitleModel.isVisible = true
            self.updateSubtitleButtonAppearance()
            // Embedded subtitles are extracted from mpv and rendered manually
        }
    }

}

// MARK: - VLCRendererDelegate
extension PlayerViewController: VLCRendererDelegate {
    func renderer(_ renderer: VLCRenderer, didUpdatePosition position: Double, duration: Double) {
        if isClosing { return }
        updatePosition(position, duration: duration)
    }
    
    func renderer(_ renderer: VLCRenderer, didChangePause isPaused: Bool) {
        if isClosing { return }
        updatePlayPauseButton(isPaused: isPaused)
        pipController?.updatePlaybackState()
    }
    
    func renderer(_ renderer: VLCRenderer, didChangeLoading isLoading: Bool) {
        if isClosing { return }
        DispatchQueue.main.async { [weak self] in
            guard let self else { return }
            if isLoading {
                self.centerPlayPauseButton.isHidden = true
                self.loadingIndicator.alpha = 1.0
                self.loadingIndicator.startAnimating()
            } else {
                self.loadingIndicator.stopAnimating()
                self.loadingIndicator.alpha = 0.0
                self.centerPlayPauseButton.isHidden = false
                self.updatePlayPauseButton(isPaused: self.rendererIsPausedState(), shouldShowControls: false)
            }
        }
    }
    
    func renderer(_ renderer: VLCRenderer, didBecomeReadyToSeek: Bool) {
        if isClosing { return }
        DispatchQueue.main.async { [weak self] in
            guard let self else { return }
            
            // Update audio and subtitle tracks now that the video is ready
            self.updateAudioTracksMenuWhenReady()
            self.updateSubtitleTracksMenuWhenReady()
            
            if let seekTime = self.pendingSeekTime {
                self.rendererSeek(to: seekTime)
                Logger.shared.log("Resumed VLC playback from \(Int(seekTime))s", type: "Progress")
                self.pendingSeekTime = nil
            }
        }
    }

    func renderer(_ renderer: VLCRenderer, didFailWithError message: String) {
        if isClosing { return }
        if attemptVlcProxyFallbackIfNeeded() {
            return
        }
        Logger.shared.log("PlayerViewController: VLC error: \(message)", type: "Error")
    }

    func rendererDidChangeTracks(_ renderer: VLCRenderer) {
        if isClosing { return }
        DispatchQueue.main.async { [weak self] in
            guard let self else { return }
            self.updateAudioTracksMenu()
            self.updateSubtitleTracksMenu()
        }
    }
    
    func renderer(_ renderer: VLCRenderer, getSubtitleForTime time: Double) -> NSAttributedString? {
        guard subtitleModel.isVisible, !subtitleEntries.isEmpty else {
            return nil
        }
        
        if let entry = subtitleEntries.first(where: { $0.startTime <= time && time <= $0.endTime }) {
            return entry.attributedText
        }
        return nil
    }
    
    func renderer(_ renderer: VLCRenderer, getSubtitleStyle: Void) -> SubtitleStyle {
        return SubtitleStyle(
            foregroundColor: subtitleModel.foregroundColor,
            strokeColor: subtitleModel.strokeColor,
            strokeWidth: subtitleModel.strokeWidth,
            fontSize: subtitleModel.fontSize,
            isVisible: subtitleModel.isVisible
        )
    }
    
    func renderer(_ renderer: VLCRenderer, subtitleTrackDidChange trackId: Int) {
        if isClosing { return }
        DispatchQueue.main.async { [weak self] in
            guard let self else { return }
            self.subtitleModel.isVisible = true
            self.updateSubtitleButtonAppearance()
            // VLC natively renders ASS subtitles
        }
    }
}

// MARK: - PiP Support
extension PlayerViewController: PiPControllerDelegate {
    func pipController(_ controller: PiPController, willStartPictureInPicture: Bool) {
        pipController?.updatePlaybackState()
    }
    func pipController(_ controller: PiPController, didStartPictureInPicture: Bool) {
        pipController?.updatePlaybackState()
    }
    func pipController(_ controller: PiPController, willStopPictureInPicture: Bool) { }
    func pipController(_ controller: PiPController, didStopPictureInPicture: Bool) { }
    func pipController(_ controller: PiPController, restoreUserInterfaceForPictureInPictureStop completionHandler: @escaping (Bool) -> Void) {
        if presentedViewController != nil {
            dismiss(animated: true) { completionHandler(true) }
        } else {
            completionHandler(true)
        }
    }
    func pipControllerPlay(_ controller: PiPController) { rendererPlay() }
    func pipControllerPause(_ controller: PiPController) { rendererPausePlayback() }
    func pipController(_ controller: PiPController, skipByInterval interval: CMTime) {
        let seconds = CMTimeGetSeconds(interval)
        let target = max(0, cachedPosition + seconds)
        rendererSeek(to: target)
        pipController?.updatePlaybackState()
    }
    func pipControllerIsPlaying(_ controller: PiPController) -> Bool { return !rendererIsPausedState() }
    func pipControllerDuration(_ controller: PiPController) -> Double { return cachedDuration }
    func pipControllerCurrentTime(_ controller: PiPController) -> Double { return cachedPosition }
    
    @objc private func appDidEnterBackground() {
        DispatchQueue.main.async { [weak self] in
            guard let self, let pip = self.pipController else { return }
            if self.vlcRenderer == nil, pip.isPictureInPicturePossible && !pip.isPictureInPictureActive {
                self.logMPV("Entering background; starting PiP")
                pip.startPictureInPicture()
            }
        }
    }
    
    @objc private func appWillEnterForeground() {
        DispatchQueue.main.async { [weak self] in
            guard let self, let pip = self.pipController else { return }
            if self.vlcRenderer == nil, pip.isPictureInPictureActive {
                self.logMPV("Returning to foreground; stopping PiP")
                pip.stopPictureInPicture()
            }
        }
    }
}
