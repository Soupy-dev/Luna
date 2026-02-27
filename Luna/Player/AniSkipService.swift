//
//  AniSkipService.swift
//  Luna
//
//  Created on 27/02/26.
//

import Foundation

// MARK: - Skip Segment Models

enum SkipType: String, Codable {
    case intro
    case outro
    case recap

    var displayLabel: String {
        switch self {
        case .intro: return "Skip Intro"
        case .outro: return "Skip Outro"
        case .recap: return "Skip Recap"
        }
    }
}

struct SkipSegment {
    let startTime: Double
    let endTime: Double
    let type: SkipType

    /// Unique key used to track whether this segment has already been auto-skipped.
    var uniqueKey: String { "\(type.rawValue)_\(Int(startTime))" }
}

// MARK: - AniSkip API Response Models

private struct AniSkipResponse: Codable {
    let found: Bool
    let results: [AniSkipResult]?
    let statusCode: Int
}

private struct AniSkipResult: Codable {
    let interval: AniSkipInterval
    let skipType: String
    let skipId: String
    let episodeLength: Double
}

private struct AniSkipInterval: Codable {
    let startTime: Double
    let endTime: Double
}

// MARK: - AniSkip Service

final class AniSkipService {
    static let shared = AniSkipService()

    private let baseURL = "https://api.aniskip.com/v2"
    private let session: URLSession

    private init() {
        let config = URLSessionConfiguration.default
        config.timeoutIntervalForRequest = 10
        config.timeoutIntervalForResource = 15
        self.session = URLSession(configuration: config)
    }

    /// Fetches skip-time segments for an anime episode using AniList ID.
    /// - Parameters:
    ///   - anilistId: The AniList media ID for the specific season / anime.
    ///   - episodeNumber: The episode number within that season.
    ///   - episodeDuration: The total duration in seconds (used for better matching).
    /// - Returns: Array of skip segments (intro, outro, recap).
    func fetchSkipTimes(anilistId: Int, episodeNumber: Int, episodeDuration: Double) async throws -> [SkipSegment] {
        let durationParam = episodeDuration > 0 ? "&episodeLength=\(Int(episodeDuration))" : ""
        let urlString = "\(baseURL)/skip-times/\(anilistId)/\(episodeNumber)?types[]=op&types[]=ed&types[]=recap&types[]=mixed-op&types[]=mixed-ed\(durationParam)"

        guard let url = URL(string: urlString) else {
            Logger.shared.log("AniSkipService: Invalid URL: \(urlString)", type: "Error")
            return []
        }

        Logger.shared.log("AniSkipService: Fetching skip times for anilistId=\(anilistId) ep=\(episodeNumber) duration=\(Int(episodeDuration))", type: "AniSkip")

        let (data, response) = try await session.data(from: url)

        guard let httpResponse = response as? HTTPURLResponse else {
            Logger.shared.log("AniSkipService: Non-HTTP response", type: "Error")
            return []
        }

        guard httpResponse.statusCode == 200 else {
            Logger.shared.log("AniSkipService: HTTP \(httpResponse.statusCode) for anilistId=\(anilistId) ep=\(episodeNumber)", type: "AniSkip")
            return []
        }

        let decoded = try JSONDecoder().decode(AniSkipResponse.self, from: data)

        guard decoded.found, let results = decoded.results else {
            Logger.shared.log("AniSkipService: No skip times found for anilistId=\(anilistId) ep=\(episodeNumber)", type: "AniSkip")
            return []
        }

        let segments = results.compactMap { result -> SkipSegment? in
            let skipType: SkipType
            switch result.skipType {
            case "op", "mixed-op":
                skipType = .intro
            case "ed", "mixed-ed":
                skipType = .outro
            case "recap":
                skipType = .recap
            default:
                return nil
            }

            let start = max(0, result.interval.startTime)
            let end = min(episodeDuration > 0 ? episodeDuration : Double.greatestFiniteMagnitude, result.interval.endTime)
            guard end > start else { return nil }

            return SkipSegment(startTime: start, endTime: end, type: skipType)
        }

        Logger.shared.log(
            "AniSkipService: Found \(segments.count) skip segments for anilistId=\(anilistId) ep=\(episodeNumber): "
            + segments.map { "\($0.type.rawValue) \(Int($0.startTime))-\(Int($0.endTime))s" }.joined(separator: ", "),
            type: "AniSkip"
        )

        return segments
    }
}
