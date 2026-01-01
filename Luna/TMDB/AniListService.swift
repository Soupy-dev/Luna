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
                            type
                            coverImage {
                                large
                                medium
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
        let anime = result.data.Media
        let title = AniListTitlePicker.title(from: anime.title, preferredLanguageCode: preferredLanguageCode)
        
        Logger.shared.log("AniListService: Raw response - episodes: \(anime.episodes ?? 0), seasonYear: \(anime.seasonYear ?? 0), season: \(anime.season ?? "UNKNOWN")", type: "AniList")
        
        // Collect all anime to process (original + sequels with their posters)
        var allAnimeToProcess: [(anime: AniListAnime, seasonOffset: Int, posterUrl: String?)] = [
            (anime, 0, anime.coverImage?.large ?? anime.coverImage?.medium ?? tmdbShowPoster)
        ]
        
        // Find and add sequels
        if let relations = anime.relations {
            for edge in relations.edges {
                if edge.relationType == "SEQUEL", edge.node.type == "ANIME" {
                    Logger.shared.log("AniListService: Found sequel: \(AniListTitlePicker.title(from: edge.node.title, preferredLanguageCode: preferredLanguageCode))", type: "AniList")
                    // Calculate season offset based on previous anime episode counts
                    let currentSeasonOffset = allAnimeToProcess.reduce(0) { acc, item in
                        let episodeCount = item.anime.episodes ?? 12
                        let episodesPerSeason = 12
                        return acc + ((episodeCount + episodesPerSeason - 1) / episodesPerSeason)
                    }
                    let sequelPoster = edge.node.coverImage?.large ?? edge.node.coverImage?.medium
                    allAnimeToProcess.append((edge.node, currentSeasonOffset, sequelPoster))
                }
            }
        }
        
        // Fetch all TMDB season data (excluding Season 0 specials)
        var allTmdbEpisodes: [Int: TMDBEpisode] = [:]
        do {
            let tvShowDetail = try await tmdbService.getTVShowWithSeasons(id: tmdbShowId)
            
            // Fetch details for each real season (skip season 0)
            for season in tvShowDetail.seasons where season.seasonNumber > 0 {
                do {
                    let seasonDetail = try await tmdbService.getSeasonDetails(tvShowId: tmdbShowId, seasonNumber: season.seasonNumber)
                    for episode in seasonDetail.episodes {
                        allTmdbEpisodes[episode.episodeNumber] = episode
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
        var currentEpisodeNumber = 1
        var seasonIndex = 1
        
        for (currentAnime, seasonOffset, posterUrl) in allAnimeToProcess {
            let totalEpisodesInAnime = currentAnime.episodes ?? 12
            Logger.shared.log("AniListService: Processing anime with \(totalEpisodesInAnime) episodes, season offset: \(seasonOffset), poster: \(posterUrl ?? "none")", type: "AniList")
            
            // Each anime (original or sequel) is its own season with all its episodes
            let seasonEpisodes: [AniListEpisode] = (0..<totalEpisodesInAnime).map { offset in
                let epNum = currentEpisodeNumber + offset
                if let tmdbEp = allTmdbEpisodes[epNum] {
                    return AniListEpisode(
                        number: epNum,
                        title: tmdbEp.name,
                        description: tmdbEp.overview,
                        seasonNumber: seasonIndex,
                        stillPath: tmdbEp.stillPath,
                        airDate: tmdbEp.airDate,
                        runtime: tmdbEp.runtime
                    )
                } else {
                    return AniListEpisode(
                        number: epNum,
                        title: "Episode \(epNum)",
                        description: nil,
                        seasonNumber: seasonIndex,
                        stillPath: nil,
                        airDate: nil,
                        runtime: nil
                    )
                }
            }
            
            seasons.append(AniListSeasonWithPoster(
                seasonNumber: seasonIndex,
                episodes: seasonEpisodes,
                posterUrl: posterUrl
            ))
            
            currentEpisodeNumber += totalEpisodesInAnime
            seasonIndex += 1
        }
        
        let totalEpisodes = allAnimeToProcess.reduce(0) { $0 + ($1.anime.episodes ?? 12) }
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
        await withTaskGroup(of: (TMDBSearchResult?, AniListAnime).self) { group in
            for anime in animeList {
                group.addTask {
                    let titleCandidates = AniListTitlePicker.titleCandidates(from: anime.title)
                    for candidate in titleCandidates where !candidate.isEmpty {
                        if let match = try? await tmdbService.searchTVShows(query: candidate).first {
                            return (match.asSearchResult, anime)
                        }
                    }
                    // Fallback: return AniList data as TMDBSearchResult when no TMDB match found
                    let title = AniListTitlePicker.title(from: anime.title, preferredLanguageCode: preferredLanguageCode)
                    let posterPath = anime.coverImage?.large ?? anime.coverImage?.medium
                    let fallback = TMDBSearchResult(
                        id: anime.id,
                        title: title,
                        overview: nil,
                        posterPath: posterPath,
                        backdropPath: nil,
                        releaseDate: nil,
                        mediaType: .tv,
                        voteAverage: 0,
                        voteCount: 0
                    )
                    return (fallback, anime)
                }
            }

            var results: [TMDBSearchResult] = []
            var seenIds = Set<Int>()
            for await (match, _) in group {
                if let match = match, !seenIds.contains(match.id) {
                    seenIds.insert(match.id)
                    results.append(match)
                }
            }
            return results
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
}

// MARK: - Helper Models

protocol AniListEpisodeProtocol {
    var number: Int { get }
    var title: String { get }
    var description: String? { get }
    var seasonNumber: Int { get }
}

struct AniListEpisode: AniListEpisodeProtocol {
    let number: Int
    let title: String
    let description: String?
    let seasonNumber: Int
    let stillPath: String?
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
