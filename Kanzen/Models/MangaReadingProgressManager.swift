//
//  MangaReadingProgressManager.swift
//  Kanzen
//
//  Created by Luna on 2026.
//

import Foundation

// MARK: - Progress Model

struct MangaProgress: Codable {
    var readChapterNumbers: Set<String> = []
    var lastReadChapter: String?
    var lastReadDate: Date?
}

// MARK: - Progress Manager

final class MangaReadingProgressManager: ObservableObject {
    static let shared = MangaReadingProgressManager()

    /// Key = AniList manga ID, Value = progress data
    @Published private(set) var progressMap: [Int: MangaProgress] = [:]

    private let storageKey = "mangaReadingProgress"

    private init() {
        load()
    }

    // MARK: - Queries

    func isChapterRead(mangaId: Int, chapterNumber: String) -> Bool {
        progressMap[mangaId]?.readChapterNumbers.contains(chapterNumber) == true
    }

    func readChapters(for mangaId: Int) -> Set<String> {
        progressMap[mangaId]?.readChapterNumbers ?? []
    }

    func lastReadChapter(for mangaId: Int) -> String? {
        progressMap[mangaId]?.lastReadChapter
    }

    // MARK: - Mutations

    /// Mark a chapter as read and optionally sync to AniList.
    func markChapterRead(mangaId: Int, chapterNumber: String, mangaTitle: String? = nil) {
        var progress = progressMap[mangaId] ?? MangaProgress()

        guard !progress.readChapterNumbers.contains(chapterNumber) else { return }

        progress.readChapterNumbers.insert(chapterNumber)
        progress.lastReadChapter = chapterNumber
        progress.lastReadDate = Date()
        progressMap[mangaId] = progress
        save()

        // Sync to AniList if connected — extract numeric chapter for the API
        if let numericChapter = extractChapterNumber(from: chapterNumber) {
            TrackerManager.shared.syncMangaProgress(aniListId: mangaId, chapterNumber: numericChapter)
        }
    }

    // MARK: - Persistence

    private func load() {
        if let data = UserDefaults.standard.data(forKey: storageKey),
           let decoded = try? JSONDecoder().decode([Int: MangaProgress].self, from: data) {
            progressMap = decoded
        }
    }

    private func save() {
        if let data = try? JSONEncoder().encode(progressMap) {
            UserDefaults.standard.set(data, forKey: storageKey)
        }
    }

    // MARK: - Helpers

    /// Extracts the leading integer from a chapter string like "Ch. 129" → 129, or "127.2" → 127.
    private func extractChapterNumber(from string: String) -> Int? {
        // Look for patterns like "Ch. 129", "Chapter 5", or just "129.2"
        let pattern = #"(\d+)"#
        guard let regex = try? NSRegularExpression(pattern: pattern),
              let match = regex.firstMatch(in: string, range: NSRange(string.startIndex..., in: string)),
              let range = Range(match.range(at: 1), in: string) else { return nil }
        return Int(string[range])
    }
}
