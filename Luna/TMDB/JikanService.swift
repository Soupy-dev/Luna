//
//  JikanService.swift
//  Luna
//
//  Created by Soupy-dev
//

import Foundation

class JikanService {
    static let shared = JikanService()
    
    private let baseURL = "https://api.jikan.moe/v4"

    // In-memory caches to avoid repeated lookups
    private var tmdbToMalCache: [Int: Int] = [:]
    private let cacheQueue = DispatchQueue(label: "JikanService.cache")
    
    enum JikanCatalogKind {
        case trending
        case popular
        case topRated
        case airing
        case upcoming
    }
    
    // MARK: - Catalog Fetching
    
    /// Fetch anime catalog from Jikan (MyAnimeList)
    func fetchAnimeCatalog(_ kind: JikanCatalogKind, limit: Int = 50) async throws -> [TMDBSearchResult] {
        let endpoint: String
        
        switch kind {
        case .trending, .popular:
            // Use top anime sorted by popularity
            endpoint = "/top/anime?filter=bypopularity&limit=\(limit)"
        case .topRated:
            // Use top anime sorted by score
            endpoint = "/top/anime?limit=\(limit)"
        case .airing:
            // Currently airing anime this season
            endpoint = "/seasons/now?limit=\(limit)"
        case .upcoming:
            // Upcoming anime
            endpoint = "/seasons/upcoming?limit=\(limit)"
        }
        
        guard let url = URL(string: baseURL + endpoint) else {
            throw NSError(domain: "JikanService", code: -1, userInfo: [NSLocalizedDescriptionKey: "Invalid URL"])
        }
        
        let (data, response) = try await URLSession.shared.data(from: url)
        
        guard (response as? HTTPURLResponse)?.statusCode == 200 else {
            throw NSError(domain: "JikanService", code: -1, userInfo: [NSLocalizedDescriptionKey: "Failed to fetch from Jikan"])
        }
        
        let decoder = JSONDecoder()
        decoder.keyDecodingStrategy = .convertFromSnakeCase
        
        let catalogResponse = try decoder.decode(JikanCatalogResponse.self, from: data)
        
        // Convert Jikan anime to TMDBSearchResult format
        return catalogResponse.data.map { anime in
            TMDBSearchResult(
                id: anime.malId,
                mediaType: "tv",
                title: anime.title,
                name: anime.title,
                overview: anime.synopsis,
                posterPath: anime.images.jpg.largeImageUrl ?? anime.images.jpg.imageUrl,
                backdropPath: nil,
                releaseDate: anime.aired?.from,
                firstAirDate: anime.aired?.from,
                voteAverage: anime.score,
                popularity: Double(anime.popularity ?? 0),
                adult: nil,
                genreIds: anime.genres?.map { $0.malId }
            )
        }
    }
    
    // MARK: - Anime Details with Episodes
    
    /// Fetch full anime details including all episodes from Jikan
    func fetchAnimeDetailsWithEpisodes(malId: Int) async throws -> JikanAnimeWithEpisodes {
        // Fetch anime details
        guard let detailURL = URL(string: "\(baseURL)/anime/\(malId)/full") else {
            throw NSError(domain: "JikanService", code: -1, userInfo: [NSLocalizedDescriptionKey: "Invalid URL"])
        }
        
        let (detailData, detailResponse) = try await URLSession.shared.data(from: detailURL)
        
        guard (detailResponse as? HTTPURLResponse)?.statusCode == 200 else {
            throw NSError(domain: "JikanService", code: -1, userInfo: [NSLocalizedDescriptionKey: "Failed to fetch anime details"])
        }
        
        let decoder = JSONDecoder()
        decoder.keyDecodingStrategy = .convertFromSnakeCase
        
        let detailResult = try decoder.decode(JikanAnimeDetailResponse.self, from: detailData)
        let anime = detailResult.data
        
        Logger.shared.log("JikanService: Fetched \(anime.title) with \(anime.episodes ?? 0) episodes", type: "Jikan")
        
        // Fetch episodes (Jikan paginates episodes, 100 per page)
        var allEpisodes: [JikanEpisode] = []
        var page = 1
        var hasMorePages = true
        
        while hasMorePages && allEpisodes.count < (anime.episodes ?? 0) {
            guard let episodeURL = URL(string: "\(baseURL)/anime/\(malId)/episodes?page=\(page)") else { break }
            
            do {
                let (episodeData, episodeResponse) = try await URLSession.shared.data(from: episodeURL)
                
                guard (episodeResponse as? HTTPURLResponse)?.statusCode == 200 else { break }
                
                let episodeResult = try decoder.decode(JikanEpisodeResponse.self, from: episodeData)
                allEpisodes.append(contentsOf: episodeResult.data)
                
                hasMorePages = episodeResult.pagination.hasNextPage
                page += 1
                
                // Rate limiting - Jikan has strict limits
                if hasMorePages {
                    try await Task.sleep(nanoseconds: 500_000_000) // 0.5 second delay
                }
            } catch {
                Logger.shared.log("JikanService: Failed to fetch episodes page \(page): \(error.localizedDescription)", type: "Jikan")
                break
            }
        }
        
        Logger.shared.log("JikanService: Loaded \(allEpisodes.count) episodes for \(anime.title)", type: "Jikan")
        
        return JikanAnimeWithEpisodes(
            malId: anime.malId,
            title: anime.title,
            titleEnglish: anime.titleEnglish,
            episodes: allEpisodes,
            totalEpisodes: anime.episodes ?? allEpisodes.count,
            status: anime.status,
            posterUrl: anime.images.jpg.largeImageUrl ?? anime.images.jpg.imageUrl,
            synopsis: anime.synopsis
        )
    }
    
    // MARK: - Search
    
    /// Search for anime on Jikan (MyAnimeList)
    func searchAnime(query: String) async throws -> [TMDBSearchResult] {
        let encodedQuery = query.addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed) ?? query
        
        guard let url = URL(string: "\(baseURL)/anime?q=\(encodedQuery)&limit=20") else {
            throw NSError(domain: "JikanService", code: -1, userInfo: [NSLocalizedDescriptionKey: "Invalid URL"])
        }
        
        let (data, response) = try await URLSession.shared.data(from: url)
        
        guard (response as? HTTPURLResponse)?.statusCode == 200 else {
            throw NSError(domain: "JikanService", code: -1, userInfo: [NSLocalizedDescriptionKey: "Failed to search on Jikan"])
        }
        
        let decoder = JSONDecoder()
        decoder.keyDecodingStrategy = .convertFromSnakeCase
        
        let searchResponse = try decoder.decode(JikanCatalogResponse.self, from: data)
        
        return searchResponse.data.map { anime in
            TMDBSearchResult(
                id: anime.malId,
                mediaType: "tv",
                title: anime.title,
                name: anime.title,
                overview: anime.synopsis,
                posterPath: anime.images.jpg.largeImageUrl ?? anime.images.jpg.imageUrl,
                backdropPath: nil,
                releaseDate: anime.aired?.from,
                firstAirDate: anime.aired?.from,
                voteAverage: anime.score,
                popularity: Double(anime.popularity ?? 0),
                adult: nil,
                genreIds: anime.genres?.map { $0.malId }
            )
        }
    }

    // MARK: - Find Anime by Title
    
    /// Find anime by title (and year, if available) and return the best match with episodes
    func findAnimeByTitle(_ title: String, year: Int?, tmdbId: Int?) async throws -> JikanAnimeWithEpisodes? {
        Logger.shared.log("JikanService: Searching for anime: \(title)\(year.map { " (\($0))" } ?? "")", type: "Jikan")

        // If we have a cached MAL ID for this TMDB ID, use it directly
        if let tmdbId = tmdbId, let cachedMal = cacheQueue.sync(execute: { tmdbToMalCache[tmdbId] }) {
            Logger.shared.log("JikanService: Using cached MAL ID \(cachedMal) for TMDB ID \(tmdbId)", type: "Jikan")
            return try await fetchAnimeDetailsWithEpisodes(malId: cachedMal)
        }

        // Search for the anime
        let results = try await searchAnime(query: title)
        
        guard !results.isEmpty else {
            Logger.shared.log("JikanService: No anime found for: \(title)", type: "Jikan")
            return nil
        }

        // Pick best candidate by year proximity then score/popularity
        let best = pickBestMatch(from: results, targetYear: year)
        Logger.shared.log("JikanService: Selected anime: \(best.title ?? "Unknown") (MAL ID: \(best.id))", type: "Jikan")

        // Cache mapping
        if let tmdbId = tmdbId {
            cacheQueue.sync { tmdbToMalCache[tmdbId] = best.id }
        }

        // Fetch full details with episodes
        return try await fetchAnimeDetailsWithEpisodes(malId: best.id)
    }

    private func pickBestMatch(from results: [TMDBSearchResult], targetYear: Int?) -> TMDBSearchResult {
        guard let targetYear = targetYear else {
            // No year — pick highest score then popularity
            return results.sorted { (lhs, rhs) in
                (lhs.voteAverage ?? 0, lhs.popularity) > (rhs.voteAverage ?? 0, rhs.popularity)
            }.first ?? results[0]
        }

        // Rank by year distance, then score, then popularity
        return results.sorted { lhs, rhs in
            let ly = year(from: lhs.firstAirDate ?? lhs.releaseDate)
            let ry = year(from: rhs.firstAirDate ?? rhs.releaseDate)
            let ldist = ly.map { abs($0 - targetYear) } ?? Int.max
            let rdist = ry.map { abs($0 - targetYear) } ?? Int.max
            if ldist != rdist { return ldist < rdist }
            if (lhs.voteAverage ?? 0) != (rhs.voteAverage ?? 0) {
                return (lhs.voteAverage ?? 0) > (rhs.voteAverage ?? 0)
            }
            return lhs.popularity > rhs.popularity
        }.first ?? results[0]
    }

    private func year(from dateString: String?) -> Int? {
        guard let dateString = dateString, dateString.count >= 4 else { return nil }
        if let y = Int(dateString.prefix(4)) { return y }
        return nil
    }
}

// MARK: - Jikan Response Models

struct JikanAnimeDetailResponse: Codable {
    let data: JikanAnimeDetail
}

struct JikanEpisodeResponse: Codable {
    let data: [JikanEpisode]
    let pagination: JikanPagination
}

struct JikanPagination: Codable {
    let hasNextPage: Bool
}

struct JikanAnime: Codable {
    let malId: Int
    let title: String
    let titleEnglish: String?
    let synopsis: String?
    let episodes: Int?
    let status: String
    let score: Double?
    let popularity: Int?
    let images: JikanImages
    let aired: JikanAired?
    let genres: [JikanGenre]?
}

struct JikanAnimeDetail: Codable {
    let malId: Int
    let title: String
    let titleEnglish: String?
    let synopsis: String?
    let episodes: Int?
    let status: String
    let score: Double?
    let images: JikanImages
    let aired: JikanAired?
    let relations: [JikanRelation]?
}

struct JikanImages: Codable {
    let jpg: JikanImageSet
}

struct JikanImageSet: Codable {
    let imageUrl: String
    let largeImageUrl: String?
}

struct JikanAired: Codable {
    let from: String?
    let to: String?
}

struct JikanGenre: Codable {
    let malId: Int
    let name: String
}

struct JikanRelation: Codable {
    let relation: String
    let entry: [JikanRelationEntry]
}

struct JikanRelationEntry: Codable {
    let malId: Int
    let type: String
    let name: String
}

struct JikanEpisode: Codable {
    let malId: Int
    let title: String?
    let titleJapanese: String?
    let titleRomanji: String?
    let aired: String?
    let score: Double?
    let filler: Bool?
    let recap: Bool?
}

// MARK: - Converted Models

struct JikanAnimeWithEpisodes {
    let malId: Int
    let title: String
    let titleEnglish: String?
    let episodes: [JikanEpisode]
    let totalEpisodes: Int
    let status: String
    let posterUrl: String?
    let synopsis: String?
}
