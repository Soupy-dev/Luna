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
    
    // MARK: - Fetch Anime Details
    
    /// Fetch full anime details with seasons and episodes from AniList only
    func fetchAnimeDetailsWithEpisodes(title: String, token: String?) async throws -> AniListAnimeWithSeasons {
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
        
        // Collect all anime to process (original + sequels)
        var allAnimeToProcess: [(anime: AniListAnime, seasonOffset: Int)] = [(anime, 0)]
        
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
                    allAnimeToProcess.append((edge.node, currentSeasonOffset))
                }
            }
        }
        
        // Build all seasons from collected anime
        var seasons: [AniListSeason] = []
        var currentEpisodeNumber = 1
        
        for (currentAnime, seasonOffset) in allAnimeToProcess {
            let episodeCount = currentAnime.episodes ?? 12
            Logger.shared.log("AniListService: Processing anime with \(episodeCount) episodes, season offset: \(seasonOffset)", type: "AniList")
            
            // Build episode list for this anime
            let episodesPerSeason = 12
            var episodeIndex = 0
            var seasonNum = seasonOffset + 1
            
            for _ in 1... {
                let endEpisodeNum = min(currentEpisodeNumber + episodesPerSeason - 1, currentEpisodeNumber + (episodeCount - episodeIndex) - 1)
                let episodeCount = endEpisodeNum - currentEpisodeNumber + 1
                
                let seasonEpisodes: [AniListEpisode] = (0..<episodeCount).map { offset in
                    let epNum = currentEpisodeNumber + offset
                    return AniListEpisode(
                        number: epNum,
                        title: "Episode \(epNum)",
                        description: nil,
                        seasonNumber: seasonNum
                    )
                }
                
                if seasonEpisodes.isEmpty { break }
                
                seasons.append(AniListSeason(
                    seasonNumber: seasonNum,
                    episodes: seasonEpisodes
                ))
                
                currentEpisodeNumber += episodeCount
                episodeIndex += episodeCount
                seasonNum += 1
                
                if episodeIndex >= episodeCount {
                    break
                }
            }
        }
        
        let totalEpisodes = allAnimeToProcess.reduce(0) { $0 + ($1.anime.episodes ?? 12) }
        Logger.shared.log("AniListService: Fetched \(title) with \(totalEpisodes) total episodes grouped into \(seasons.count) seasons", type: "AniList")
        for season in seasons {
            Logger.shared.log("  Season \(season.seasonNumber): \(season.episodes.count) episodes", type: "AniList")
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

struct AniListEpisode {
    let number: Int
    let title: String
    let description: String?
    let seasonNumber: Int
}

struct AniListSeason {
    let seasonNumber: Int
    let episodes: [AniListEpisode]
}

struct AniListAnimeWithSeasons {
    let id: Int
    let title: String
    let seasons: [AniListSeason]
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
}
