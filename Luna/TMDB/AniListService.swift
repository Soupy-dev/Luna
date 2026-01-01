//
//  AniListService.swift
//  Luna
//
//  Created by Soupy-dev
//

import Foundation

class AniListService {
    static let shared = AniListService()
    
    private let graphQLEndpoint = URL(string: "https://graphql.anilist.co")!
    private let trackerManager = TrackerManager.shared

    private var preferredLanguageCode: String {
        let raw = UserDefaults.standard.string(forKey: "tmdbLanguage") ?? "en-US"
        return raw.split(separator: "-").first.map(String.init) ?? "en"
    }

    enum AniListCatalogKind {
        case trending
        case popular
        case topRated
        case airing
        case upcoming
    }

    // MARK: - Catalog Fetching

    /// Fetch a lightweight AniList catalog and hydrate entries with TMDB matches for posters/details.
    func fetchAnimeCatalog(
        _ kind: AniListCatalogKind,
        limit: Int = 20,
        tmdbService: TMDBService
    ) async throws -> [TMDBSearchResult] {
        let sort: String
        let status: String?

        switch kind {
        case .trending:
            sort = "TRENDING_DESC"
            status = nil
        case .popular:
            sort = "POPULARITY_DESC"
            status = nil
        case .topRated:
            sort = "SCORE_DESC"
            status = nil
        case .airing:
            sort = "POPULARITY_DESC"
            status = "RELEASING"
        case .upcoming:
            sort = "POPULARITY_DESC"
            status = "NOT_YET_RELEASED"
        }

        let statusClause = status.map { ", status: \($0)" } ?? ""
        let query = """
        query {
            Page(perPage: \(limit)) {
                media(type: ANIME, sort: [\(sort)]\(statusClause)) {
                    id
                    title {
                        romaji
                        english
                        native
                    }
                    episodes
                    status
                    coverImage {
                        large
                        medium
                    }
                }
            }
        }
        """

        struct CatalogResponse: Codable {
            let data: DataWrapper
            struct DataWrapper: Codable {
                let Page: PageData
            }
            struct PageData: Codable {
                let media: [AniListAnime]
            }
        }

        let data = try await executeGraphQLQuery(query, token: nil)
        let decoded = try JSONDecoder().decode(CatalogResponse.self, from: data)
        let animeList = decoded.data.Page.media
        return await mapAniListCatalogToTMDB(animeList, tmdbService: tmdbService)
    }
    
    // MARK: - Fetch Anime Details
    
    /// Fetch full anime details with seasons and episodes from AniList + TMDB
    /// Uses AniList for season structure and sequels, TMDB for episode details
    func fetchAnimeDetailsWithEpisodes(
        title: String,
        tmdbShowId: Int,
        tmdbService: TMDBService,
        tmdbShowPoster: String?,
        token: String?
    ) async throws -> AniListAnimeWithSeasons {
        // Query AniList for anime structure + sequels + coverImage
        let query = """
        query {
            Media(search: "\(title.replacingOccurrences(of: "\"", with: "\\\""))", type: ANIME) {
                id
                title {
                    romaji
                    english
                    native
                }
                episodes
                status
                seasonYear
                season
                coverImage {
                    large
                    medium
                }
                format
                nextAiringEpisode {
                    episode
                    airingAt
                }
                relations {
                    edges {
                        relationType
                        node {
                            id
                            title {
                                romaji
                                english
                                native
                            }
                            episodes
                            status
                            seasonYear
                            season
                            format
                            type
                            coverImage {
                                large
                                medium
                            }
                            relations {
                                edges {
                                    relationType
                                    node {
                                        id
                                        title { romaji english native }
                                        episodes
                                        status
                                        seasonYear
                                        season
                                        format
                                        type
                                        coverImage { large medium }
                                    }
                                }
                            }
                        }
                    }
                }
            }
        }
        """
        
        let response = try await executeGraphQLQuery(query, token: token)
        
        struct Response: Codable {
            let data: DataWrapper
            struct DataWrapper: Codable {
                let Media: AniListAnime
            }
        }
        
        let result = try JSONDecoder().decode(Response.self, from: response)
        var anime = result.data.Media

        // If the first hit is not a TV/TV_SHORT (e.g., picked an OVA/Movie), try to find a TV entry by search
        let isNotTV = anime.format.map { !($0 == "TV" || $0 == "TV_SHORT") } ?? false
        if isNotTV {
            Logger.shared.log("AniListService: Initial result for '\(title)' is format \(anime.format ?? "UNKNOWN"), searching for TV version...", type: "AniList")
            if let tvCandidate = try? await fetchAniListAnimeBySearch(title, formats: ["TV", "TV_SHORT"]) {
                anime = tvCandidate
                Logger.shared.log("AniListService: Swapped to TV entry (ID: \(anime.id), format: \(anime.format ?? "UNKNOWN"))", type: "AniList")
            } else {
                Logger.shared.log("AniListService: No TV version found, using original result", type: "AniList")
            }
        }
        let title = AniListTitlePicker.title(from: anime.title, preferredLanguageCode: preferredLanguageCode)
        
        Logger.shared.log("AniListService: Raw response - episodes: \(anime.episodes ?? 0), seasonYear: \(anime.seasonYear ?? 0), season: \(anime.season ?? "UNKNOWN")", type: "AniList")
        
        // Collect all anime to process (original + all recursive sequels) with posters
        var allAnimeToProcess: [(anime: AniListAnime, seasonOffset: Int, posterUrl: String?)] = []

        func appendAnime(_ entry: AniListAnime) {
            let poster = entry.coverImage?.large ?? entry.coverImage?.medium ?? tmdbShowPoster
            allAnimeToProcess.append((entry, 0, poster))
        }

        appendAnime(anime)

        // Allowed relation types we treat as season/continuation
        let allowedRelationTypes: Set<String> = ["SEQUEL", "PREQUEL", "SEASON"]

        // BFS over sequels/prequels/seasons, recursively fetching relations when needed (format must be TV/TV_SHORT)
        var queue: [AniListAnime] = [anime]
        var seenIds = Set<Int>([anime.id])

        while let current = queue.first {
            queue.removeFirst()

            let edges = current.relations?.edges ?? []
            for edge in edges {
                guard allowedRelationTypes.contains(edge.relationType), edge.node.type == "ANIME" else { continue }
                if let format = edge.node.format, !(format == "TV" || format == "TV_SHORT") { continue }
                if !seenIds.insert(edge.node.id).inserted { continue }

                let titleStr = AniListTitlePicker.title(from: edge.node.title, preferredLanguageCode: preferredLanguageCode)
                Logger.shared.log("AniListService: Found sequel: \(titleStr)", type: "AniList")

                // Ensure we have this node's relations for deeper traversal
                let fullNode: AniListAnime
                if edge.node.relations != nil {
                    fullNode = edge.node
                } else if let fetched = try? await fetchAniListAnimeNode(id: edge.node.id) {
                    fullNode = fetched
                } else {
                    fullNode = edge.node
                }

                appendAnime(fullNode)
                queue.append(fullNode)
            }
        }
        
        // Fetch all TMDB season data (excluding Season 0 specials)
        // Build an absolute episode index so we can map stills/runtime even when seasons reset numbering
        // Also build a map of TMDB season numbers to poster paths
        var tmdbEpisodesByAbsolute: [Int: TMDBEpisode] = [:]
        var tmdbSeasonPosters: [Int: String] = [:]
        do {
            let tvShowDetail = try await tmdbService.getTVShowWithSeasons(id: tmdbShowId)

            var absoluteIndex = 1
            // Sort seasons by seasonNumber to keep ordering consistent
            let realSeasons = tvShowDetail.seasons.filter { $0.seasonNumber > 0 }.sorted { $0.seasonNumber < $1.seasonNumber }
            for season in realSeasons {
                // Store TMDB season poster if available
                if let posterPath = season.posterPath {
                    tmdbSeasonPosters[season.seasonNumber] = posterPath
                }
                
                do {
                    let seasonDetail = try await tmdbService.getSeasonDetails(tvShowId: tmdbShowId, seasonNumber: season.seasonNumber)
                    for episode in seasonDetail.episodes.sorted(by: { $0.episodeNumber < $1.episodeNumber }) {
                        tmdbEpisodesByAbsolute[absoluteIndex] = episode
                        absoluteIndex += 1
                    }
                } catch {
                    Logger.shared.log("AniListService: Failed to fetch TMDB season \(season.seasonNumber): \(error.localizedDescription)", type: "AniList")
                }
            }
        } catch {
            Logger.shared.log("AniListService: Failed to fetch TMDB show details: \(error.localizedDescription)", type: "AniList")
        }
        
        // Build all seasons from AniList structure + TMDB episode details
        var seasons: [AniListSeasonWithPoster] = []
        var currentAbsoluteEpisode = 1
        var seasonIndex = 1
        
        for (currentAnime, seasonOffset, posterUrl) in allAnimeToProcess {
            // Use AniList episode count - this is authoritative
            let anilistEpisodeCount = currentAnime.episodes ?? 0
            
            // Only fall back to remaining TMDB episodes if AniList has no data
            let totalEpisodesInAnime: Int
            if anilistEpisodeCount > 0 {
                totalEpisodesInAnime = anilistEpisodeCount
                Logger.shared.log("AniListService: Season \(seasonIndex) using AniList count: \(totalEpisodesInAnime) episodes", type: "AniList")
            } else {
                let remainingTmdb = max(0, tmdbEpisodesByAbsolute.count - (currentAbsoluteEpisode - 1))
                totalEpisodesInAnime = remainingTmdb > 0 ? remainingTmdb : 12
                Logger.shared.log("AniListService: Season \(seasonIndex) AniList has no count, falling back to: \(totalEpisodesInAnime) episodes (TMDB remaining: \(remainingTmdb))", type: "AniList")
            }
            
            // Each anime (original or sequel) is its own season with episodes numbered from 1
            // Use AniList S/E for service search, but pull metadata from TMDB using absolute index
            let seasonEpisodes: [AniListEpisode] = (0..<totalEpisodesInAnime).map { offset in
                let absoluteEp = currentAbsoluteEpisode + offset
                let localEp = offset + 1
                if let tmdbEp = tmdbEpisodesByAbsolute[absoluteEp] {
                    return AniListEpisode(
                        number: localEp,              // AniList episode (1-12) for search
                        title: tmdbEp.name,           // TMDB metadata
                        description: tmdbEp.overview, // TMDB metadata
                        seasonNumber: seasonIndex,    // AniList season for search
                        stillPath: tmdbEp.stillPath,  // TMDB metadata
                        airDate: tmdbEp.airDate,      // TMDB metadata
                        runtime: tmdbEp.runtime       // TMDB metadata
                    )
                } else {
                    return AniListEpisode(
                        number: localEp,
                        title: "Episode \(localEp)",
                        description: nil,
                        seasonNumber: seasonIndex,
                        stillPath: nil,
                        airDate: nil,
                        runtime: nil
                    )
                }
            }
            
            // Prefer TMDB season poster if available for this season number, otherwise use AniList poster
            let finalPosterUrl: String?
            if let tmdbPoster = tmdbSeasonPosters[seasonIndex] {
                finalPosterUrl = "https://image.tmdb.org/t/p/original" + tmdbPoster
            } else {
                finalPosterUrl = posterUrl
            }
            
            seasons.append(AniListSeasonWithPoster(
                seasonNumber: seasonIndex,
                episodes: seasonEpisodes,
                posterUrl: finalPosterUrl
            ))
            
            currentAbsoluteEpisode += totalEpisodesInAnime
            seasonIndex += 1
        }
        
        let totalEpisodes = seasons.reduce(0) { $0 + $1.episodes.count }
        Logger.shared.log("AniListService: Fetched \(title) with \(totalEpisodes) total episodes grouped into \(seasons.count) seasons", type: "AniList")
        for season in seasons {
            Logger.shared.log("  Season \(season.seasonNumber): \(season.episodes.count) episodes, poster: \(season.posterUrl ?? "none")", type: "AniList")
        }
        
        return AniListAnimeWithSeasons(
            id: anime.id,
            title: title,
            seasons: seasons,
            totalEpisodes: totalEpisodes,
            status: anime.status ?? "UNKNOWN"
        )
    }
    
    // MARK: - Update Watch Progress
    
    func updateAnimeProgress(
        mediaId: Int,
        episodeNumber: Int,
        token: String
    ) async throws {
        let mutation = """
        mutation {
            SaveMediaListEntry(mediaId: \(mediaId), progress: \(episodeNumber)) {
                id
                progress
            }
        }
        """
        
        _ = try await executeGraphQLQuery(mutation, token: token)
    }
    
    // MARK: - Search Anime
    
    func searchAnime(query: String, token: String?) async throws -> [AniListSearchResult] {
        let graphQLQuery = """
        query {
            Page(perPage: 10) {
                media(search: "\(query.replacingOccurrences(of: "\"", with: "\\\""))", type: ANIME, sort: POPULARITY_DESC) {
                    id
                    title {
                        romaji
                        english
                    }
                    episodes
                    coverImage {
                        medium
                    }
                    status
                }
            }
        }
        """
        
        let response = try await executeGraphQLQuery(graphQLQuery, token: token)
        
        struct Response: Codable {
            let data: DataWrapper
            struct DataWrapper: Codable {
                let Page: PageData
                struct PageData: Codable {
                    let media: [AniListAnime]
                }
            }
        }
        
        let result = try JSONDecoder().decode(Response.self, from: response)
        return result.data.Page.media.map { AniListSearchResult(from: $0, preferredLanguageCode: preferredLanguageCode) }
    }

    // MARK: - Catalog Mapping Helpers

    private func mapAniListCatalogToTMDB(_ animeList: [AniListAnime], tmdbService: TMDBService) async -> [TMDBSearchResult] {
        let preferredLang = preferredLanguageCode
        
        return await withTaskGroup(of: TMDBSearchResult?.self) { group in
            for anime in animeList {
                group.addTask {
                    let titleCandidates = AniListTitlePicker.titleCandidates(from: anime.title)
                    for candidate in titleCandidates where !candidate.isEmpty {
                        if let match = try? await tmdbService.searchTVShows(query: candidate).first {
                            return match.asSearchResult
                        }
                    }
                    // Skip entries without a TMDB match to avoid invalid IDs downstream
                    return nil
                }
            }

            var results: [TMDBSearchResult] = []
            var seenIds = Set<Int>()
            for await match in group {
                if let match = match, !seenIds.contains(match.id) {
                    seenIds.insert(match.id)
                    results.append(match)
                }
            }
            return results
        }
    }
    
    // MARK: - MAL ID to AniList ID Conversion
    
    /// Convert MyAnimeList ID to AniList ID for tracking purposes
    func getAniListId(fromMalId malId: Int) async throws -> Int? {
        let query = """
        query {
            Media(idMal: \(malId), type: ANIME) {
                id
            }
        }
        """
        
        struct Response: Codable {
            let data: DataWrapper?
            struct DataWrapper: Codable {
                let Media: MediaData?
                struct MediaData: Codable {
                    let id: Int
                }
            }
        }
        
        do {
            let data = try await executeGraphQLQuery(query, token: nil)
            let result = try JSONDecoder().decode(Response.self, from: data)
            return result.data?.Media?.id
        } catch {
            Logger.shared.log("AniListService: Failed to convert MAL ID \(malId) to AniList ID: \(error.localizedDescription)", type: "AniList")
            return nil
        }
    }
    
    // MARK: - Private Helpers
    
    private func executeGraphQLQuery(_ query: String, token: String?) async throws -> Data {
        var request = URLRequest(url: graphQLEndpoint)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        
        if let token = token {
            request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        }
        
        let body: [String: Any] = ["query": query]
        request.httpBody = try JSONSerialization.data(withJSONObject: body)
        
        let (data, response) = try await URLSession.shared.data(for: request)
        
        guard (response as? HTTPURLResponse)?.statusCode == 200 else {
            throw NSError(domain: "AniList", code: -1, userInfo: [NSLocalizedDescriptionKey: "Failed to fetch from AniList"])
        }
        
        return data
    }

    /// Fetch a single anime node with relations for deeper traversal
    private func fetchAniListAnimeNode(id: Int) async throws -> AniListAnime {
        let query = """
        query {
            Media(id: \(id), type: ANIME) {
                id
                title { romaji english native }
                episodes
                status
                seasonYear
                season
                format
                type
                coverImage { large medium }
                relations {
                    edges {
                        relationType
                        node {
                            id
                            title { romaji english native }
                            episodes
                            status
                            seasonYear
                            season
                            format
                            type
                            coverImage { large medium }
                        }
                    }
                }
            }
        }
        """

        struct Response: Codable {
            let data: DataWrapper
            struct DataWrapper: Codable {
                let Media: AniListAnime
            }
        }

        let data = try await executeGraphQLQuery(query, token: nil)
        let decoded = try JSONDecoder().decode(Response.self, from: data)
        return decoded.data.Media
    }

    /// Search for a TV/TV_SHORT anime by title, preferring those formats
    private func fetchAniListAnimeBySearch(_ title: String, formats: [String]) async throws -> AniListAnime? {
        let formatList = formats.map { "\"\($0)\"" }.joined(separator: ",")
        let query = """
        query {
            Page(perPage: 10) {
                media(search: \"\(title.replacingOccurrences(of: "\"", with: "\\\""))\", type: ANIME, format_in: [\(formatList)], sort: POPULARITY_DESC) {
                    id
                    title { romaji english native }
                    episodes
                    status
                    seasonYear
                    season
                    format
                    type
                    coverImage { large medium }
                    relations {
                        edges {
                            relationType
                            node {
                                id
                                title { romaji english native }
                                episodes
                                status
                                seasonYear
                                season
                                format
                                type
                                coverImage { large medium }
                            }
                        }
                    }
                }
            }
        }
        """

        struct Response: Codable {
            let data: DataWrapper
            struct DataWrapper: Codable {
                let Page: PageData
                struct PageData: Codable {
                    let media: [AniListAnime]
                }
            }
        }

        let data = try await executeGraphQLQuery(query, token: nil)
        let decoded = try JSONDecoder().decode(Response.self, from: data)
        
        // Log all found results for debugging
        Logger.shared.log("AniListService: TV search found \(decoded.data.Page.media.count) results", type: "AniList")
        for (idx, result) in decoded.data.Page.media.prefix(3).enumerated() {
            let resultTitle = AniListTitlePicker.title(from: result.title, preferredLanguageCode: preferredLanguageCode)
            Logger.shared.log("  [\(idx+1)] ID: \(result.id), Format: \(result.format ?? "nil"), Episodes: \(result.episodes ?? 0), Title: \(resultTitle)", type: "AniList")
        }
        
        return decoded.data.Page.media.first
    }
}

// MARK: - Helper Models

protocol AniListEpisodeProtocol {
    var number: Int { get }
    var title: String { get }
    var description: String? { get }
    var seasonNumber: Int { get }
}

struct AniListEpisode: AniListEpisodeProtocol {
    let number: Int                // AniList local episode number (1-12 per season) - used for search
    let title: String
    let description: String?
    let seasonNumber: Int          // AniList season number - used for search
    let stillPath: String?         // From TMDB for metadata
    let airDate: String?
    let runtime: Int?
}

struct AniListSeasonWithPoster {
    let seasonNumber: Int
    let episodes: [AniListEpisode]
    let posterUrl: String?
}

struct AniListAnimeWithSeasons {
    let id: Int
    let title: String
    let seasons: [AniListSeasonWithPoster]
    let totalEpisodes: Int
    let status: String
}

struct AniListAnimeWithEpisodes {
    let id: Int
    let title: String
    let episodes: [AniListEpisode]
    let totalEpisodes: Int
    let status: String
}

struct AniListAnimeDetails {
    let id: Int
    let title: String
    let episodes: Int?
    let status: String

    init(from anime: AniListAnime, preferredLanguageCode: String) {
        self.id = anime.id
        self.title = AniListTitlePicker.title(from: anime.title, preferredLanguageCode: preferredLanguageCode)
        self.episodes = anime.episodes
        self.status = ""
    }
}

struct AniListSearchResult {
    let id: Int
    let title: String
    let episodes: Int?
    let coverImage: String?

    init(from anime: AniListAnime, preferredLanguageCode: String) {
        self.id = anime.id
        self.title = AniListTitlePicker.title(from: anime.title, preferredLanguageCode: preferredLanguageCode)
        self.episodes = anime.episodes
        self.coverImage = nil
    }
}

enum AniListTitlePicker {
    static func title(from title: AniListAnime.AniListTitle, preferredLanguageCode: String) -> String {
        let lang = preferredLanguageCode.lowercased()

        if lang.hasPrefix("en"), let english = title.english, !english.isEmpty {
            return english
        }

        if lang.hasPrefix("ja"), let native = title.native, !native.isEmpty {
            return native
        }

        if let english = title.english, !english.isEmpty {
            return english
        }

        if let romaji = title.romaji, !romaji.isEmpty {
            return romaji
        }

        if let native = title.native, !native.isEmpty {
            return native
        }

        return "Unknown"
    }

    static func titleCandidates(from title: AniListAnime.AniListTitle) -> [String] {
        var seen = Set<String>()
        let ordered = [title.english, title.romaji, title.native].compactMap { $0 }
        return ordered.filter { value in
            if seen.contains(value) { return false }
            seen.insert(value)
            return true
        }
    }
}
