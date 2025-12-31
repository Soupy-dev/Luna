//
//  ContinueWatchingViewModel.swift
//  Luna
//
//  Created by GitHub Copilot on request
//

import Foundation
import Combine
import UIKit
import AVFoundation
import AVKit

enum ContinueMediaType {
    case movie
    case episode
}

struct ContinueWatchingEntry: Identifiable {
    let id: String
    let title: String
    var imageURL: String?
    let currentTime: Double
    let totalDuration: Double
    let lastUpdated: Date
    let type: ContinueMediaType
    let lastServiceId: UUID?
    let lastHref: String?

    // episode-specific
    let showId: Int?
    let seasonNumber: Int?
    let episodeNumber: Int?
}

final class ContinueWatchingViewModel: ObservableObject {
    @Published var entries: [ContinueWatchingEntry] = []
    private var cancellables = Set<AnyCancellable>()

    // Progress filter thresholds
    private let minProgress: Double = 0.05
    private let maxProgress: Double = 0.85
    private let maxEntries: Int = 6

    init() {
        let pm = ProgressManager.shared

        pm.$movieProgressList
            .combineLatest(pm.$episodeProgressList)
            .receive(on: DispatchQueue.main)
            .sink { [weak self] movieList, episodeList in
                guard let self = self else { return }

                let movieEntries = movieList
                    .filter { $0.progress > self.minProgress && $0.progress < self.maxProgress }
                    .map { m -> ContinueWatchingEntry in
                        ContinueWatchingEntry(
                            id: "movie_\(m.id)",
                            title: m.title,
                            imageURL: nil,
                            currentTime: m.currentTime,
                            totalDuration: m.totalDuration,
                            lastUpdated: m.lastUpdated,
                            type: .movie,
                            lastServiceId: m.lastServiceId,
                            lastHref: m.lastHref,
                            showId: nil,
                            seasonNumber: nil,
                            episodeNumber: nil
                        )
                    }

                let episodeEntries = episodeList
                    .filter { $0.progress > self.minProgress && $0.progress < self.maxProgress }
                    .map { e -> ContinueWatchingEntry in
                        ContinueWatchingEntry(
                            id: e.id,
                            title: "S\(e.seasonNumber)E\(e.episodeNumber)",
                            imageURL: nil,
                            currentTime: e.currentTime,
                            totalDuration: e.totalDuration,
                            lastUpdated: e.lastUpdated,
                            type: .episode,
                            lastServiceId: e.lastServiceId,
                            lastHref: e.lastHref,
                            showId: e.showId,
                            seasonNumber: e.seasonNumber,
                            episodeNumber: e.episodeNumber
                        )
                    }

                var combined = (movieEntries + episodeEntries)
                    .sorted { $0.lastUpdated > $1.lastUpdated }
                if combined.count > self.maxEntries {
                    combined = Array(combined.prefix(self.maxEntries))
                }
                self.entries = combined
                // Kick off async poster fetch for entries that don't have an image
                Task { [weak self] in
                    guard let self = self else { return }
                    for entry in combined where entry.imageURL == nil {
                        switch entry.type {
                        case .movie:
                            if let idStr = entry.id.split(separator: "_").last, let movieId = Int(idStr) {
                                do {
                                    let detail = try await TMDBService.shared.getMovieDetails(id: movieId)
                                    if let poster = detail.fullPosterURL {
                                        await MainActor.run {
                                            if let idx = self.entries.firstIndex(where: { $0.id == entry.id }) {
                                                self.entries[idx].imageURL = poster
                                            }
                                        }
                                    }
                                } catch {
                                    // ignore failures; poster optional
                                }
                            }
                        case .episode:
                            if let showId = entry.showId {
                                do {
                                    let detail = try await TMDBService.shared.getTVShowDetails(id: showId)
                                    if let poster = detail.fullPosterURL {
                                        await MainActor.run {
                                            if let idx = self.entries.firstIndex(where: { $0.id == entry.id }) {
                                                self.entries[idx].imageURL = poster
                                            }
                                        }
                                    }
                                } catch {
                                    // ignore failures; poster optional
                                }
                            }
                        }
                    }
                }
            }
            .store(in: &cancellables)
    }

    func resume(_ entry: ContinueWatchingEntry) {
        // Try to resume using the last recorded service/href when available
        if let serviceId = entry.lastServiceId, let href = entry.lastHref {
            // Attempt to find the service
            let service = ServiceStore.shared.getServices().first(where: { $0.id == serviceId })
            if let service = service {
                let jsController = JSController()
                jsController.loadScript(service.jsScript)
                jsController.fetchStreamUrlJS(episodeUrl: href, module: service) { [weak self] streamResult in
                    DispatchQueue.main.async {
                        let (streams, subtitles, sources) = streamResult
                        // pick the first available stream
                        let streamURLString: String?
                        if let source = sources?.first, let url = source["url"] as? String {
                            streamURLString = url
                        } else if let stream = streams?.first {
                            streamURLString = stream
                        } else {
                            streamURLString = nil
                        }
                        
                        if let streamURLString = streamURLString {
                            guard let streamURL = URL(string: streamURLString) else {
                                Logger.shared.log("Invalid stream URL: \(streamURLString)", type: "Error")
                                return
                            }
                            // try external player first
                            let externalRaw = UserDefaults.standard.string(forKey: "externalPlayer") ?? ExternalPlayer.none.rawValue
                            let external = ExternalPlayer(rawValue: externalRaw) ?? .none
                            if let scheme = external.schemeURL(for: streamURLString), UIApplication.shared.canOpenURL(scheme) {
                                UIApplication.shared.open(scheme, options: [:], completionHandler: nil)
                                return
                            }

                            // In-app player
                            let inAppRaw = UserDefaults.standard.string(forKey: "inAppPlayer") ?? InAppPlayer.normal.rawValue
                            let inAppPlayer = (inAppRaw == "mpv") ? "mpv" : "Normal"

                            if inAppPlayer == "mpv" {
                                let preset = PlayerPreset.presets.first
                                let pvc = PlayerViewController(url: streamURL, preset: preset ?? PlayerPreset(id: .sdrRec709, title: "Default", summary: "", stream: nil, commands: []), headers: nil, subtitles: subtitles)
                                if entry.type == .movie {
                                    if let idStr = entry.id.split(separator: "_").last, let movieId = Int(idStr) {
                                        pvc.mediaInfo = .movie(id: movieId, title: entry.title)
                                    }
                                } else if let showId = entry.showId, let season = entry.seasonNumber, let ep = entry.episodeNumber {
                                    pvc.mediaInfo = .episode(showId: showId, seasonNumber: season, episodeNumber: ep)
                                }
                                pvc.modalPresentationStyle = .fullScreen
                                if let windowScene = UIApplication.shared.connectedScenes.first as? UIWindowScene,
                                   let rootVC = windowScene.windows.first?.rootViewController {
                                    rootVC.topmostViewController().present(pvc, animated: true, completion: nil)
                                }
                                return
                            } else {
                                let playerVC = NormalPlayer()
                                let asset = AVURLAsset(url: streamURL, options: nil)
                                let item = AVPlayerItem(asset: asset)
                                playerVC.player = AVPlayer(playerItem: item)
                                if entry.type == .movie {
                                    if let idStr = entry.id.split(separator: "_").last, let movieId = Int(idStr) {
                                        playerVC.mediaInfo = .movie(id: movieId, title: entry.title)
                                    }
                                } else if let showId = entry.showId, let season = entry.seasonNumber, let ep = entry.episodeNumber {
                                    playerVC.mediaInfo = .episode(showId: showId, seasonNumber: season, episodeNumber: ep)
                                }
                                playerVC.modalPresentationStyle = .fullScreen
                                if let windowScene = UIApplication.shared.connectedScenes.first as? UIWindowScene,
                                   let rootVC = windowScene.windows.first?.rootViewController {
                                    rootVC.topmostViewController().present(playerVC, animated: true) {
                                        playerVC.player?.play()
                                    }
                                } else {
                                    playerVC.player?.play()
                                }
                                return
                            }
                        } else {
                            // No streams resolved -> fallback to details view
                            var userInfo: [String: Any] = [:]
                            switch entry.type {
                            case .movie:
                                if let idStr = entry.id.split(separator: "_").last, let movieId = Int(idStr) {
                                    userInfo["tmdbId"] = movieId
                                    userInfo["isMovie"] = true
                                    userInfo["title"] = entry.title
                                }
                            case .episode:
                                if let showId = entry.showId {
                                    userInfo["tmdbId"] = showId
                                    userInfo["isMovie"] = false
                                    userInfo["title"] = entry.title
                                    userInfo["seasonNumber"] = entry.seasonNumber
                                    userInfo["episodeNumber"] = entry.episodeNumber
                                }
                            }
                            NotificationCenter.default.post(name: Notification.Name("ContinueWatchingOpenDetail"), object: nil, userInfo: userInfo)
                            return
                        }
                    }
                }
                return
            }
        }

        // Fallback: open detail or update progress only (no known service)
        switch entry.type {
        case .movie:
            if let idStr = entry.id.split(separator: "_").last, let movieId = Int(idStr) {
                ProgressManager.shared.updateMovieProgress(movieId: movieId, title: entry.title, currentTime: entry.currentTime, totalDuration: entry.totalDuration)
                    // Open MediaDetailView for this movie
                    DispatchQueue.main.async {
                        NotificationCenter.default.post(name: Notification.Name("ContinueWatchingOpenDetail"), object: nil, userInfo: ["tmdbId": movieId, "isMovie": true, "title": entry.title, "autoPlay": true])
                    }
            }
        case .episode:
            if let showId = entry.showId, let season = entry.seasonNumber, let ep = entry.episodeNumber {
                ProgressManager.shared.updateEpisodeProgress(showId: showId, seasonNumber: season, episodeNumber: ep, currentTime: entry.currentTime, totalDuration: entry.totalDuration)
                    // Open MediaDetailView for this show
                    DispatchQueue.main.async {
                        NotificationCenter.default.post(name: Notification.Name("ContinueWatchingOpenDetail"), object: nil, userInfo: ["tmdbId": showId, "isMovie": false, "title": entry.title, "seasonNumber": season, "episodeNumber": ep, "autoPlay": true])
                    }
            }
        }
    }

    func playFromStart(_ entry: ContinueWatchingEntry) {
        // Reset progress to start so players won't seek
        switch entry.type {
        case .movie:
            if let idStr = entry.id.split(separator: "_").last, let movieId = Int(idStr) {
                ProgressManager.shared.updateMovieProgress(movieId: movieId, title: entry.title, currentTime: 0, totalDuration: entry.totalDuration)
            }
        case .episode:
            if let showId = entry.showId, let season = entry.seasonNumber, let ep = entry.episodeNumber {
                ProgressManager.shared.updateEpisodeProgress(showId: showId, seasonNumber: season, episodeNumber: ep, currentTime: 0, totalDuration: entry.totalDuration)
            }
        }

        // Reuse resume flow, which will now see progress at zero
        resume(entry)
    }
}
