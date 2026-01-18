//
//  AniSkipService.swift
//  Luna
//
//  AniSkip API integration for automatic intro/outro/recap skipping
//  API Documentation: https://api.aniskip.com/api-docs
//

import Foundation

enum AniSkipType: String, Codable {
    case op = "op"           // Opening
    case ed = "ed"           // Ending
    case recap = "recap"     // Recap
    case mixedOp = "mixed-op" // Mixed opening
    case mixedEd = "mixed-ed" // Mixed ending
    
    var displayName: String {
        switch self {
        case .op, .mixedOp: return "Opening"
        case .ed, .mixedEd: return "Ending"
        case .recap: return "Recap"
        }
    }
}

struct AniSkipSegment: Codable {
    let interval: AniSkipInterval
    let skipType: AniSkipType
    let skipId: String
    let episodeLength: Double
    
    var startTime: Double { interval.startTime }
    var endTime: Double { interval.endTime }
}

struct AniSkipInterval: Codable {
    let startTime: Double
    let endTime: Double
}

struct AniSkipResponse: Codable {
    let found: Bool
    let results: [AniSkipSegment]?
    let message: String?
    let statusCode: Int
}

final class AniSkipService {
    static let shared = AniSkipService()
    
    private let baseURL = "https://api.aniskip.com/v2"
    private let session: URLSession
    
    // Cache for skip times: "anilistId_episodeNumber" -> [AniSkipSegment]
    private var skipCache: [String: [AniSkipSegment]] = [:]
    private let cacheQueue = DispatchQueue(label: "com.luna.aniskip.cache")
    
    private init() {
        let config = URLSessionConfiguration.default
        config.timeoutIntervalForRequest = 10
        config.timeoutIntervalForResource = 15
        self.session = URLSession(configuration: config)
    }
    
    /// Fetch skip times for a specific anime episode
    /// - Parameters:
    ///   - anilistId: The AniList ID of the anime
    ///   - episodeNumber: The episode number (1-based)
    ///   - episodeLength: Optional episode length in seconds for validation
    /// - Returns: Array of skip segments, or empty array if none found
    func fetchSkipTimes(
        anilistId: Int,
        episodeNumber: Int,
        episodeLength: Double? = nil
    ) async throws -> [AniSkipSegment] {
        // Check cache first
        let cacheKey = "\(anilistId)_\(episodeNumber)"
        if let cached = getCachedSkipTimes(for: cacheKey) {
            Logger.shared.log("[AniSkip] Cache hit for \(cacheKey)", type: "AniSkip")
            return cached
        }
        
        // Build URL: /v2/skip-times/{anilist_id}/{episode_number}
        var urlString = "\(baseURL)/skip-times/\(anilistId)/\(episodeNumber)"
        
        // Add optional query parameters
        var queryItems: [URLQueryItem] = []
        queryItems.append(URLQueryItem(name: "types", value: "op,ed,recap,mixed-op,mixed-ed"))
        
        if let length = episodeLength {
            queryItems.append(URLQueryItem(name: "episodeLength", value: String(Int(length))))
        }
        
        if !queryItems.isEmpty {
            var components = URLComponents(string: urlString)!
            components.queryItems = queryItems
            urlString = components.url?.absoluteString ?? urlString
        }
        
        guard let url = URL(string: urlString) else {
            Logger.shared.log("[AniSkip] Invalid URL: \(urlString)", type: "Error")
            return []
        }
        
        Logger.shared.log("[AniSkip] Fetching skip times: \(url.absoluteString)", type: "AniSkip")
        
        var request = URLRequest(url: url)
        request.httpMethod = "GET"
        request.setValue("application/json", forHTTPHeaderField: "Accept")
        
        do {
            let (data, response) = try await session.data(for: request)
            
            guard let httpResponse = response as? HTTPURLResponse else {
                Logger.shared.log("[AniSkip] Invalid response type", type: "Error")
                return []
            }
            
            Logger.shared.log("[AniSkip] Response status: \(httpResponse.statusCode)", type: "AniSkip")
            
            // Handle different status codes
            if httpResponse.statusCode == 404 {
                // No skip times found for this episode
                Logger.shared.log("[AniSkip] No skip times found for AniList ID \(anilistId) Episode \(episodeNumber)", type: "AniSkip")
                cacheSkipTimes([], for: cacheKey)
                return []
            }
            
            guard httpResponse.statusCode == 200 else {
                Logger.shared.log("[AniSkip] Unexpected status code: \(httpResponse.statusCode)", type: "Error")
                return []
            }
            
            let decoder = JSONDecoder()
            let skipResponse = try decoder.decode(AniSkipResponse.self, from: data)
            
            if !skipResponse.found || skipResponse.results == nil {
                Logger.shared.log("[AniSkip] No results found in response", type: "AniSkip")
                cacheSkipTimes([], for: cacheKey)
                return []
            }
            
            let segments = skipResponse.results ?? []
            Logger.shared.log("[AniSkip] Found \(segments.count) skip segments", type: "AniSkip")
            
            for segment in segments {
                Logger.shared.log("[AniSkip] - \(segment.skipType.displayName): \(segment.startTime)s - \(segment.endTime)s", type: "AniSkip")
            }
            
            // Cache the results
            cacheSkipTimes(segments, for: cacheKey)
            
            return segments
            
        } catch let error as DecodingError {
            Logger.shared.log("[AniSkip] Decoding error: \(error)", type: "Error")
            return []
        } catch {
            Logger.shared.log("[AniSkip] Network error: \(error.localizedDescription)", type: "Error")
            return []
        }
    }
    
    /// Check if the current playback position is within any skip segment
    /// - Parameters:
    ///   - position: Current playback position in seconds
    ///   - segments: Array of skip segments
    /// - Returns: The active skip segment if position is within one, nil otherwise
    func activeSkipSegment(at position: Double, in segments: [AniSkipSegment]) -> AniSkipSegment? {
        return segments.first { segment in
            position >= segment.startTime && position < segment.endTime
        }
    }
    
    // MARK: - Cache Management
    
    private func getCachedSkipTimes(for key: String) -> [AniSkipSegment]? {
        return cacheQueue.sync {
            return skipCache[key]
        }
    }
    
    private func cacheSkipTimes(_ segments: [AniSkipSegment], for key: String) {
        cacheQueue.async {
            self.skipCache[key] = segments
        }
    }
    
    /// Clear all cached skip times
    func clearCache() {
        cacheQueue.async {
            self.skipCache.removeAll()
        }
    }
}
