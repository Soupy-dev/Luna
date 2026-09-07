//
//  AlgorithmManager.swift
//  Sora
//
//  Created by Francesco on 20/08/25.
//

import Foundation

enum SimilarityAlgorithm: String, CaseIterable, Hashable, Sendable {
    case hybrid = "hybrid"
    case jaroWinkler = "jaro_winkler"
    case levenshtein = "levenshtein"

    var displayName: String {
        switch self {
        case .hybrid:
            return "Hybrid"
        case .jaroWinkler:
            return "Jaro-Winkler Similarity"
        case .levenshtein:
            return "Levenshtein Distance"
        }
    }

    var description: String {
        switch self {
        case .hybrid:
            return "Combines both algorithms for optimal matching across different string types and lengths."
        case .jaroWinkler:
            return "When matching names, titles, or short strings where prefix similarity are important."
        case .levenshtein:
            return "When you need precise differences across all text available."
        }
    }
}

class AlgorithmManager: ObservableObject {
    static let shared = AlgorithmManager()

    private struct SimilarityCacheKey: Hashable {
        let algorithm: SimilarityAlgorithm
        let original: String
        let result: String
    }

    private static let similarityCacheLimit = 4_000
    private static let similarityCacheLock = NSLock()
    nonisolated(unsafe) private static var similarityCache: [SimilarityCacheKey: Double] = [:]

    private var isReloadingForProfileSwitch = false

    @Published var selectedAlgorithm: SimilarityAlgorithm {
        didSet {
            guard !isReloadingForProfileSwitch else { return }
            ProfileSettingsStore.active.set(selectedAlgorithm.rawValue, forKey: "selectedSimilarityAlgorithm")
        }
    }

    private init() {
        let savedAlgorithm = ProfileSettingsStore.active.string(forKey: "selectedSimilarityAlgorithm") ?? SimilarityAlgorithm.hybrid.rawValue
        self.selectedAlgorithm = SimilarityAlgorithm(rawValue: savedAlgorithm) ?? .hybrid
    }

    func reloadForActiveProfile() {
        isReloadingForProfileSwitch = true
        defer { isReloadingForProfileSwitch = false }
        let saved = ProfileSettingsStore.active.string(forKey: "selectedSimilarityAlgorithm")
            ?? SimilarityAlgorithm.hybrid.rawValue
        selectedAlgorithm = SimilarityAlgorithm(rawValue: saved) ?? .hybrid
    }

    func calculateSimilarity(original: String, result: String) -> Double {
        Self.calculateSimilarity(original: original, result: result, algorithm: selectedAlgorithm)
    }

    static func calculateSimilarity(original: String, result: String, algorithm: SimilarityAlgorithm) -> Double {
        guard !original.isEmpty && !result.isEmpty else {
            return original.isEmpty && result.isEmpty ? 1.0 : 0.0
        }

        let cleanOriginal = original.trimmingCharacters(in: .whitespacesAndNewlines)
        let cleanResult = result.trimmingCharacters(in: .whitespacesAndNewlines)

        guard !cleanOriginal.isEmpty && !cleanResult.isEmpty else {
            return cleanOriginal.isEmpty && cleanResult.isEmpty ? 1.0 : 0.0
        }

        let key = SimilarityCacheKey(
            algorithm: algorithm,
            original: cleanOriginal,
            result: cleanResult
        )

        similarityCacheLock.lock()
        let cachedScore = similarityCache[key]
        similarityCacheLock.unlock()
        if let cachedScore {
            return cachedScore
        }

        let score: Double
        switch algorithm {
        case .levenshtein:
            score = LevenshteinDistance.calculateSimilarity(original: cleanOriginal, result: cleanResult)
        case .jaroWinkler:
            score = JaroWinklerSimilarity.calculateSimilarity(original: cleanOriginal, result: cleanResult)
        case .hybrid:
            score = HybridSimilarity.calculateSimilarity(original: cleanOriginal, result: cleanResult)
        }

        similarityCacheLock.lock()
        if similarityCache.count >= AlgorithmManager.similarityCacheLimit {
            similarityCache.removeAll(keepingCapacity: true)
        }
        similarityCache[key] = score
        similarityCacheLock.unlock()

        return score
    }
}

struct ServiceResultRankingContext: Hashable, Sendable {
    struct Episode: Hashable, Sendable {
        let seasonNumber: Int
        let episodeNumber: Int
    }

    struct RankedSearchResult: Sendable {
        let index: Int
        let result: String
        let initialSimilarity: Double
        let titleSimilarity: Double
        let animeSeasonPreference: Int
        let tieBreakScore: Int
        let matchesForcedDestination: Bool
        let displaySimilarity: Double
    }

    private struct Calculator {
        let algorithm: SimilarityAlgorithm

        func calculateSimilarity(original: String, result: String) -> Double {
            AlgorithmManager.calculateSimilarity(original: original, result: result, algorithm: algorithm)
        }
    }

    let algorithm: SimilarityAlgorithm
    let localeIdentifier: String
    let effectiveTitle: String
    let mediaTitle: String
    let displayTitle: String
    let originalTitle: String?
    let seasonTitleOverride: String?
    let animeSeasonTitle: String?
    let normalizedAnimeSequelTitle: String?
    let strippedAnimeFallbackTitle: String?
    let isAnimeContent: Bool
    let isForcedWatchTogetherAnimePlayback: Bool
    let selectedEpisode: Episode?
    let serviceResultMinimumSimilarity: Double
    let highQualityThreshold: Double
    let dropsMismatches: Bool

    private var algorithmManager: Calculator { Calculator(algorithm: algorithm) }

    func rankedServiceResults(_ results: [String]) throws -> [RankedSearchResult] {
        let matchCandidates = titleMatchCandidates()
        let rankCandidates = titleRankingCandidates()
        let tieBreakCandidates = matchCandidates.map(normalizeTitle).filter { !$0.isEmpty }
        let expectedSeasonMarkers: Set<AnimeSeasonPreferenceMarker>
        if isAnimeContent || animeSeasonTitle != nil,
           let seasonNumber = selectedEpisode?.seasonNumber, seasonNumber > 1 {
            expectedSeasonMarkers = animeSeasonPreferenceMarkers(
                in: stripEpisodeSuffix(from: effectiveTitle), terminalSeasonNumber: seasonNumber
            )
        } else {
            expectedSeasonMarkers = []
        }
        return try results.enumerated().map { index, result in
            try Task.checkCancellation()
            let initialSimilarity = resultSimilarity(result, candidates: matchCandidates)
            return RankedSearchResult(
                index: index,
                result: result,
                initialSimilarity: initialSimilarity,
                titleSimilarity: titleRankingScore(result, candidates: rankCandidates, initialSimilarity: initialSimilarity),
                animeSeasonPreference: animeSeasonPreferenceScore(result, expectedMarkers: expectedSeasonMarkers),
                tieBreakScore: resultTieBreakScore(result, expectedTitles: tieBreakCandidates),
                matchesForcedDestination: forcedWatchTogetherAnimeResultMatchesDestination(result),
                displaySimilarity: max(
                    algorithmManager.calculateSimilarity(original: effectiveTitle, result: result),
                    originalTitle.map { algorithmManager.calculateSimilarity(original: $0, result: result) } ?? 0
                )
            )
        }
        .sorted { lhs, rhs in
            let lhsEligible = lhs.initialSimilarity >= serviceResultMinimumSimilarity
            let rhsEligible = rhs.initialSimilarity >= serviceResultMinimumSimilarity

            if lhsEligible != rhsEligible {
                return lhsEligible && !rhsEligible
            }

            if lhsEligible && rhsEligible,
               lhs.animeSeasonPreference != rhs.animeSeasonPreference {
                return lhs.animeSeasonPreference > rhs.animeSeasonPreference
            }

            if lhsEligible && rhsEligible,
               !scoresAreEquivalent(lhs.titleSimilarity, rhs.titleSimilarity) {
                return lhs.titleSimilarity > rhs.titleSimilarity
            }

            if !scoresAreEquivalent(lhs.initialSimilarity, rhs.initialSimilarity) {
                return lhs.initialSimilarity > rhs.initialSimilarity
            }

            if lhs.tieBreakScore != rhs.tieBreakScore {
                return lhs.tieBreakScore > rhs.tieBreakScore
            }

            return lhs.index < rhs.index
        }
    }

    private func scoresAreEquivalent(_ lhs: Double, _ rhs: Double) -> Bool {
        abs(lhs - rhs) < 0.0001
    }

    private func normalizeTitle(_ title: String) -> String {
        title
            .lowercased()
            .replacingOccurrences(of: "[^a-z0-9]+", with: " ", options: .regularExpression)
            .trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private var sheetTitleBaseForMatching: String {
        stripEpisodeSuffix(from: displayTitle)
    }

    private func stripEpisodeSuffix(from title: String) -> String {
        let patterns = [
            #"(?i)\s*-\s*S\d{1,3}E\d{1,4}$"#,
            #"(?i)\s*S\d{1,3}E\d{1,4}$"#,
            #"(?i)\s*-\s*E\d{1,4}$"#,
            #"(?i)\s*E\d{1,4}$"#,
            #"(?i)\s*episode\s+\d{1,4}$"#
        ]

        var stripped = title.trimmingCharacters(in: .whitespacesAndNewlines)
        for pattern in patterns {
            if let range = stripped.range(of: pattern, options: .regularExpression) {
                stripped.removeSubrange(range)
                break
            }
        }
        return stripped.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private func titleMatchCandidates() -> [String] {
        var seen = Set<String>()
        var candidates: [String?] = [
            sheetTitleBaseForMatching,
            effectiveTitle,
            mediaTitle,
            normalizedAnimeSequelTitle
        ]
        if !isForcedWatchTogetherAnimePlayback {
            candidates.append(strippedAnimeFallbackTitle)
            candidates.append(originalTitle)
        }
        return candidates
        .compactMap { $0?.trimmingCharacters(in: .whitespacesAndNewlines) }
        .filter { !$0.isEmpty }
        .filter { seen.insert(normalizeTitle($0)).inserted }
    }

    private func titleRankingCandidates() -> [String] {
        var seen = Set<String>()
        var candidates = [
            sheetTitleBaseForMatching,
            effectiveTitle,
            mediaTitle,
            normalizedAnimeSequelTitle
        ]

        if !isForcedWatchTogetherAnimePlayback {
            candidates.append(strippedAnimeFallbackTitle)
        }

        if !(isAnimeContent || animeSeasonTitle != nil),
           !isForcedWatchTogetherAnimePlayback {
            candidates.append(originalTitle)
        }

        return candidates.compactMap { raw in
            guard let raw else { return nil }
            let value = raw.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !value.isEmpty else { return nil }
            let key = normalizeTitleForRanking(value)
            guard seen.insert(key).inserted else { return nil }
            return value
        }
    }

    private func titleRankingScore(_ result: String, candidates: [String], initialSimilarity: Double) -> Double {
        rankingCandidates(for: result, fallback: candidates)
            .map { titleSimilarityForRanking(expected: $0, result: result) }
            .max() ?? initialSimilarity
    }

    private func rankingCandidates(for result: String, fallback: [String]) -> [String] {
        guard isAnimeContent || animeSeasonTitle != nil,
              let alternate = originalTitle?.trimmingCharacters(in: .whitespacesAndNewlines),
              !alternate.isEmpty,
              serviceResultLooksLikeAlternateTitle(result, alternateTitle: alternate) else {
            return fallback
        }

        return [alternate]
    }

    private func serviceResultLooksLikeAlternateTitle(_ result: String, alternateTitle: String) -> Bool {
        let displayScore = titleSimilarityForRanking(expected: sheetTitleBaseForMatching, result: result)
        let alternateScore = titleSimilarityForRanking(expected: alternateTitle, result: result)
        return alternateScore >= 0.82 && alternateScore > displayScore + 0.06
    }

    func forcedWatchTogetherAnimeResultMatchesDestination(
        _ result: String
    ) -> Bool {
        guard isForcedWatchTogetherAnimePlayback else { return true }
        let resultKey = exactWatchTogetherAnimeTitleKey(result)
        guard !resultKey.isEmpty else { return false }
        let targetKeys = [
            seasonTitleOverride,
            Optional(effectiveTitle),
            Optional(mediaTitle),
            normalizedAnimeSequelTitle
        ]
        .compactMap { $0 }
        .map(exactWatchTogetherAnimeTitleKey)
        .filter { !$0.isEmpty }

        return targetKeys.contains(resultKey)
    }

    private func exactWatchTogetherAnimeTitleKey(_ rawTitle: String) -> String {
        func collapsedWhitespace(_ value: String) -> String {
            value
                .replacingOccurrences(of: #"\s+"#, with: " ", options: .regularExpression)
                .trimmingCharacters(in: .whitespacesAndNewlines)
        }

        var value = collapsedWhitespace(
            rawTitle
                .lowercased()
                .replacingOccurrences(of: "’", with: "'")
                .replacingOccurrences(of: "‘", with: "'")
                .replacingOccurrences(of: "–", with: "-")
                .replacingOccurrences(of: "—", with: "-")
        )
        let technicalSuffixes = [
            " (english dub)", " [english dub]", " - english dub", " english dub",
            " (english sub)", " [english sub]", " - english sub", " english sub",
            " (dual audio)", " [dual audio]", " - dual audio", " dual audio",
            " (multi audio)", " [multi audio]", " - multi audio", " multi audio",
            " (uncensored)", " [uncensored]", " - uncensored", " uncensored",
            " (remastered)", " [remastered]", " - remastered", " remastered",
            " (dubbed)", " [dubbed]", " - dubbed", " dubbed",
            " (subbed)", " [subbed]", " - subbed", " subbed",
            " (dub)", " [dub]", " - dub", " dub",
            " (sub)", " [sub]", " - sub", " sub",
            " (1080p)", " [1080p]", " - 1080p", " 1080p",
            " (720p)", " [720p]", " - 720p", " 720p",
            " (4k)", " [4k]", " - 4k", " 4k",
            " (hd)", " [hd]", " - hd", " hd"
        ]
        var removedSuffix = true
        while removedSuffix {
            removedSuffix = false
            for suffix in technicalSuffixes where value.hasSuffix(suffix) {
                value.removeLast(suffix.count)
                value = collapsedWhitespace(value)
                removedSuffix = true
                break
            }
        }
        return collapsedWhitespace(stripEpisodeSuffix(from: value))
    }

    private func titleSimilarityForRanking(expected: String, result: String) -> Double {
        let expectedCanonical = normalizeTitleForRanking(expected)
        let resultCanonical = normalizeTitleForRanking(result)

        let rawSimilarity = algorithmManager.calculateSimilarity(original: expected, result: result)
        let canonicalSimilarity = algorithmManager.calculateSimilarity(original: expectedCanonical, result: resultCanonical)
        let tokenScore = tokenOverlapScore(expectedCanonical, resultCanonical)

        var score = max(rawSimilarity, canonicalSimilarity) * 0.70 + tokenScore * 0.30

        if !expectedCanonical.isEmpty {
            if resultCanonical == expectedCanonical {
                score += 0.15
            } else if resultCanonical.contains(expectedCanonical) || expectedCanonical.contains(resultCanonical) {
                score += 0.08
            }
        }

        return max(0, score)
    }

    private func normalizeTitleForRanking(_ title: String) -> String {
        title
            .folding(options: [.diacriticInsensitive, .widthInsensitive], locale: Locale(identifier: localeIdentifier))
            .lowercased()
            .replacingOccurrences(of: #"[^a-z0-9]+"#, with: " ", options: .regularExpression)
            .trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private func tokenOverlapScore(_ lhs: String, _ rhs: String) -> Double {
        let ignored: Set<String> = ["a", "an", "and", "the", "of", "to", "in", "on", "tv", "series", "episode"]
        let lhsTokens = Set(lhs.split(separator: " ").map(String.init).filter { $0.count > 1 && !ignored.contains($0) })
        let rhsTokens = Set(rhs.split(separator: " ").map(String.init).filter { $0.count > 1 && !ignored.contains($0) })

        guard !lhsTokens.isEmpty, !rhsTokens.isEmpty else { return 0 }
        let shared = lhsTokens.intersection(rhsTokens).count
        return Double(shared) / Double(max(lhsTokens.count, rhsTokens.count))
    }

    private func resultSimilarity(_ result: String, candidates: [String]) -> Double {
        candidates
            .map { algorithmManager.calculateSimilarity(original: $0, result: result) }
            .max() ?? 0.0
    }

    private enum AnimeSeasonPreferenceMarker: Hashable {
        case season(Int)
        case part(Int)
    }

    private func animeSeasonPreferenceScore(_ result: String, expectedMarkers: Set<AnimeSeasonPreferenceMarker>) -> Int {
        guard !expectedMarkers.isEmpty else { return 0 }

        let resultTitle = stripEpisodeSuffix(from: result)
        return expectedMarkers.allSatisfy { animeResultTitle(resultTitle, matches: $0) } ? 1 : 0
    }

    private func animeSeasonPreferenceMarkers(
        in title: String,
        terminalSeasonNumber: Int? = nil
    ) -> Set<AnimeSeasonPreferenceMarker> {
        let normalized = normalizeTitle(title)
        let tokens = normalized.split(separator: " ").map(String.init)
        var markers = Set<AnimeSeasonPreferenceMarker>()

        for (index, token) in tokens.enumerated() {
            let nextToken = index + 1 < tokens.count ? tokens[index + 1] : nil

            if token == "season", let nextToken, let number = Int(nextToken) {
                markers.insert(.season(number))
            } else if let number = markerNumber(after: "season", in: token) {
                markers.insert(.season(number))
            }

            if token == "part", let nextToken, let number = Int(nextToken) {
                markers.insert(.part(number))
            } else if let number = markerNumber(after: "part", in: token) {
                markers.insert(.part(number))
            }

            if nextToken == "season", let number = ordinalNumber(from: token) {
                markers.insert(.season(number))
            }
        }

        if markers.isEmpty,
           let terminalSeasonNumber,
           titleContainsTerminalAnimeSeasonNumber(normalized, seasonNumber: terminalSeasonNumber) {
            markers.insert(.season(terminalSeasonNumber))
        }

        return markers
    }

    private func animeResultTitle(_ title: String, matches marker: AnimeSeasonPreferenceMarker) -> Bool {
        let explicitMarkers = animeSeasonPreferenceMarkers(in: title)
        if explicitMarkers.contains(marker) {
            return true
        }

        guard explicitMarkers.isEmpty,
              case let .season(seasonNumber) = marker else {
            return false
        }

        return titleContainsTerminalAnimeSeasonNumber(title, seasonNumber: seasonNumber)
    }

    private func titleContainsTerminalAnimeSeasonNumber(_ title: String, seasonNumber: Int) -> Bool {
        let patterns = [
            "[a-z]\(seasonNumber)$",
            "\\b\(seasonNumber)$"
        ]
        return patterns.contains { title.range(of: $0, options: .regularExpression) != nil }
    }

    private func markerNumber(after prefix: String, in token: String) -> Int? {
        guard token.hasPrefix(prefix) else { return nil }
        let suffix = token.dropFirst(prefix.count)
        return suffix.isEmpty ? nil : Int(suffix)
    }

    private func ordinalNumber(from token: String) -> Int? {
        for suffix in ["st", "nd", "rd", "th"] where token.hasSuffix(suffix) {
            return Int(token.dropLast(suffix.count))
        }
        return nil
    }

    private func resultTieBreakScore(_ result: String, expectedTitles: [String]) -> Int {
        let normalizedResult = normalizeTitle(result)

        var score = 0
        for candidate in expectedTitles {
            if normalizedResult == candidate {
                score += 10
            } else if normalizedResult.contains(candidate) || candidate.contains(normalizedResult) {
                score += 4
            }
        }

        if let episode = selectedEpisode {
            let seasonEpisodeToken = "s\(episode.seasonNumber)e\(episode.episodeNumber)"
            let episodeToken = "e\(episode.episodeNumber)"
            if normalizedResult.contains(seasonEpisodeToken) || normalizedResult.contains(episodeToken) {
                score += 3
            }
        }

        if !sheetTitleBaseForMatching.isEmpty {
            let sheetScore = algorithmManager.calculateSimilarity(original: sheetTitleBaseForMatching, result: result)
            score += Int(sheetScore * 10)
        }

        return score
    }

}

protocol ServiceResultRankingComputing: Sendable {
    func rank(titles: [String], context: ServiceResultRankingContext) async throws -> [ServiceResultRankingContext.RankedSearchResult]
}

actor ServiceResultRankingWorker: ServiceResultRankingComputing {
    static let shared = ServiceResultRankingWorker()

    func rank(titles: [String], context: ServiceResultRankingContext) throws -> [ServiceResultRankingContext.RankedSearchResult] {
        try Task.checkCancellation()
        return try context.rankedServiceResults(titles)
    }
}
