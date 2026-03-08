//
//  StremioClient.swift
//  Luna
//
//  Created by Soupy on 2026.
//

import Foundation

/// HTTP client for the Stremio addon protocol.
/// SAFETY: Only returns streams with direct HTTP(S) URLs. Torrent-only streams are discarded.
final class StremioClient {
    static let shared = StremioClient()

    private let session: URLSession
    private let decoder = JSONDecoder()

    private init() {
        let config = URLSessionConfiguration.default
        config.timeoutIntervalForRequest = 15
        config.timeoutIntervalForResource = 30
        session = URLSession(configuration: config)
    }

    // MARK: - Fetch Manifest

    func fetchManifest(from url: String) async throws -> StremioManifest {
        let manifestURL = normalizeManifestURL(url)
        guard let requestURL = URL(string: manifestURL) else {
            throw StremioError.invalidURL
        }

        let (data, response) = try await session.data(from: requestURL)
        guard let httpResponse = response as? HTTPURLResponse,
              (200...299).contains(httpResponse.statusCode) else {
            throw StremioError.httpError((response as? HTTPURLResponse)?.statusCode ?? 0)
        }

        return try decoder.decode(StremioManifest.self, from: data)
    }

    // MARK: - Fetch Streams

    /// Fetches streams for a given addon and content ID.
    /// **SAFETY**: Only returns streams with direct HTTP(S) URLs. Any torrent-only entry is stripped.
    func fetchStreams(baseURL: String, type: String, id: String) async throws -> [StremioStream] {
        let base = baseURL.hasSuffix("/") ? String(baseURL.dropLast()) : baseURL

        // Remove /manifest.json suffix if present
        let cleanBase: String
        if base.hasSuffix("/manifest.json") {
            cleanBase = String(base.dropLast("/manifest.json".count))
        } else {
            cleanBase = base
        }

        let urlString = "\(cleanBase)/stream/\(type)/\(id).json"
        guard let url = URL(string: urlString) else {
            throw StremioError.invalidURL
        }

        Logger.shared.log("Stremio: Fetching streams from \(urlString)", type: "Stremio")

        let (data, response) = try await session.data(from: url)
        guard let httpResponse = response as? HTTPURLResponse,
              (200...299).contains(httpResponse.statusCode) else {
            throw StremioError.httpError((response as? HTTPURLResponse)?.statusCode ?? 0)
        }

        let streamResponse = try decoder.decode(StremioStreamResponse.self, from: data)
        let allStreams = streamResponse.streams ?? []

        // SAFETY: Filter out any stream that is NOT a direct HTTP(S) link.
        // This ensures NO torrent (infoHash-only) streams ever reach the user.
        let safeStreams = allStreams.filter { $0.isDirectHTTP }

        let dropped = allStreams.count - safeStreams.count
        if dropped > 0 {
            Logger.shared.log("Stremio: Dropped \(dropped) non-HTTP stream(s) (torrent/infoHash only)", type: "Stremio")
        }

        Logger.shared.log("Stremio: Got \(safeStreams.count) safe HTTP stream(s) from \(cleanBase)", type: "Stremio")
        return safeStreams
    }

    // MARK: - Build Stremio Content ID

    /// Builds the Stremio content ID string for a given item.
    /// - Parameters:
    ///   - tmdbId: The TMDB ID
    ///   - imdbId: The IMDB ID (tt-prefixed string), if available
    ///   - type: "movie" or "series"
    ///   - season: Season number (for series only)
    ///   - episode: Episode number (for series only)
    ///   - addon: The addon to build the ID for (checks idPrefixes)
    /// - Returns: Array of possible IDs to try, ordered by preference
    func buildContentIds(tmdbId: Int, imdbId: String?, type: String, season: Int?, episode: Int?, addon: StremioAddon) -> [String] {
        var ids: [String] = []

        let prefixes = addon.manifest.idPrefixes ?? []
        let supportsTMDB = prefixes.isEmpty || prefixes.contains("tmdb") || prefixes.contains("tmdb:")
        let supportsIMDB = prefixes.isEmpty || prefixes.contains("tt")

        // Prefer tmdb: prefix when supported
        if supportsTMDB {
            if type == "series", let s = season, let e = episode {
                ids.append("tmdb:\(tmdbId):\(s):\(e)")
            } else {
                ids.append("tmdb:\(tmdbId)")
            }
        }

        // Fall back to IMDB when available
        if supportsIMDB, let imdb = imdbId, !imdb.isEmpty {
            let ttId = imdb.hasPrefix("tt") ? imdb : "tt\(imdb)"
            if type == "series", let s = season, let e = episode {
                ids.append("\(ttId):\(s):\(e)")
            } else {
                ids.append(ttId)
            }
        }

        return ids
    }

    // MARK: - Helpers

    /// Normalizes a user-provided URL to point to manifest.json
    private func normalizeManifestURL(_ url: String) -> String {
        var cleaned = url.trimmingCharacters(in: .whitespacesAndNewlines)
        if cleaned.hasSuffix("/") { cleaned = String(cleaned.dropLast()) }

        if cleaned.hasSuffix("/manifest.json") {
            return cleaned
        }

        return "\(cleaned)/manifest.json"
    }

    enum StremioError: LocalizedError {
        case invalidURL
        case httpError(Int)
        case noStreams

        var errorDescription: String? {
            switch self {
            case .invalidURL: return "Invalid Stremio addon URL"
            case .httpError(let code): return "HTTP error \(code)"
            case .noStreams: return "No streams available"
            }
        }
    }
}
