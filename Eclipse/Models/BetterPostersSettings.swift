
import Foundation

enum BetterPostersSettings {
    static let enabledKey = "betterPostersEnabled"
    static let urlPatternKey = "betterPostersURLPattern"
    static let applyToHomeKey = "betterPostersApplyToHome"

    static let defaultEnabled = false
    static let defaultApplyToHome = false

    static let placeholderToken = "{imdb_id}"

    static var isEnabled: Bool {
        let defaults = ProfileSettingsStore.active
        return defaults.object(forKey: enabledKey) == nil ? defaultEnabled : defaults.bool(forKey: enabledKey)
    }

    static var applyToHomeScreen: Bool {
        let defaults = ProfileSettingsStore.active
        return defaults.object(forKey: applyToHomeKey) == nil ? defaultApplyToHome : defaults.bool(forKey: applyToHomeKey)
    }

    static var urlPattern: String? {
        let pattern = ProfileSettingsStore.active.string(forKey: urlPatternKey)?
            .trimmingCharacters(in: .whitespacesAndNewlines)
        return (pattern?.isEmpty ?? true) ? nil : pattern
    }

    static func posterURL(imdbId: String?) -> String? {
        guard isEnabled, let pattern = urlPattern, let imdbId, !imdbId.isEmpty else { return nil }
        guard pattern.contains(placeholderToken) else { return nil }
        return pattern.replacingOccurrences(of: placeholderToken, with: imdbId)
    }
}

actor IMDbIDCache {
    static let shared = IMDbIDCache()

    private var cache: [String: String] = [:]
    private var inFlight: [String: Task<String?, Never>] = [:]

    private func key(tmdbId: Int, isMovie: Bool) -> String {
        "\(isMovie ? "movie" : "tv")-\(tmdbId)"
    }

    func imdbId(tmdbId: Int, isMovie: Bool, tmdbService: TMDBService) async -> String? {
        let cacheKey = key(tmdbId: tmdbId, isMovie: isMovie)

        if let cached = cache[cacheKey] {
            return cached
        }

        if let existingTask = inFlight[cacheKey] {
            return await existingTask.value
        }

        let task = Task<String?, Never> {
            await tmdbService.fetchExternalImdbId(tmdbId: tmdbId, isMovie: isMovie)
        }
        inFlight[cacheKey] = task

        let result = await task.value
        inFlight[cacheKey] = nil
        if let result {
            cache[cacheKey] = result
        }
        return result
    }
}
