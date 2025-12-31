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
    
    /// Fetch anime episodes and details from AniList instead of TMDB
    func fetchAnimeDetails(title: String, token: String?) async throws -> AniListAnimeDetails {
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
                nextAiringEpisode {
                    episode
                    airingAt
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
        return AniListAnimeDetails(from: result.data.Media, preferredLanguageCode: preferredLanguageCode)
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
