//
//  VLCPlayer.swift
//  Luna
//
//  VLC Player SwiftUI wrapper using PlayerViewController
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
    
    func makeUIViewController(context: Context) -> PlayerViewController {
        let controller = PlayerViewController()
        controller.mediaInfo = mediaInfo
        return controller
    }
    
    func updateUIViewController(_ uiViewController: PlayerViewController, context: Context) {
        // Load media if needed
        if let preset = preset {
            uiViewController.loadMedia(url: url, preset: preset, headers: headers)
        }
    }
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

#endif
