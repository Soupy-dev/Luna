//
//  UserRatingManager.swift
//  Luna
//
//  Persists user star ratings (1-5) for media items and feeds them
//  back into the RecommendationEngine for taste-profile scoring.
//

import Foundation

final class UserRatingManager {
    static let shared = UserRatingManager()

    private var ratings: [Int: Int] = [:] // tmdbId -> 1…5
    private let fileURL: URL
    private let lock = NSLock()

    private init() {
        let docs = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)[0]
        fileURL = docs.appendingPathComponent("UserRatings.json")
        ratings = Self.load(from: fileURL)
    }

    

    func rating(for tmdbId: Int) -> Int? {
        lock.lock()
        defer { lock.unlock() }
        return ratings[tmdbId]
    }

    func setRating(_ value: Int, for tmdbId: Int) {
        let clamped = max(1, min(5, value))
        lock.lock()
        ratings[tmdbId] = clamped
        let snapshot = ratings
        lock.unlock()
        save(snapshot)
        RecommendationEngine.shared.invalidateCache()
    }

    func removeRating(for tmdbId: Int) {
        lock.lock()
        ratings.removeValue(forKey: tmdbId)
        let snapshot = ratings
        lock.unlock()
        save(snapshot)
        RecommendationEngine.shared.invalidateCache()
    }

    /// All ratings as (tmdbId, stars) for the recommendation engine.
    func allRatings() -> [(tmdbId: Int, stars: Int)] {
        lock.lock()
        defer { lock.unlock() }
        return ratings.map { (tmdbId: $0.key, stars: $0.value) }
    }

    /// All ratings as a dictionary for backup.
    func getRatingsForBackup() -> [String: Int] {
        lock.lock()
        defer { lock.unlock() }
        return Dictionary(uniqueKeysWithValues: ratings.map { (String($0.key), $0.value) })
    }

    /// Restores ratings from backup, replacing current data.
    func restoreRatings(_ backup: [String: Int]) {
        let restored = Dictionary(uniqueKeysWithValues: backup.compactMap { key, value -> (Int, Int)? in
            guard let intKey = Int(key) else { return nil }
            return (intKey, max(1, min(5, value)))
        })
        lock.lock()
        ratings = restored
        let snapshot = ratings
        lock.unlock()
        save(snapshot)
        RecommendationEngine.shared.invalidateCache()
    }

    // MARK: - Persistence

    private func save(_ data: [Int: Int]) {
        // Convert Int keys to String for JSON compatibility
        let stringKeyed = Dictionary(uniqueKeysWithValues: data.map { (String($0.key), $0.value) })
        guard let jsonData = try? JSONEncoder().encode(stringKeyed) else { return }
        try? jsonData.write(to: fileURL, options: .atomic)
    }

    private static func load(from url: URL) -> [Int: Int] {
        guard let data = try? Data(contentsOf: url),
              let stringKeyed = try? JSONDecoder().decode([String: Int].self, from: data) else {
            return [:]
        }
        return Dictionary(uniqueKeysWithValues: stringKeyed.compactMap { key, value in
            guard let intKey = Int(key) else { return nil }
            return (intKey, value)
        })
    }
}
