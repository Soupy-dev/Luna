//
//  MangaCatalogManager.swift
//  Kanzen
//
//  Created by Luna on 2025.
//

import Foundation
import Combine

class MangaCatalogManager: ObservableObject {
    static let shared = MangaCatalogManager()

    @Published var catalogs: [MangaCatalog] = []

    private let userDefaults = UserDefaults.standard
    private let catalogsKey = "mangaEnabledCatalogs"

    init() {
        loadCatalogs()
    }

    private func loadCatalogs() {
        let defaultCatalogs: [MangaCatalog] = [
            MangaCatalog(id: "trendingManga", name: "Trending Manga", isEnabled: true, order: 0),
            MangaCatalog(id: "popularManga", name: "Popular Manga", isEnabled: true, order: 1),
            MangaCatalog(id: "topRatedManga", name: "Top Rated Manga", isEnabled: true, order: 2),
            MangaCatalog(id: "publishingManga", name: "Currently Publishing", isEnabled: false, order: 3),
            MangaCatalog(id: "recentlyUpdated", name: "Recently Updated", isEnabled: true, order: 4),
            MangaCatalog(id: "popularManhwa", name: "Popular Manhwa", isEnabled: true, order: 5),
            MangaCatalog(id: "trendingManhwa", name: "Trending Manhwa", isEnabled: false, order: 6),
            MangaCatalog(id: "topRatedManhwa", name: "Top Rated Manhwa", isEnabled: false, order: 7),
            MangaCatalog(id: "popularLightNovels", name: "Popular Light Novels", isEnabled: false, order: 8),
            MangaCatalog(id: "topRatedLightNovels", name: "Top Rated Light Novels", isEnabled: false, order: 9),
        ]

        if let data = userDefaults.data(forKey: catalogsKey),
           let savedCatalogs = try? JSONDecoder().decode([MangaCatalog].self, from: data) {
            var merged = savedCatalogs.sorted { $0.order < $1.order }
            let existingIds = Set(savedCatalogs.map { $0.id })
            let missingDefaults = defaultCatalogs.filter { !existingIds.contains($0.id) }
            merged.append(contentsOf: missingDefaults)

            merged = merged.enumerated().map { index, catalog in
                var updated = catalog
                updated.order = index
                return updated
            }

            self.catalogs = merged
            saveCatalogs()
        } else {
            self.catalogs = defaultCatalogs
            saveCatalogs()
        }
    }

    func saveCatalogs() {
        if let data = try? JSONEncoder().encode(catalogs) {
            userDefaults.set(data, forKey: catalogsKey)
            userDefaults.synchronize()
        }
        DispatchQueue.main.async { [weak self] in
            self?.objectWillChange.send()
        }
    }

    func toggleCatalog(id: String) {
        if let index = catalogs.firstIndex(where: { $0.id == id }) {
            catalogs[index].isEnabled.toggle()
            saveCatalogs()
        }
    }

    func moveCatalog(from: IndexSet, to: Int) {
        catalogs.move(fromOffsets: from, toOffset: to)
        for (index, _) in catalogs.enumerated() {
            catalogs[index].order = index
        }
        saveCatalogs()
    }

    func getEnabledCatalogs() -> [MangaCatalog] {
        catalogs.filter { $0.isEnabled }.sorted { $0.order < $1.order }
    }
}

struct MangaCatalog: Identifiable, Codable {
    let id: String
    let name: String
    var isEnabled: Bool
    var order: Int
}
