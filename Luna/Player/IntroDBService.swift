//
//  IntroDBService.swift
//  Luna
//
//  Created on 28/02/26.
//

import Foundation

// MARK: - TheIntroDB API Response Models

private struct IntroDBResponse: Codable {
    let tmdb_id: Int?
    let type: String?
    let intro: [IntroDBSegment]?
    let recap: [IntroDBSegment]?
    let credits: [IntroDBSegment]?
    let preview: [IntroDBSegment]?
}

private struct IntroDBSegment: Codable {
    let start_ms: Int?
    let end_ms: Int?
    let confidence: Double?
    let submission_count: Int?
}

// MARK: - TheIntroDB Service

final class IntroDBService {
    static let shared = IntroDBService()

    private let baseURL = "https://api.theintrodb.org/v2"
    private let session: URLSession

    private init() {
        let config = URLSessionConfiguration.default
        config.timeoutIntervalForRequest = 10
        config.timeoutIntervalForResource = 15
        self.session = URLSession(configuration: config)
    }

    /// Fetches skip-time segments from TheIntroDB using TMDB ID.
    /// - Parameters:
    ///   - tmdbId: The TMDB ID of the movie or TV show.
    ///   - seasonNumber: Season number (nil for movies).
    ///   - episodeNumber: Episode number (nil for movies).
    ///   - episodeDuration: The total duration in seconds (used for clamping and null end times).
    /// - Returns: Array of skip segments (intro, outro/credits, recap, preview).
    func fetchSkipTimes(tmdbId: Int, seasonNumber: Int?, episodeNumber: Int?, episodeDuration: Double) async throws -> [SkipSegment] {
        var urlString = "\(baseURL)/media?tmdb_id=\(tmdbId)"
        if let season = seasonNumber {
            urlString += "&season=\(season)"
        }
        if let episode = episodeNumber {
            urlString += "&episode=\(episode)"
        }

        guard let url = URL(string: urlString) else {
            Logger.shared.log("IntroDBService: Invalid URL: \(urlString)", type: "Error")
            return []
        }

        Logger.shared.log("IntroDBService: Fetching skip times for tmdbId=\(tmdbId) s=\(seasonNumber ?? -1) ep=\(episodeNumber ?? -1)", type: "IntroDB")

        let (data, response) = try await session.data(from: url)

        guard let httpResponse = response as? HTTPURLResponse else {
            Logger.shared.log("IntroDBService: Non-HTTP response", type: "Error")
            return []
        }

        guard httpResponse.statusCode == 200 else {
            Logger.shared.log("IntroDBService: HTTP \(httpResponse.statusCode) for tmdbId=\(tmdbId)", type: "IntroDB")
            return []
        }

        let decoded = try JSONDecoder().decode(IntroDBResponse.self, from: data)

        var segments: [SkipSegment] = []
        let maxDuration = episodeDuration > 0 ? episodeDuration : Double.greatestFiniteMagnitude

        // Parse intro segments
        if let intros = decoded.intro {
            for seg in intros {
                if let parsed = parseSegment(seg, type: .intro, maxDuration: maxDuration) {
                    segments.append(parsed)
                }
            }
        }

        // Parse recap segments
        if let recaps = decoded.recap {
            for seg in recaps {
                if let parsed = parseSegment(seg, type: .recap, maxDuration: maxDuration) {
                    segments.append(parsed)
                }
            }
        }

        // Parse credits → map to .outro (functionally equivalent — "Skip Outro")
        if let credits = decoded.credits {
            for seg in credits {
                if let parsed = parseSegment(seg, type: .outro, maxDuration: maxDuration) {
                    segments.append(parsed)
                }
            }
        }

        // Parse preview segments
        if let previews = decoded.preview {
            for seg in previews {
                if let parsed = parseSegment(seg, type: .preview, maxDuration: maxDuration) {
                    segments.append(parsed)
                }
            }
        }

        Logger.shared.log(
            "IntroDBService: Found \(segments.count) skip segments for tmdbId=\(tmdbId): "
            + segments.map { "\($0.type.rawValue) \(Int($0.startTime))-\(Int($0.endTime))s" }.joined(separator: ", "),
            type: "IntroDB"
        )

        return segments
    }

    /// Converts an IntroDB segment (milliseconds, nullable) into a SkipSegment (seconds).
    private func parseSegment(_ seg: IntroDBSegment, type: SkipType, maxDuration: Double) -> SkipSegment? {
        let startSec = seg.start_ms.map { Double($0) / 1000.0 } ?? 0
        let endSec = seg.end_ms.map { Double($0) / 1000.0 } ?? maxDuration

        let clampedStart = max(0, startSec)
        let clampedEnd = min(maxDuration, endSec)
        guard clampedEnd > clampedStart else { return nil }

        return SkipSegment(startTime: clampedStart, endTime: clampedEnd, type: type)
    }
}
