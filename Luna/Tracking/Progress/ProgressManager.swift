//
//  ProgressManager.swift
//  Sora
//
//  Created by Francesco on 27/08/25.
//

import Foundation
import AVFoundation
import Combine

// MARK: - Data Models

struct ShowMetadata: Codable {
    let showId: Int
    var title: String
    var posterURL: String?
}

struct ProgressData: Codable {
    var movieProgress: [MovieProgressEntry] = []
    var episodeProgress: [EpisodeProgressEntry] = []
    var showMetadata: [Int: ShowMetadata] = [:]  // showId -> metadata

    mutating func updateMovie(_ entry: MovieProgressEntry) {
        if let index = movieProgress.firstIndex(where: { $0.id == entry.id }) {
            movieProgress[index] = entry
        } else {
            movieProgress.append(entry)
        }
    }

    mutating func updateEpisode(_ entry: EpisodeProgressEntry) {
        if let index = episodeProgress.firstIndex(where: { $0.id == entry.id }) {
            episodeProgress[index] = entry
        } else {
            episodeProgress.append(entry)
        }
    }
    
    mutating func updateShowMetadata(showId: Int, title: String, posterURL: String?) {
        showMetadata[showId] = ShowMetadata(showId: showId, title: title, posterURL: posterURL)
    }

    func findMovie(id: Int) -> MovieProgressEntry? {
        movieProgress.first { $0.id == id }
    }

    func findEpisode(showId: Int, season: Int, episode: Int) -> EpisodeProgressEntry? {
        episodeProgress.first { $0.showId == showId && $0.seasonNumber == season && $0.episodeNumber == episode }
    }
    
    func getShowMetadata(showId: Int) -> ShowMetadata? {
        showMetadata[showId]
    }
}

struct MovieProgressEntry: Codable, Identifiable {
    let id: Int
    let title: String
    var posterURL: String? = nil
    var currentTime: Double = 0
    var totalDuration: Double = 0
    var isWatched: Bool = false
    var lastUpdated: Date = Date()
    var lastServiceId: UUID? = nil
    var lastHref: String? = nil

    var progress: Double {
        guard totalDuration > 0 else { return 0 }
        return min(currentTime / totalDuration, 1.0)
    }
}

struct EpisodeProgressEntry: Codable, Identifiable {
    let id: String
    let showId: Int
    let seasonNumber: Int
    let episodeNumber: Int
    var currentTime: Double = 0
    var totalDuration: Double = 0
    var isWatched: Bool = false
    var lastUpdated: Date = Date()
    var lastServiceId: UUID? = nil
    var lastHref: String? = nil

    var progress: Double {
        guard totalDuration > 0 else { return 0 }
        return min(currentTime / totalDuration, 1.0)
    }

    init(showId: Int, seasonNumber: Int, episodeNumber: Int) {
        self.id = "ep_\(showId)_s\(seasonNumber)_e\(episodeNumber)"
        self.showId = showId
        self.seasonNumber = seasonNumber
        self.episodeNumber = episodeNumber
    }
}

// Helper for episode resume context
struct EpisodeProgressSnapshot {
    let showId: Int
    let seasonNumber: Int
    let episodeNumber: Int
    let progress: Double
    let lastUpdated: Date
}

// Continue watching item
struct ContinueWatchingItem: Identifiable {
    let id: String
    let tmdbId: Int
    let isMovie: Bool
    let title: String
    let posterURL: String?
    let progress: Double
    let lastUpdated: Date
    let seasonNumber: Int?
    let episodeNumber: Int?
    let currentTime: Double
    let totalDuration: Double
    
    var remainingTime: String {
        let remaining = max(0, totalDuration - currentTime)
        let minutes = Int(remaining / 60)
        if minutes < 60 {
            return "\(minutes) min left"
        } else {
            let hours = minutes / 60
            let mins = minutes % 60
            return mins > 0 ? "\(hours)h \(mins)m left" : "\(hours)h left"
        }
    }
}

// MARK: - ProgressManager

final class ProgressManager: ObservableObject {
    static let shared = ProgressManager()

    private let fileManager = FileManager.default
    private var progressData: ProgressData = ProgressData()
    private let progressFileURL: URL
    private let debounceInterval: TimeInterval = 2.0
    private var debounceTask: Task<Void, Never>?
    private let accessQueue = DispatchQueue(label: "com.luna.progress-manager", attributes: .concurrent)

    private static let documentsDirectory = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)[0]
    @Published private(set) var movieProgressList: [MovieProgressEntry] = []
    @Published private(set) var episodeProgressList: [EpisodeProgressEntry] = []

    private init() {
        self.progressFileURL = Self.documentsDirectory.appendingPathComponent("ProgressData.json")
        loadProgressData()
    }
    
    // MARK: - Public Access
    
    /// Returns a snapshot of the current progress data for backup purposes
    func getProgressData() -> ProgressData {
        return accessQueue.sync {
            return self.progressData
        }
    }

    private func publishCurrentData() {
        accessQueue.async { [weak self] in
            guard let self = self else { return }
            let movies = self.progressData.movieProgress
            let episodes = self.progressData.episodeProgress
            DispatchQueue.main.async {
                self.movieProgressList = movies
                self.episodeProgressList = episodes
            }
        }
    }

    // MARK: - Data Persistence

    private func loadProgressData() {
        guard fileManager.fileExists(atPath: progressFileURL.path) else {
            Logger.shared.log("Progress file not found, initializing new data", type: "Progress")
            return
        }

        do {
            let data = try Data(contentsOf: progressFileURL)
            Logger.shared.log("Raw JSON file size: \(data.count) bytes", type: "Progress")

            // Log just the episode section to see structure
            if let jsonString = String(data: data, encoding: .utf8), jsonString.contains("\"episodeProgress\"") {
                if let start = jsonString.range(of: "\"episodeProgress\""),
                   let end = jsonString.range(of: "]", range: start.upperBound..<jsonString.endIndex) {
                    let section = String(jsonString[start.lowerBound..<end.upperBound])
                    let preview = section.count > 500 ? String(section.prefix(500)) + "..." : section
                    Logger.shared.log("Episode section: \(preview)", type: "Progress")
                }
            }

            let decoded = try JSONDecoder().decode(ProgressData.self, from: data)
            Logger.shared.log("Loaded \(decoded.episodeProgress.count) episodes from JSON", type: "Progress")
            for ep in decoded.episodeProgress.prefix(5) {
                Logger.shared.log("  - showId=\(ep.showId) S\(ep.seasonNumber)E\(ep.episodeNumber)", type: "Progress")
            }
            accessQueue.async(flags: .barrier) { [weak self] in
                self?.progressData = decoded
                self?.publishCurrentData()
            }
            Logger.shared.log("Progress data loaded successfully (\(decoded.movieProgress.count) movies, \(decoded.episodeProgress.count) episodes)", type: "Progress")
        } catch {
            Logger.shared.log("Failed to load progress data: \(error.localizedDescription)", type: "Error")
        }
    }

    private func saveProgressData() {
        accessQueue.async { [weak self] in
            guard let self = self else { return }
            do {
                let data = try JSONEncoder().encode(self.progressData)
                try data.write(to: self.progressFileURL, options: .atomic)
                Logger.shared.log("Progress data saved successfully", type: "Progress")
            } catch {
                Logger.shared.log("Failed to save progress data: \(error.localizedDescription)", type: "Error")
            }
        }
    }

    private func debouncedSave() {
        debounceTask?.cancel()
        debounceTask = Task {
            try? await Task.sleep(nanoseconds: UInt64(debounceInterval * 1_000_000_000))
            if !Task.isCancelled {
                self.saveProgressData()
            }
        }
    }

    // MARK: - Movie Progress

    func updateMovieProgress(movieId: Int, title: String, currentTime: Double, totalDuration: Double, posterURL: String? = nil) {
        guard currentTime >= 0 && totalDuration > 0 && currentTime <= totalDuration else {
            Logger.shared.log("Invalid progress values for movie \(title): currentTime=\(currentTime), totalDuration=\(totalDuration)", type: "Warning")
            return
        }

        accessQueue.async(flags: .barrier) { [weak self] in
            guard let self = self else { return }
            var entry = self.progressData.findMovie(id: movieId) ?? MovieProgressEntry(id: movieId, title: title)
            entry.currentTime = currentTime
            entry.totalDuration = totalDuration
            entry.lastUpdated = Date()
            
            // Update poster if provided
            if let posterURL = posterURL {
                entry.posterURL = posterURL
            }

            if entry.progress >= 0.85 {
                entry.isWatched = true
            }

            self.progressData.updateMovie(entry)
            self.publishCurrentData()
        }
        debouncedSave()
    }
    
    func updateMoviePoster(movieId: Int, posterURL: String) {
        accessQueue.async(flags: .barrier) { [weak self] in
            guard let self = self else { return }
            if var entry = self.progressData.findMovie(id: movieId) {
                entry.posterURL = posterURL
                self.progressData.updateMovie(entry)
                self.publishCurrentData()
                self.debouncedSave()
            }
        }
    }

    func getMovieProgress(movieId: Int, title: String) -> Double {
        var result: Double = 0.0
        accessQueue.sync {
            result = self.progressData.findMovie(id: movieId)?.progress ?? 0.0
        }
        return result
    }

    func getMovieCurrentTime(movieId: Int, title: String) -> Double {
        var result: Double = 0.0
        accessQueue.sync {
            result = self.progressData.findMovie(id: movieId)?.currentTime ?? 0.0
        }
        return result
    }

    func isMovieWatched(movieId: Int, title: String) -> Bool {
        var result: Bool = false
        accessQueue.sync {
            if let entry = self.progressData.findMovie(id: movieId) {
                result = entry.isWatched || entry.progress >= 0.85
            }
        }
        return result
    }

    func markMovieAsWatched(movieId: Int, title: String) {
        accessQueue.async(flags: .barrier) { [weak self] in
            guard let self = self else { return }
            if var entry = self.progressData.findMovie(id: movieId) {
                entry.isWatched = true
                entry.currentTime = entry.totalDuration
                entry.lastUpdated = Date()
                self.progressData.updateMovie(entry)
                self.publishCurrentData()
                Logger.shared.log("Marked movie as watched: \(title)", type: "Progress")
            }
        }
        saveProgressData()
    }

    func resetMovieProgress(movieId: Int, title: String) {
        accessQueue.async(flags: .barrier) { [weak self] in
            guard let self = self else { return }
            if var entry = self.progressData.findMovie(id: movieId) {
                entry.currentTime = 0
                entry.isWatched = false
                entry.lastUpdated = Date()
                self.progressData.updateMovie(entry)
                self.publishCurrentData()
                Logger.shared.log("Reset movie progress: \(title)", type: "Progress")
            }
        }
        saveProgressData()
    }

    // MARK: - Record last service/href used for playback

    func recordMovieServiceInfo(movieId: Int, serviceId: UUID?, href: String?) {
        accessQueue.async(flags: .barrier) { [weak self] in
            guard let self = self else { return }
            if var entry = self.progressData.findMovie(id: movieId) {
                entry.lastServiceId = serviceId
                entry.lastHref = href
                entry.lastUpdated = Date()
                self.progressData.updateMovie(entry)
                self.publishCurrentData()
            } else {
                var newEntry = MovieProgressEntry(id: movieId, title: "")
                newEntry.lastServiceId = serviceId
                newEntry.lastHref = href
                newEntry.lastUpdated = Date()
                self.progressData.updateMovie(newEntry)
                self.publishCurrentData()
            }
        }
        saveProgressData()
    }

    func recordEpisodeServiceInfo(showId: Int, seasonNumber: Int, episodeNumber: Int, serviceId: UUID?, href: String?) {
        accessQueue.async(flags: .barrier) { [weak self] in
            guard let self = self else { return }
            if var entry = self.progressData.findEpisode(showId: showId, season: seasonNumber, episode: episodeNumber) {
                entry.lastServiceId = serviceId
                entry.lastHref = href
                entry.lastUpdated = Date()
                self.progressData.updateEpisode(entry)
                self.publishCurrentData()
            } else {
                var newEntry = EpisodeProgressEntry(showId: showId, seasonNumber: seasonNumber, episodeNumber: episodeNumber)
                newEntry.lastServiceId = serviceId
                newEntry.lastHref = href
                newEntry.lastUpdated = Date()
                self.progressData.updateEpisode(newEntry)
                self.publishCurrentData()
            }
        }
        saveProgressData()
    }

    // MARK: - Episode Progress

    func updateEpisodeProgress(showId: Int, seasonNumber: Int, episodeNumber: Int, currentTime: Double, totalDuration: Double, showTitle: String? = nil, showPosterURL: String? = nil) {
        guard currentTime >= 0 && totalDuration > 0 && currentTime <= totalDuration else {
            Logger.shared.log("Invalid progress values for episode S\(seasonNumber)E\(episodeNumber): currentTime=\(currentTime), totalDuration=\(totalDuration)", type: "Warning")       
            return
        }

        Logger.shared.log("Storing progress for showId=\(showId) S\(seasonNumber)E\(episodeNumber) position=\(currentTime)/\(totalDuration)", type: "Progress")

        accessQueue.async(flags: .barrier) { [weak self] in
            guard let self = self else { return }
            var entry = self.progressData.findEpisode(showId: showId, season: seasonNumber, episode: episodeNumber)
                ?? EpisodeProgressEntry(showId: showId, seasonNumber: seasonNumber, episodeNumber: episodeNumber)

            let previousWatchedState = entry.isWatched
            entry.currentTime = currentTime
            entry.totalDuration = totalDuration
            entry.lastUpdated = Date()

            if entry.progress >= 0.85 {
                entry.isWatched = true
            }

            self.progressData.updateEpisode(entry)
            
            // Update show metadata if provided
            if let showTitle = showTitle {
                self.progressData.updateShowMetadata(showId: showId, title: showTitle, posterURL: showPosterURL)
            }
            
            self.publishCurrentData()

            // Sync to trackers if just reached watched threshold
            if !previousWatchedState && entry.isWatched {
                DispatchQueue.main.async {
                    TrackerManager.shared.syncWatchProgress(showId: showId, seasonNumber: seasonNumber, episodeNumber: episodeNumber, progress: entry.progress)
                }
            }
        }
        debouncedSave()
    }
    
    func updateShowMetadata(showId: Int, title: String, posterURL: String?) {
        accessQueue.async(flags: .barrier) { [weak self] in
            guard let self = self else { return }
            self.progressData.updateShowMetadata(showId: showId, title: title, posterURL: posterURL)
            self.publishCurrentData()
            self.debouncedSave()
        }
    }

    func getEpisodeProgress(showId: Int, seasonNumber: Int, episodeNumber: Int) -> Double {
        var result: Double = 0.0
        accessQueue.sync {
            result = self.progressData.findEpisode(showId: showId, season: seasonNumber, episode: episodeNumber)?.progress ?? 0.0
        }
        return result
    }

    func getEpisodeCurrentTime(showId: Int, seasonNumber: Int, episodeNumber: Int) -> Double {
        var result: Double = 0.0
        accessQueue.sync {
            result = self.progressData.findEpisode(showId: showId, season: seasonNumber, episode: episodeNumber)?.currentTime ?? 0.0
        }
        return result
    }

    /// Returns the most recently updated episode progress for a given show (if any).
    func latestEpisodeProgress(for showId: Int) -> EpisodeProgressSnapshot? {
        var snapshot: EpisodeProgressSnapshot? = nil
        accessQueue.sync {
            let entries = self.progressData.episodeProgress.filter { $0.showId == showId }
            if let latest = entries.max(by: { $0.lastUpdated < $1.lastUpdated }) {
                snapshot = EpisodeProgressSnapshot(
                    showId: latest.showId,
                    seasonNumber: latest.seasonNumber,
                    episodeNumber: latest.episodeNumber,
                    progress: latest.progress,
                    lastUpdated: latest.lastUpdated
                )
            }
        }
        return snapshot
    }

    func isEpisodeWatched(showId: Int, seasonNumber: Int, episodeNumber: Int) -> Bool {
        var result: Bool = false
        accessQueue.sync {
            if let entry = self.progressData.findEpisode(showId: showId, season: seasonNumber, episode: episodeNumber) {
                result = entry.isWatched || entry.progress >= 0.85
            }
        }
        return result
    }

    func markEpisodeAsWatched(showId: Int, seasonNumber: Int, episodeNumber: Int) {
        accessQueue.async(flags: .barrier) { [weak self] in
            guard let self = self else { return }
            var entry = self.progressData.findEpisode(showId: showId, season: seasonNumber, episode: episodeNumber)
                ?? EpisodeProgressEntry(showId: showId, seasonNumber: seasonNumber, episodeNumber: episodeNumber)
            let safeDuration = entry.totalDuration > 0 ? entry.totalDuration : max(entry.currentTime, 1)
            entry.totalDuration = safeDuration
            entry.isWatched = true
            entry.currentTime = safeDuration
            entry.lastUpdated = Date()
            self.progressData.updateEpisode(entry)
            self.publishCurrentData()
            Logger.shared.log("Marked episode as watched: S\(seasonNumber)E\(episodeNumber)", type: "Progress")

            // Sync to trackers
            DispatchQueue.main.async {
                TrackerManager.shared.syncWatchProgress(showId: showId, seasonNumber: seasonNumber, episodeNumber: episodeNumber, progress: 1.0)
            }
        }
        saveProgressData()
    }

    func resetEpisodeProgress(showId: Int, seasonNumber: Int, episodeNumber: Int) {
        accessQueue.async(flags: .barrier) { [weak self] in
            guard let self = self else { return }
            var entry = self.progressData.findEpisode(showId: showId, season: seasonNumber, episode: episodeNumber)
                ?? EpisodeProgressEntry(showId: showId, seasonNumber: seasonNumber, episodeNumber: episodeNumber)
            entry.currentTime = 0
            entry.isWatched = false
            entry.lastUpdated = Date()
            self.progressData.updateEpisode(entry)
            self.publishCurrentData()
            Logger.shared.log("Reset episode progress: S\(seasonNumber)E\(episodeNumber)", type: "Progress")
        }
        saveProgressData()
    }

    func markPreviousEpisodesAsWatched(showId: Int, seasonNumber: Int, episodeNumber: Int) {
        guard episodeNumber > 1 else { return }

        accessQueue.async(flags: .barrier) { [weak self] in
            guard let self = self else { return }
            for e in 1..<episodeNumber {
                var entry = self.progressData.findEpisode(showId: showId, season: seasonNumber, episode: e)
                    ?? EpisodeProgressEntry(showId: showId, seasonNumber: seasonNumber, episodeNumber: e)
                let safeDuration = entry.totalDuration > 0 ? entry.totalDuration : max(entry.currentTime, 1)
                entry.totalDuration = safeDuration
                entry.isWatched = true
                entry.currentTime = safeDuration
                entry.lastUpdated = Date()
                self.progressData.updateEpisode(entry)
            }
            self.publishCurrentData()
            Logger.shared.log("Marked previous episodes as watched for S\(seasonNumber) up to E\(episodeNumber - 1)", type: "Progress")
        }
        saveProgressData()
    }

    func markEpisodeAsUnwatched(showId: Int, seasonNumber: Int, episodeNumber: Int) {
        accessQueue.async(flags: .barrier) { [weak self] in
            guard let self = self else { return }
            var entry = self.progressData.findEpisode(showId: showId, season: seasonNumber, episode: episodeNumber)
                ?? EpisodeProgressEntry(showId: showId, seasonNumber: seasonNumber, episodeNumber: episodeNumber)
            entry.currentTime = 0
            entry.isWatched = false
            entry.lastUpdated = Date()
            self.progressData.updateEpisode(entry)
            self.publishCurrentData()
            Logger.shared.log("Marked episode as unwatched: S\(seasonNumber)E\(episodeNumber)", type: "Progress")
        }
        saveProgressData()
    }

    func markPreviousEpisodesAsUnwatched(showId: Int, seasonNumber: Int, episodeNumber: Int) {
        guard episodeNumber > 1 else { return }

        accessQueue.async(flags: .barrier) { [weak self] in
            guard let self = self else { return }
            for e in 1..<episodeNumber {
                var entry = self.progressData.findEpisode(showId: showId, season: seasonNumber, episode: e)
                    ?? EpisodeProgressEntry(showId: showId, seasonNumber: seasonNumber, episodeNumber: e)
                entry.currentTime = 0
                entry.isWatched = false
                entry.lastUpdated = Date()
                self.progressData.updateEpisode(entry)
            }
            self.publishCurrentData()
            Logger.shared.log("Marked previous episodes as unwatched for S\(seasonNumber) up to E\(episodeNumber - 1)", type: "Progress")
        }
        saveProgressData()
    }

    // MARK: - Continue Watching
    
    func getContinueWatchingItems() -> [ContinueWatchingItem] {
        var items: [ContinueWatchingItem] = []
        
        accessQueue.sync {
            // Add movies
            let movies = self.progressData.movieProgress
                .filter { $0.progress > 0.05 && $0.progress < 0.85 }
                .map { movie in
                    ContinueWatchingItem(
                        id: "movie_\(movie.id)",
                        tmdbId: movie.id,
                        isMovie: true,
                        title: movie.title,
                        posterURL: movie.posterURL,
                        progress: movie.progress,
                        lastUpdated: movie.lastUpdated,
                        seasonNumber: nil,
                        episodeNumber: nil,
                        currentTime: movie.currentTime,
                        totalDuration: movie.totalDuration
                    )
                }
            
            // Add episodes (grouped by show, keep most recent)
            var showMap: [Int: EpisodeProgressEntry] = [:]
            for episode in self.progressData.episodeProgress where episode.progress > 0.05 && episode.progress < 0.85 {
                if let existing = showMap[episode.showId] {
                    if episode.lastUpdated > existing.lastUpdated {
                        showMap[episode.showId] = episode
                    }
                } else {
                    showMap[episode.showId] = episode
                }
            }
            
            let episodes = showMap.values.map { episode in
                // Look up show metadata
                let showMeta = self.progressData.getShowMetadata(showId: episode.showId)
                return ContinueWatchingItem(
                    id: "episode_\(episode.showId)",
                    tmdbId: episode.showId,
                    isMovie: false,
                    title: showMeta?.title ?? "",
                    posterURL: showMeta?.posterURL,
                    progress: episode.progress,
                    lastUpdated: episode.lastUpdated,
                    seasonNumber: episode.seasonNumber,
                    episodeNumber: episode.episodeNumber,
                    currentTime: episode.currentTime,
                    totalDuration: episode.totalDuration
                )
            }
            
            items = (movies + episodes)
                .sorted { $0.lastUpdated > $1.lastUpdated }
                .prefix(6)
                .map { $0 }
        }
        
        return items
    }

    // MARK: - AVPlayer Extension

    func addPeriodicTimeObserver(to player: AVPlayer, for mediaInfo: MediaInfo) -> Any? {
        let interval = CMTime(seconds: 1.0, preferredTimescale: CMTimeScale(NSEC_PER_SEC))

        return player.addPeriodicTimeObserver(forInterval: interval, queue: .main) { [weak self] time in
            guard let self = self,
                  let currentItem = player.currentItem,
                  currentItem.duration.seconds.isFinite,
                  currentItem.duration.seconds > 0 else {
                return
            }

            let currentTime = time.seconds
            let duration = currentItem.duration.seconds

            guard currentTime >= 0 && currentTime <= duration else { return }

            switch mediaInfo {
            case .movie(let id, let title, let posterURL, _):
                self.updateMovieProgress(movieId: id, title: title, currentTime: currentTime, totalDuration: duration, posterURL: posterURL)

            case .episode(let showId, let seasonNumber, let episodeNumber, let showTitle, let showPosterURL, _):
                self.updateEpisodeProgress(showId: showId, seasonNumber: seasonNumber, episodeNumber: episodeNumber, currentTime: currentTime, totalDuration: duration, showTitle: showTitle, showPosterURL: showPosterURL)
            }
        }
    }
}


// MARK: - MediaInfo Enum

enum MediaInfo {
    case movie(id: Int, title: String, posterURL: String? = nil, isAnime: Bool = false)
    case episode(showId: Int, seasonNumber: Int, episodeNumber: Int, showTitle: String? = nil, showPosterURL: String? = nil, isAnime: Bool = false)
}
