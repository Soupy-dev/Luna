//
//  ContinueWatchingViewModel.swift
//  Luna
//
//  Created by Soupy-dev
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
    let title: String               // short label (for episodes this is S/E)
    var showTitle: String?          // resolved canonical title for search/detail
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
                            showTitle: m.title,
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
                            showTitle: nil,
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

                // Deduplicate: for episodes, keep only the most recent per show
                var seenShowIds = Set<Int>()
                let deduped = (movieEntries + episodeEntries)
                    .sorted { $0.lastUpdated > $1.lastUpdated }
                    .filter { entry in
                        if entry.type == .episode, let showId = entry.showId {
                            if seenShowIds.contains(showId) {
                                return false
                            }
                            seenShowIds.insert(showId)
                        }
                        return true
                    }

                var combined = deduped
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
                                    await MainActor.run {
                                        if let idx = self.entries.firstIndex(where: { $0.id == entry.id }) {
                                            self.entries[idx].showTitle = detail.title
                                            if let poster = detail.fullPosterURL {
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
                                    await MainActor.run {
                                        if let idx = self.entries.firstIndex(where: { $0.id == entry.id }) {
                                            self.entries[idx].showTitle = detail.name
                                            if let poster = detail.fullPosterURL {
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
        Task { await resumeAsync(entry) }
    }

    private func resumeAsync(_ entry: ContinueWatchingEntry) async {
        Logger.shared.log("CW Resume start: type=\(entry.type) showId=\(entry.showId ?? -1) S\(entry.seasonNumber ?? -1)E\(entry.episodeNumber ?? -1) lastService=\(String(describing: entry.lastServiceId))", type: "ContinueWatching")
        let canonicalTitle = await resolveCanonicalTitle(for: entry)
        Logger.shared.log("CW Resume resolved title=\(canonicalTitle)", type: "ContinueWatching")

        func postModulesSearch() {
            var userInfo: [String: Any] = ["title": canonicalTitle]
            switch entry.type {
            case .movie:
                if let idStr = entry.id.split(separator: "_").last, let movieId = Int(idStr) {
                    userInfo["tmdbId"] = movieId
                    userInfo["isMovie"] = true
                }
            case .episode:
                if let showId = entry.showId {
                    userInfo["tmdbId"] = showId
                    userInfo["isMovie"] = false
                    userInfo["seasonNumber"] = entry.seasonNumber
                    userInfo["episodeNumber"] = entry.episodeNumber
                    Logger.shared.log("CW postModulesSearch: title='\(canonicalTitle)', showId=\(showId), S\(entry.seasonNumber ?? -1)E\(entry.episodeNumber ?? -1)", type: "ContinueWatching")
                }
            }
            NotificationCenter.default.post(name: Notification.Name("ContinueWatchingOpenModules"), object: nil, userInfo: userInfo)
        }

        func recordProgressSnapshot() {
            switch entry.type {
            case .movie:
                if let idStr = entry.id.split(separator: "_").last, let movieId = Int(idStr) {
                    ProgressManager.shared.updateMovieProgress(movieId: movieId, title: canonicalTitle, currentTime: entry.currentTime, totalDuration: entry.totalDuration)
                }
            case .episode:
                if let showId = entry.showId, let season = entry.seasonNumber, let ep = entry.episodeNumber {
                    ProgressManager.shared.updateEpisodeProgress(showId: showId, seasonNumber: season, episodeNumber: ep, currentTime: entry.currentTime, totalDuration: entry.totalDuration)
                }
            }
        }

        // Try to resume using the last recorded service/href when available
        if let serviceId = entry.lastServiceId, let href = entry.lastHref {
            let service = ServiceStore.shared.getServices().first(where: { $0.id == serviceId })
            if let service = service {
                Logger.shared.log("CW Resume using saved service \(service.metadata.sourceName) href=\(href)", type: "ContinueWatching")
                let jsController = JSController()
                jsController.loadScript(service.jsScript)
                var didResolve = false
                let timeoutTask = Task { @MainActor in
                    try? await Task.sleep(nanoseconds: 1_000_000_000)
                    if !didResolve {
                        Logger.shared.log("CW Resume timeout; fallback to modules search", type: "ContinueWatching")
                        recordProgressSnapshot()
                        postModulesSearch()
                    }
                }
                jsController.fetchStreamUrlJS(episodeUrl: href, module: service) { [weak self] streamResult in
                    DispatchQueue.main.async {
                        didResolve = true
                        timeoutTask.cancel()
                        Logger.shared.log("CW Resume stream result streams=\(streamResult.0?.count ?? 0) sources=\(streamResult.2?.count ?? 0)", type: "ContinueWatching")
                        let (streams, subtitles, sources) = streamResult
                        let streamURLString: String?
                        var headerFields: [String: String] = [:]
                        if let source = sources?.first {
                            if let url = source["url"] as? String {
                                streamURLString = url
                            } else {
                                streamURLString = nil
                            }

                            if let headers = source["headers"] as? [String: String] {
                                headerFields = headers
                            } else if let headersAny = source["headers"] as? [String: Any] {
                                headerFields = headersAny.compactMapValues { value in
                                    if let str = value as? String { return str }
                                    return "\(value)"
                                }
                            }
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
                            var finalHeaders: [String: String]? = nil
                            if let baseURL = URL(string: service.metadata.baseUrl)?.absoluteString {
                                var headers = [
                                    "Origin": baseURL,
                                    "Referer": baseURL,
                                    "User-Agent": URLSession.randomUserAgent
                                ]
                                for (k, v) in headerFields { headers[k] = v }
                                finalHeaders = headers
                            } else if !headerFields.isEmpty {
                                finalHeaders = headerFields
                            }
                            let externalRaw = UserDefaults.standard.string(forKey: "externalPlayer") ?? ExternalPlayer.none.rawValue
                            let external = ExternalPlayer(rawValue: externalRaw) ?? .none
                            if let scheme = external.schemeURL(for: streamURLString), UIApplication.shared.canOpenURL(scheme) {
                                UIApplication.shared.open(scheme, options: [:], completionHandler: nil)
                                return
                            }

                            let inAppRaw = UserDefaults.standard.string(forKey: "inAppPlayer") ?? InAppPlayer.normal.rawValue
                            let inAppPlayer = (inAppRaw == "mpv") ? "mpv" : "Normal"

                            if inAppPlayer == "mpv" {
                                let preset = PlayerPreset.presets.first
                                let pvc = PlayerViewController(url: streamURL, preset: preset ?? PlayerPreset(id: .sdrRec709, title: "Default", summary: "", stream: nil, commands: []), headers: finalHeaders, subtitles: subtitles)
                                if entry.type == .movie {
                                    if let idStr = entry.id.split(separator: "_").last, let movieId = Int(idStr) {
                                        pvc.mediaInfo = .movie(id: movieId, title: canonicalTitle)
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
                                let asset: AVURLAsset
                                if let headers = finalHeaders {
                                    asset = AVURLAsset(url: streamURL, options: ["AVURLAssetHTTPHeaderFieldsKey": headers])
                                } else {
                                    asset = AVURLAsset(url: streamURL, options: nil)
                                }
                                let item = AVPlayerItem(asset: asset)
                                playerVC.player = AVPlayer(playerItem: item)
                                if entry.type == .movie {
                                    if let idStr = entry.id.split(separator: "_").last, let movieId = Int(idStr) {
                                        playerVC.mediaInfo = .movie(id: movieId, title: canonicalTitle)
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
                            Logger.shared.log("CW Resume no stream; open detail fallback", type: "ContinueWatching")
                            var userInfo: [String: Any] = [:]
                            switch entry.type {
                            case .movie:
                                if let idStr = entry.id.split(separator: "_").last, let movieId = Int(idStr) {
                                    userInfo["tmdbId"] = movieId
                                    userInfo["isMovie"] = true
                                    userInfo["title"] = canonicalTitle
                                }
                            case .episode:
                                if let showId = entry.showId {
                                    userInfo["tmdbId"] = showId
                                    userInfo["isMovie"] = false
                                    userInfo["title"] = canonicalTitle
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

            recordProgressSnapshot()
            postModulesSearch()
            return
        }

        recordProgressSnapshot()
        DispatchQueue.main.async {
            postModulesSearch()
        }
    }

    private func resolveCanonicalTitle(for entry: ContinueWatchingEntry) async -> String {
        if let title = entry.showTitle, !title.isEmpty {
            return title
        }

        // Prefer AniList metadata for anime (cached mapping from TMDB -> AniList ID)
        if entry.type == .episode, let showId = entry.showId, let anilistId = TrackerManager.shared.cachedAniListId(for: showId) {
            if let info = try? await AniListService.shared.fetchAnimeBasicInfo(anilistId: anilistId) {
                await MainActor.run {
                    if let idx = self.entries.firstIndex(where: { $0.id == entry.id }) {
                        self.entries[idx].showTitle = info.title
                        if self.entries[idx].imageURL == nil, let cover = info.coverImage {
                            self.entries[idx].imageURL = cover
                        }
                    }
                }
                return info.title
            }
        }

        switch entry.type {
        case .movie:
            if let idStr = entry.id.split(separator: "_").last, let movieId = Int(idStr) {
                if let detail = try? await TMDBService.shared.getMovieDetails(id: movieId) {
                    await MainActor.run {
                        if let idx = self.entries.firstIndex(where: { $0.id == entry.id }) {
                            self.entries[idx].showTitle = detail.title
                            if self.entries[idx].imageURL == nil, let poster = detail.fullPosterURL {
                                self.entries[idx].imageURL = poster
                            }
                        }
                    }
                    return detail.title
                }
            }
        case .episode:
            if let showId = entry.showId {
                if let detail = try? await TMDBService.shared.getTVShowDetails(id: showId) {
                    await MainActor.run {
                        if let idx = self.entries.firstIndex(where: { $0.id == entry.id }) {
                            self.entries[idx].showTitle = detail.name
                            if self.entries[idx].imageURL == nil, let poster = detail.fullPosterURL {
                                self.entries[idx].imageURL = poster
                            }
                        }
                    }
                    return detail.name
                }
            }
        }

        return entry.showTitle ?? entry.title
    }

    func playFromStart(_ entry: ContinueWatchingEntry) {
        let canonicalTitle = entry.showTitle ?? entry.title

        // Reset progress to start so players won't seek
        switch entry.type {
        case .movie:
            if let idStr = entry.id.split(separator: "_").last, let movieId = Int(idStr) {
                ProgressManager.shared.updateMovieProgress(movieId: movieId, title: canonicalTitle, currentTime: 0, totalDuration: entry.totalDuration)
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
