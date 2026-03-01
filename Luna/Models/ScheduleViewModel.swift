//
//  ScheduleViewModel.swift
//  Luna
//
//  Created by Soupy-dev
//

import Foundation

final class ScheduleViewModel: ObservableObject {
    @Published var isLoading = true
    @Published var errorMessage: String?
    @Published var scheduleEntries: [AniListAiringScheduleEntry] = []
    @Published var dayBuckets: [DayBucket] = []
    @Published var currentDayAnchor = Date()
    
    private let scheduleDaysAhead = 7
    
    init() {}
    
    func loadSchedule(localTimeZone: Bool) async {
        await MainActor.run {
            isLoading = true
            errorMessage = nil
        }
        
        do {
            let entries = try await AniListService.shared.fetchAiringSchedule(daysAhead: scheduleDaysAhead)
            await MainActor.run {
                isLoading = false
                scheduleEntries = entries
                currentDayAnchor = Date()
                updateBuckets(with: entries, localTimeZone: localTimeZone)
            }
        } catch {
            await MainActor.run {
                isLoading = false
                errorMessage = error.localizedDescription
            }
        }
    }
    
    func updateBuckets(with entries: [AniListAiringScheduleEntry], localTimeZone: Bool) {
        let calendar = makeCalendar(localTimeZone: localTimeZone)
        let startOfToday = calendar.startOfDay(for: Date())
        
        var buckets: [DayBucket] = []
        for offset in 0...scheduleDaysAhead {
            guard let day = calendar.date(byAdding: .day, value: offset, to: startOfToday),
                  let nextDay = calendar.date(byAdding: .day, value: 1, to: calendar.startOfDay(for: day)) else {
                continue
            }
            
            let dayItems = entries
                .filter { entry in
                    entry.airingAt >= calendar.startOfDay(for: day) && entry.airingAt < nextDay
                }
                .sorted { $0.airingAt < $1.airingAt }
            
            buckets.append(DayBucket(date: calendar.startOfDay(for: day), items: dayItems))
        }
        
        dayBuckets = buckets
    }
    
    func regroupBuckets(localTimeZone: Bool) {
        updateBuckets(with: scheduleEntries, localTimeZone: localTimeZone)
    }
    
    func handleDayChangeIfNeeded(localTimeZone: Bool) async {
        let calendar = makeCalendar(localTimeZone: localTimeZone)
        let trackedDay = calendar.startOfDay(for: currentDayAnchor)
        let today = calendar.startOfDay(for: Date())
        
        if today != trackedDay {
            await loadSchedule(localTimeZone: localTimeZone)
        } else {
            await MainActor.run {
                currentDayAnchor = Date()
                updateBuckets(with: scheduleEntries, localTimeZone: localTimeZone)
            }
        }
    }
    
    private func makeCalendar(localTimeZone: Bool) -> Calendar {
        var calendar = Calendar.current
        calendar.timeZone = localTimeZone ? .current : TimeZone(secondsFromGMT: 0)!
        return calendar
    }
    
    // MARK: - TMDB Lookup
    
    /// Cache keyed by AniList media ID to avoid redundant TMDB API calls.
    /// Stores Optional<TMDBSearchResult> so we also cache "not found" results.
    private var tmdbCache: [Int: TMDBSearchResult?] = [:]
    
    func lookupTMDBResult(for entry: AniListAiringScheduleEntry) async -> TMDBSearchResult? {
        // Return cached result (including cached nil) to avoid repeat API calls
        if let cached = tmdbCache[entry.mediaId] {
            return cached
        }
        
        let result = await performTMDBLookup(for: entry)
        tmdbCache[entry.mediaId] = .some(result)
        return result
    }
    
    private func performTMDBLookup(for entry: AniListAiringScheduleEntry) async -> TMDBSearchResult? {
        func normalized(_ value: String) -> String {
            value.lowercased().components(separatedBy: CharacterSet.alphanumerics.inverted).joined()
        }
        
        // Build unique title candidates in preference order
        var seen = Set<String>()
        let titleCandidates = [entry.englishTitle, entry.romajiTitle, entry.nativeTitle]
            .compactMap { $0?.trimmingCharacters(in: .whitespaces) }
            .filter { !$0.isEmpty && seen.insert($0).inserted }
        
        // Fallback to the display title if no variants available
        let candidates = titleCandidates.isEmpty ? [entry.title] : titleCandidates
        let tmdbService = TMDBService.shared
        let isMovie = entry.format?.uppercased() == "MOVIE"
        
        for candidate in candidates {
            // For movies, search TMDB movies; for everything else, search TV shows
            if isMovie {
                if let result = try? await tmdbService.searchMovies(query: candidate),
                   let best = bestMovieMatch(results: result, candidateKey: normalized(candidate)) {
                    return best.asSearchResult
                }
            } else {
                if let result = try? await tmdbService.searchTVShows(query: candidate),
                   let best = bestTVMatch(results: result, candidateKey: normalized(candidate)) {
                    return best.asSearchResult
                }
            }
        }
        
        // Fallback: try searchMulti for any format
        for candidate in candidates {
            if let results = try? await tmdbService.searchMulti(query: candidate, maxPages: 1), !results.isEmpty {
                let candidateKey = normalized(candidate)
                // Prefer animation genre and exact/partial title match
                let filtered = results.filter { r in
                    let nameKey = normalized(r.displayTitle)
                    return nameKey == candidateKey || nameKey.contains(candidateKey) || candidateKey.contains(nameKey)
                }
                let pool = filtered.isEmpty ? results : filtered
                let best = pool.min { a, b in
                    let aAnim = a.genreIds?.contains(16) == true
                    let bAnim = b.genreIds?.contains(16) == true
                    if aAnim != bAnim { return aAnim }
                    return a.popularity > b.popularity
                }
                if let best = best { return best }
            }
        }
        
        return nil
    }
    
    private func bestTVMatch(results: [TMDBTVShow], candidateKey: String) -> TMDBTVShow? {
        func normalized(_ value: String) -> String {
            value.lowercased().components(separatedBy: CharacterSet.alphanumerics.inverted).joined()
        }
        guard !results.isEmpty else { return nil }
        
        let exactMatches = results.filter { normalized($0.name) == candidateKey }
        if !exactMatches.isEmpty {
            return exactMatches.min { a, b in
                let aAnim = a.genreIds?.contains(16) == true
                let bAnim = b.genreIds?.contains(16) == true
                if aAnim != bAnim { return aAnim }
                return a.popularity > b.popularity
            }
        }
        
        let partialMatches = results.filter {
            let nameKey = normalized($0.name)
            return nameKey.contains(candidateKey) || candidateKey.contains(nameKey)
        }
        if !partialMatches.isEmpty {
            return partialMatches.min { a, b in
                let aAnim = a.genreIds?.contains(16) == true
                let bAnim = b.genreIds?.contains(16) == true
                if aAnim != bAnim { return aAnim }
                return a.popularity > b.popularity
            }
        }
        
        return results.min { a, b in
            let aAnim = a.genreIds?.contains(16) == true
            let bAnim = b.genreIds?.contains(16) == true
            if aAnim != bAnim { return aAnim }
            return a.popularity > b.popularity
        }
    }
    
    private func bestMovieMatch(results: [TMDBMovie], candidateKey: String) -> TMDBMovie? {
        func normalized(_ value: String) -> String {
            value.lowercased().components(separatedBy: CharacterSet.alphanumerics.inverted).joined()
        }
        guard !results.isEmpty else { return nil }
        
        let exactMatches = results.filter { normalized($0.title) == candidateKey }
        if !exactMatches.isEmpty {
            return exactMatches.min { a, b in
                let aAnim = a.genreIds?.contains(16) == true
                let bAnim = b.genreIds?.contains(16) == true
                if aAnim != bAnim { return aAnim }
                return a.popularity > b.popularity
            }
        }
        
        let partialMatches = results.filter {
            let nameKey = normalized($0.title)
            return nameKey.contains(candidateKey) || candidateKey.contains(nameKey)
        }
        if !partialMatches.isEmpty {
            return partialMatches.min { a, b in
                let aAnim = a.genreIds?.contains(16) == true
                let bAnim = b.genreIds?.contains(16) == true
                if aAnim != bAnim { return aAnim }
                return a.popularity > b.popularity
            }
        }
        
        return results.min { a, b in
            let aAnim = a.genreIds?.contains(16) == true
            let bAnim = b.genreIds?.contains(16) == true
            if aAnim != bAnim { return aAnim }
            return a.popularity > b.popularity
        }
    }
}

struct DayBucket: Identifiable {
    let id = UUID()
    let date: Date
    let items: [AniListAiringScheduleEntry]
}
