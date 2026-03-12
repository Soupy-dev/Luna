//
//  CatalogManager.swift
//  Luna
//
//  Created by Soupy-dev
//

import Foundation
import Combine

class CatalogManager: ObservableObject {
    static let shared = CatalogManager()
    
    @Published var catalogs: [Catalog] = []
    
    private let userDefaults = UserDefaults.standard
    private let catalogsKey = "enabledCatalogs"
    
    init() {
        loadCatalogs()
    }
    
    private func loadCatalogs() {
        // Default catalogs
        let defaultCatalogs: [Catalog] = [
            Catalog(id: "forYou", name: "Just For You", source: .local, isEnabled: true, order: 0),
            Catalog(id: "trending", name: "Trending This Week", source: .tmdb, isEnabled: true, order: 1),
            Catalog(id: "popularMovies", name: "Popular Movies", source: .tmdb, isEnabled: true, order: 2),
            Catalog(id: "nowPlayingMovies", name: "Now Playing Movies", source: .tmdb, isEnabled: false, order: 3),
            Catalog(id: "upcomingMovies", name: "Upcoming Movies", source: .tmdb, isEnabled: false, order: 4),
            Catalog(id: "popularTVShows", name: "Popular TV Shows", source: .tmdb, isEnabled: true, order: 5),
            Catalog(id: "onTheAirTV", name: "On The Air TV Shows", source: .tmdb, isEnabled: false, order: 6),
            Catalog(id: "airingTodayTV", name: "Airing Today TV Shows", source: .tmdb, isEnabled: false, order: 7),
            Catalog(id: "topRatedTVShows", name: "Top Rated TV Shows", source: .tmdb, isEnabled: true, order: 8),
            Catalog(id: "topRatedMovies", name: "Top Rated Movies", source: .tmdb, isEnabled: true, order: 9),
            Catalog(id: "trendingAnime", name: "Trending Anime", source: .anilist, isEnabled: true, order: 10),
            Catalog(id: "popularAnime", name: "Popular Anime", source: .anilist, isEnabled: true, order: 11),
            Catalog(id: "topRatedAnime", name: "Top Rated Anime", source: .anilist, isEnabled: true, order: 12),
            Catalog(id: "airingAnime", name: "Currently Airing Anime", source: .anilist, isEnabled: false, order: 13),
            Catalog(id: "upcomingAnime", name: "Upcoming Anime", source: .anilist, isEnabled: false, order: 14),
            Catalog(id: "networks", name: "Network", source: .tmdb, isEnabled: true, order: 15, displayStyle: .network),
            Catalog(id: "genres", name: "Category", source: .tmdb, isEnabled: true, order: 16, displayStyle: .genre),
            Catalog(id: "companies", name: "Company", source: .tmdb, isEnabled: true, order: 17, displayStyle: .company),
            Catalog(id: "bestTVShows", name: "Best TV Shows", source: .tmdb, isEnabled: true, order: 18, displayStyle: .ranked),
            Catalog(id: "bestMovies", name: "Best Movies", source: .tmdb, isEnabled: true, order: 19, displayStyle: .ranked),
            Catalog(id: "bestAnime", name: "Best Anime", source: .anilist, isEnabled: true, order: 20, displayStyle: .ranked),
            Catalog(id: "featured", name: "Featured", source: .tmdb, isEnabled: true, order: 21, displayStyle: .featured)
        ]
        
        // Try to load saved catalogs
        if let data = userDefaults.data(forKey: catalogsKey),
           let savedCatalogs = try? JSONDecoder().decode([Catalog].self, from: data) {
            // Merge any newly added defaults while preserving the user's order
            var merged = savedCatalogs.sorted { $0.order < $1.order }
            let existingIds = Set(savedCatalogs.map { $0.id })
            let missingDefaults = defaultCatalogs.filter { !existingIds.contains($0.id) }
            merged.append(contentsOf: missingDefaults)
            
            // Ensure orders stay sequential after adding new entries
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
        // Dispatch to main thread to notify observers after persistence
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
    
    func getEnabledCatalogs() -> [Catalog] {
        catalogs.filter { $0.isEnabled }.sorted { $0.order < $1.order }
    }
}

struct Catalog: Identifiable, Codable {
    let id: String
    let name: String
    let source: CatalogSource
    var isEnabled: Bool
    var order: Int
    var displayStyle: CatalogDisplayStyle
    
    enum CatalogSource: String, Codable {
        case tmdb = "TMDB"
        case anilist = "AniList"
        case local = "Local"
    }
    
    enum CatalogDisplayStyle: String, Codable {
        case standard
        case network
        case genre
        case company
        case ranked
        case featured
    }
    
    init(id: String, name: String, source: CatalogSource, isEnabled: Bool, order: Int, displayStyle: CatalogDisplayStyle = .standard) {
        self.id = id
        self.name = name
        self.source = source
        self.isEnabled = isEnabled
        self.order = order
        self.displayStyle = displayStyle
    }
    
    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        id = try container.decode(String.self, forKey: .id)
        name = try container.decode(String.self, forKey: .name)
        source = try container.decode(CatalogSource.self, forKey: .source)
        isEnabled = try container.decode(Bool.self, forKey: .isEnabled)
        order = try container.decode(Int.self, forKey: .order)
        displayStyle = try container.decodeIfPresent(CatalogDisplayStyle.self, forKey: .displayStyle) ?? .standard
    }
}
