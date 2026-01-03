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
    
    private lazy var renderer: MPVSoftwareRenderer = {
        let r = MPVSoftwareRenderer(displayLayer: displayLayer)
        r.delegate = self
        return r
    }()
    var mediaInfo: MediaInfo?
    private var isSeeking = false
    private var cachedDuration: Double = 0
    private var cachedPosition: Double = 0
    private var isClosing = false
    private var pipController: PiPController?
    private var initialURL: URL?
    private var initialPreset: PlayerPreset?
    private var initialHeaders: [String: String]?
    private var initialSubtitles: [String]?
    private var userSelectedAudioTrack = false
    
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
        setupDoubleTapSkipGestures()
    #if !os(tvOS)
        setupBrightnessControls()
    #endif
        
        NotificationCenter.default.addObserver(self, selector: #selector(handleLoggerNotification(_:)), name: NSNotification.Name("LoggerNotification"), object: nil)
        
        do {
            try renderer.start()
            logMPV("renderer.start succeeded")
        } catch {
            Logger.shared.log("Failed to start MPV renderer: \(error)", type: "Error")
            presentErrorAlert(title: "Playback Error", message: "Failed to start renderer: \(error)")
        }
        
        pipController = PiPController(sampleBufferDisplayLayer: displayLayer)
        pipController?.delegate = self
        
        showControlsTemporarily()
        
        if let url = initialURL, let preset = initialPreset {
            logMPV("loading initial url=\(url.absoluteString) preset=\(preset.id.rawValue)")
            load(url: url, preset: preset, headers: initialHeaders)
        }
        
        updateProgressHostingController()
        updateSpeedMenu()
        
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
        displayLayer.frame = videoContainer.bounds
        displayLayer.isHidden = false
        displayLayer.opacity = 1.0
        
        if let gradientLayer = controlsOverlayView.layer.sublayers?.first(where: { $0.name == "gradientLayer" }) {
            gradientLayer.frame = controlsOverlayView.bounds
        }
        
        CATransaction.commit()
    }
    
    deinit {
        isClosing = true
        renderer.delegate = nil
        logMPV("deinit; stopping renderer and restoring state")
        pipController?.delegate = nil
        if pipController?.isPictureInPictureActive == true {
            pipController?.stopPictureInPicture()
        }
        pipController?.invalidate()
        renderer.stop()
        displayLayer.removeFromSuperlayer()
        NotificationCenter.default.removeObserver(self)
    }
    
    convenience init(url: URL, preset: PlayerPreset, headers: [String: String]? = nil, subtitles: [String]? = nil) {
        self.init(nibName: nil, bundle: nil)
        self.initialURL = url
        self.initialPreset = preset
        self.initialHeaders = headers
        self.initialSubtitles = subtitles
    }
    
    func load(url: URL, preset: PlayerPreset, headers: [String: String]? = nil) {
        logMPV("load url=\(url.absoluteString) preset=\(preset.id.rawValue) headers=\(headers?.count ?? 0)")
        userSelectedAudioTrack = false
        renderer.load(url: url, with: preset, headers: headers)
        if let info = mediaInfo {
            prepareSeekToLastPosition(for: info)
        }
        
        if let subs = initialSubtitles, !subs.isEmpty {
            loadSubtitles(subs)
        }
    }
    
    private func prepareSeekToLastPosition(for mediaInfo: MediaInfo) {
        let lastPlayedTime: Double
        
        switch mediaInfo {
        case .movie(let id, let title):
            lastPlayedTime = ProgressManager.shared.getMovieCurrentTime(movieId: id, title: title)
            
        case .episode(let showId, let seasonNumber, let episodeNumber):
            lastPlayedTime = ProgressManager.shared.getEpisodeCurrentTime(showId: showId, seasonNumber: seasonNumber, episodeNumber: episodeNumber)
        }
        
        if lastPlayedTime != 0 {
            let progress: Double
            switch mediaInfo {
            case .movie(let id, let title):
                progress = ProgressManager.shared.getMovieProgress(movieId: id, title: title)
            case .episode(let showId, let seasonNumber, let episodeNumber):
                progress = ProgressManager.shared.getEpisodeProgress(showId: showId, seasonNumber: seasonNumber, episodeNumber: episodeNumber)
            }
            
            if progress < 0.95 {
                pendingSeekTime = lastPlayedTime
            }
        }
    }
    
    private func setupLayout() {
        view.addSubview(videoContainer)
        
        displayLayer.frame = videoContainer.bounds
        displayLayer.videoGravity = .resizeAspect
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
        videoContainer.addSubview(speedButton)
        videoContainer.addSubview(audioButton)
    #if !os(tvOS)
        videoContainer.addSubview(brightnessContainer)
        brightnessContainer.contentView.addSubview(brightnessSlider)
        brightnessContainer.contentView.addSubview(brightnessIcon)
    #endif
        
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
            subtitleButton.heightAnchor.constraint(equalToConstant: 32),
            
            speedButton.trailingAnchor.constraint(equalTo: subtitleButton.leadingAnchor, constant: -8),
            speedButton.centerYAnchor.constraint(equalTo: subtitleButton.centerYAnchor),
            speedButton.widthAnchor.constraint(equalToConstant: 32),
            speedButton.heightAnchor.constraint(equalToConstant: 32),
            
            audioButton.trailingAnchor.constraint(equalTo: speedButton.leadingAnchor, constant: -8),
            audioButton.centerYAnchor.constraint(equalTo: subtitleButton.centerYAnchor),
            audioButton.widthAnchor.constraint(equalToConstant: 32),
            audioButton.heightAnchor.constraint(equalToConstant: 32)
        ])
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
    }
    
    private func setupActions() {
        centerPlayPauseButton.addTarget(self, action: #selector(centerPlayPauseTapped), for: .touchUpInside)
        closeButton.addTarget(self, action: #selector(closeTapped), for: .touchUpInside)
        pipButton.addTarget(self, action: #selector(pipTapped), for: .touchUpInside)
        skipBackwardButton.addTarget(self, action: #selector(skipBackwardTapped), for: .touchUpInside)
        skipForwardButton.addTarget(self, action: #selector(skipForwardTapped), for: .touchUpInside)
        subtitleButton.addTarget(self, action: #selector(subtitleButtonTapped), for: .touchUpInside)
        let tap = UITapGestureRecognizer(target: self, action: #selector(containerTapped))
        tap.delegate = self
        tap.cancelsTouchesInView = false
        videoContainer.addGestureRecognizer(tap)
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
        renderer.seek(by: -10)
        animateButtonTap(skipBackwardButton)
        showControlsTemporarily()
    }

    @objc private func rightSideDoubleTapped(_ gesture: UITapGestureRecognizer) {
        let location = gesture.location(in: videoContainer)
        let isRightSide = location.x >= videoContainer.bounds.width / 2
        guard isRightSide else { return }
        renderer.seek(by: 10)
        animateButtonTap(skipForwardButton)
        showControlsTemporarily()
    }

    @objc private func twoFingerTapped(_ gesture: UITapGestureRecognizer) {
        centerPlayPauseTapped()
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
        originalSpeed = renderer.getSpeed()
        let holdSpeed = UserDefaults.standard.float(forKey: "holdSpeedPlayer")
        let targetSpeed = holdSpeed > 0 ? Double(holdSpeed) : 2.0
        renderer.setSpeed(targetSpeed)
        
        DispatchQueue.main.async { [weak self] in
            guard let self = self else { return }
            self.speedIndicatorLabel.text = String(format: "%.1fx", targetSpeed)
            UIView.animate(withDuration: 0.2) {
                self.speedIndicatorLabel.alpha = 1.0
            }
        }
    }
    
    private func endHoldSpeed() {
        renderer.setSpeed(originalSpeed)
        
        DispatchQueue.main.async { [weak self] in
            UIView.animate(withDuration: 0.2) {
                self?.speedIndicatorLabel.alpha = 0.0
            }
        }
    }
    
    @objc private func playPauseTapped() {
        if renderer.isPausedState {
            renderer.play()
            updatePlayPauseButton(isPaused: false)
        } else {
            renderer.pausePlayback()
            updatePlayPauseButton(isPaused: true)
        }
    }
    
    @objc private func centerPlayPauseTapped() {
        playPauseTapped()
    }
    
    @objc private func skipBackwardTapped() {
        renderer.seek(by: -10)
        animateButtonTap(skipBackwardButton)
        showControlsTemporarily()
    }
    
    @objc private func skipForwardTapped() {
        renderer.seek(by: 10)
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
        let currentSpeed = renderer.getSpeed()
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
                self?.renderer.setSpeed(speed)
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
    
    private func updateAudioTracksMenu() {
        let detailedTracks = renderer.getAudioTracksDetailed()
        let tracks = detailedTracks.map { ($0.0, $0.1) }
        var trackActions: [UIAction] = []
        
        if tracks.isEmpty {
            let loadingAction = UIAction(title: "Loading audio tracks...", attributes: [.disabled], state: .off) { _ in }
            let audioMenu = UIMenu(title: "Audio Tracks", image: UIImage(systemName: "speaker.wave.2"), children: [loadingAction])
            audioButton.menu = audioMenu
            return
        }

        trackActions = tracks.map { (id, name) in
            UIAction(
                title: name,
                state: .off
            ) { [weak self] _ in
                self?.userSelectedAudioTrack = true
                self?.renderer.setAudioTrack(id: id)
                self?.updateAudioTracksMenu()
            }
        }

        // Auto-select preferred anime audio language when applicable
        if isAnimeContent() && !userSelectedAudioTrack {
            let preferredLang = Settings.shared.preferredAnimeAudioLanguage.lowercased()
            let preferredLangName = languageName(for: preferredLang)

            if let matching = detailedTracks.first(where: {
                let langCode = $0.2.lowercased()
                let title = $0.1.lowercased()
                if !preferredLang.isEmpty && langCode.contains(preferredLang) { return true }
                if !preferredLangName.isEmpty && langCode.contains(preferredLangName.lowercased()) { return true }
                if !preferredLang.isEmpty && title.contains(preferredLang) { return true }
                if !preferredLangName.isEmpty && title.contains(preferredLangName.lowercased()) { return true }
                return false
            }) {
                userSelectedAudioTrack = true
                renderer.setAudioTrack(id: matching.0)
            }
        }
        
        let audioMenu = UIMenu(title: "Audio Tracks", image: UIImage(systemName: "speaker.wave.2"), children: trackActions)
        audioButton.menu = audioMenu
    }

    private func isAnimeContent() -> Bool {
        guard let info = mediaInfo else { return false }
        switch info {
        case .movie:
            return false
        case .episode(let showId, _, _):
            return trackerManager.cachedAniListId(for: showId) != nil
        }
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
    
    private func updateSubtitleTracksMenu() {
        // If we already have external subtitle URLs, keep the external menu intact
        guard subtitleURLs.isEmpty else { return }

        let tracks = renderer.getSubtitleTracks()
        
        // Show subtitle button if we have embedded tracks
        if !tracks.isEmpty {
            subtitleButton.isHidden = false
            
            // Apply default subtitle settings if enabled
            let settings = Settings.shared
            if settings.enableSubtitlesByDefault {
                // Try to find matching language track
                let preferredLang = settings.defaultSubtitleLanguage
                if let matchingTrack = tracks.first(where: { $0.1.lowercased().contains(preferredLang.lowercased()) }) {
                    renderer.setSubtitleTrack(id: matchingTrack.0)
                }
            }
        }
        
        var trackActions: [UIAction] = []

        let disableAction = UIAction(
            title: "Disable Subtitles",
            image: UIImage(systemName: "xmark"),
            state: .off
        ) { [weak self] _ in
            self?.renderer.disableSubtitles()
            self?.updateSubtitleTracksMenu()
        }
        trackActions.append(disableAction)
        
        if tracks.isEmpty {
            // Don't disable - just inform the user
            let noTracksAction = UIAction(title: "No subtitles in stream", state: .off) { _ in }
            trackActions.append(noTracksAction)
        } else {
            // Use map to properly capture values in closures (same pattern as audio tracks)
            let subtitleActions = tracks.map { (id, name) in
                UIAction(
                    title: name,
                    image: UIImage(systemName: "captions.bubble"),
                    state: .off
                ) { [weak self] _ in
                    self?.renderer.setSubtitleTrack(id: id)
                    self?.updateSubtitleTracksMenu()
                }
            }
            trackActions.append(contentsOf: subtitleActions)
        }
        
        let subtitleMenu = UIMenu(title: "Subtitles", image: UIImage(systemName: "captions.bubble"), children: trackActions)
        subtitleButton.menu = subtitleMenu
    }
    private func loadSubtitles(_ urls: [String]) {
        subtitleURLs = urls
        
        if !urls.isEmpty {
            subtitleButton.isHidden = false
            currentSubtitleIndex = 0
            subtitleModel.isVisible = true
            loadCurrentSubtitle()
            updateSubtitleButtonAppearance()
            updateSubtitleMenu()
        } else {
            Logger.shared.log("No subtitle URLs to load", type: "Info")
        }
    }
    
    private func loadCurrentSubtitle() {
        guard currentSubtitleIndex < subtitleURLs.count else { return }
        let urlString = subtitleURLs[currentSubtitleIndex]
        
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
        DispatchQueue.main.async { [weak self] in
            guard let self = self else { return }
            self.subtitleEntries = SubtitleLoader.parseSubtitles(from: content, fontSize: self.subtitleModel.fontSize, foregroundColor: self.subtitleModel.foregroundColor)
            Logger.shared.log("Loaded \(self.subtitleEntries.count) subtitle entries", type: "Info")
            self.renderer.refreshSubtitleOverlay()
        }
    }
    
    @objc private func subtitleButtonTapped() {
        // External subtitles present
        if !subtitleURLs.isEmpty {
            if subtitleURLs.count == 1 {
                subtitleModel.isVisible.toggle()
                renderer.refreshSubtitleOverlay()
                updateSubtitleButtonAppearance()
            } else {
                showSubtitleSelectionMenu()
            }
            showControlsTemporarily()
            Logger.shared.log("subtitleButtonTapped: handled external subtitle flow", type: "Info")
            return
        }

        // Embedded subtitles flow
        let embeddedTracks = renderer.getSubtitleTracks()
            Logger.shared.log("subtitleButtonTapped: embedded flow, tracks=\(embeddedTracks.count)", type: "Info")
        guard !embeddedTracks.isEmpty else {
            Logger.shared.log("subtitleButtonTapped: no embedded tracks available", type: "Info")
            showControlsTemporarily()
            return
        }

        Logger.shared.log("subtitleButtonTapped: presenting action sheet for embedded tracks", type: "Info")

        let alert = UIAlertController(title: "Select Subtitle", message: nil, preferredStyle: .actionSheet)

        let disable = UIAlertAction(title: "Disable Subtitles", style: .destructive) { [weak self] _ in
            Logger.shared.log("Embedded subtitles disabled via action sheet", type: "Info")
            self?.renderer.disableSubtitles()
            self?.updateSubtitleTracksMenu()
        }
        alert.addAction(disable)

        for (id, name) in embeddedTracks {
            alert.addAction(UIAlertAction(title: name, style: .default) { [weak self] _ in
                Logger.shared.log("Embedded subtitle selected via action sheet: id=\(id) name=\(name)", type: "Info")
                self?.renderer.setSubtitleTrack(id: id)
                self?.updateSubtitleTracksMenu()
            })
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
            self?.renderer.refreshSubtitleOverlay()
            self?.updateSubtitleButtonAppearance()
        }
        alert.addAction(disableAction)
        
        for (index, _) in subtitleURLs.enumerated() {
            let action = UIAlertAction(title: "Subtitle \(index + 1)", style: .default) { [weak self] _ in
                self?.currentSubtitleIndex = index
                self?.subtitleModel.isVisible = true
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
                self.renderer.seek(to: max(0, self.progressModel.position))
            }
        })))
        
        progressHostingController = host
        addChild(host)
        host.view.translatesAutoresizingMaskIntoConstraints = false
        host.view.backgroundColor = .clear
        host.view.isOpaque = false
        progressContainer.addSubview(host.view)
        NSLayoutConstraint.activate([
            host.view.topAnchor.constraint(equalTo: progressContainer.topAnchor),
            host.view.bottomAnchor.constraint(equalTo: progressContainer.bottomAnchor),
            host.view.leadingAnchor.constraint(equalTo: progressContainer.leadingAnchor),
            host.view.trailingAnchor.constraint(equalTo: progressContainer.trailingAnchor),
        ])
        host.didMove(toParent: self)
    }
    
    private func updatePlayPauseButton(isPaused: Bool) {
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
            
            self.showControlsTemporarily()
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
        
        DispatchQueue.main.async {
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
                self.speedButton.alpha = 1.0
                if !self.audioButton.isHidden {
                    self.audioButton.alpha = 1.0
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
                self.speedButton.alpha = 0.0
                self.audioButton.alpha = 0.0
#if !os(tvOS)
                self.brightnessContainer.alpha = 0.0
#endif
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
        renderer.delegate = nil
        pipController?.delegate = nil
        if pipController?.isPictureInPictureActive == true {
            pipController?.stopPictureInPicture()
        }
        
        renderer.stop()
        logMPV("renderer.stop called from closeTapped")
        
        if presentingViewController != nil {
            dismiss(animated: true, completion: nil)
        } else {
            view.window?.rootViewController?.dismiss(animated: true, completion: nil)
        }
    }
    
    @objc private func pipTapped() {
        guard let pip = pipController else { return }
        if pip.isPictureInPictureActive {
            pip.stopPictureInPicture()
        } else if pip.isPictureInPicturePossible {
            pip.startPictureInPicture()
        }
    }
    
    private func updatePosition(_ position: Double, duration: Double) {
        DispatchQueue.main.async {
            self.cachedDuration = duration
            self.cachedPosition = position
            if duration > 0 {
                self.updateProgressHostingController()
            }
            self.progressModel.position = position
            self.progressModel.duration = max(duration, 1.0)
            
            if self.pipController?.isPictureInPictureActive == true {
                self.pipController?.updatePlaybackState()
            }
        }
        
        guard duration.isFinite, duration > 0, position >= 0, let info = mediaInfo else { return }
        
        switch info {
        case .movie(let id, let title):
            ProgressManager.shared.updateMovieProgress(movieId: id, title: title, currentTime: position, totalDuration: duration)
        case .episode(let showId, let seasonNumber, let episodeNumber):
            ProgressManager.shared.updateEpisodeProgress(showId: showId, seasonNumber: seasonNumber, episodeNumber: episodeNumber, currentTime: position, totalDuration: duration)
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
                self.updatePlayPauseButton(isPaused: self.renderer.isPausedState)
            }
        }
    }
    
    func renderer(_ renderer: MPVSoftwareRenderer, didBecomeReadyToSeek: Bool) {
        if isClosing { return }
        DispatchQueue.main.async { [weak self] in
            guard let self else { return }
            
            // Update audio and subtitle tracks now that the video is ready
            self.updateAudioTracksMenu()
            self.updateSubtitleTracksMenu()
            
            if let seekTime = self.pendingSeekTime {
                self.renderer.seek(to: seekTime)
                Logger.shared.log("Resumed MPV playback from \(Int(seekTime))s", type: "Progress")
                self.pendingSeekTime = nil
            }
        }
    }

    func rendererDidChangeTracks(_ renderer: MPVSoftwareRenderer) {
        if isClosing { return }
        DispatchQueue.main.async { [weak self] in
            guard let self else { return }
            self.updateAudioTracksMenu()
        }
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
        let settings = Settings.shared
        let style = SubtitleStyle(
            foregroundColor: subtitleModel.foregroundColor,
            strokeColor: subtitleModel.strokeColor,
            strokeWidth: settings.subtitleSize.strokeWidth,
            fontSize: settings.subtitleSize.fontSize,
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
    func pipControllerPlay(_ controller: PiPController) { renderer.play() }
    func pipControllerPause(_ controller: PiPController) { renderer.pausePlayback() }
    func pipController(_ controller: PiPController, skipByInterval interval: CMTime) {
        let seconds = CMTimeGetSeconds(interval)
        let target = max(0, cachedPosition + seconds)
        renderer.seek(to: target)
        pipController?.updatePlaybackState()
    }
    func pipControllerIsPlaying(_ controller: PiPController) -> Bool { return !renderer.isPausedState }
    func pipControllerDuration(_ controller: PiPController) -> Double { return cachedDuration }
    func pipControllerCurrentTime(_ controller: PiPController) -> Double { return cachedPosition }
    
    @objc private func appDidEnterBackground() {
        DispatchQueue.main.async { [weak self] in
            guard let self, let pip = self.pipController else { return }
            if pip.isPictureInPicturePossible && !pip.isPictureInPictureActive {
                self.logMPV("Entering background; starting PiP")
                pip.startPictureInPicture()
            }
        }
    }
    
    @objc private func appWillEnterForeground() {
        DispatchQueue.main.async { [weak self] in
            guard let self, let pip = self.pipController else { return }
            if pip.isPictureInPictureActive {
                self.logMPV("Returning to foreground; stopping PiP")
                pip.stopPictureInPicture()
            }
        }
    }
}
