//
//  VideoRenderer.swift
//  Luna
//
//  Common protocol for both MPV and VLC renderers to provide unified interface
//

import UIKit
import AVFoundation

protocol VideoRenderer: AnyObject {
    associatedtype DelegateType
    
    var delegate: DelegateType? { get set }
    var isPausedState: Bool { get }
    
    func start() throws
    func stop()
    func load(url: URL, with preset: PlayerPreset, headers: [String: String]?)
    func reloadCurrentItem()
    func applyPreset(_ preset: PlayerPreset)
    
    // Playback control
    func play()
    func pausePlayback()
    func togglePause()
    func seek(to seconds: Double)
    func seek(by seconds: Double)
    func setSpeed(_ speed: Double)
    func getSpeed() -> Double
    
    // Audio tracks
    func getAudioTracks() -> [(Int, String)]
    func getAudioTracksDetailed() -> [(Int, String, String)]
    func setAudioTrack(_ id: Int)
    
    // Subtitle tracks
    func getSubtitleTracks() -> [(Int, String)]
    func setSubtitleTrack(_ id: Int)
    func disableSubtitles()
    func loadExternalSubtitles(urls: [String])
    func clearSubtitleCache()
}
