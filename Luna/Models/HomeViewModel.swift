//
//  HomeViewModel.swift
//  Luna
//
//  Created by Soupy-dev
//

import Foundation
import SwiftUI

final class HomeViewModel: ObservableObject {
    @Published var catalogResults: [String: [TMDBSearchResult]] = [:]
    @Published var isLoading = true
    @Published var errorMessage: String?
    @Published var heroContent: TMDBSearchResult?
    @Published var ambientColor: Color = Color.black
    @Published var hasLoadedContent = false
    @Published var widgetData: [String: [TMDBSearchResult]] = [:]
    @Published var becauseYouWatchedTitle: String = ""
    
    init() {
        // Init body can be simplified if needed
    }
    
    func loadContent(
        tmdbService: TMDBService,
        catalogManager: CatalogManager,
        contentFilter: TMDBContentFilter
    ) {
        // Don't reload if we already have content
        guard !hasLoadedContent else {
            return
        }
        
        isLoading = true
        errorMessage = nil
        
        Task {
            do {
                async let trending = tmdbService.getTrending()
                async let popularM = tmdbService.getPopularMovies()
                async let nowPlayingM = tmdbService.getNowPlayingMovies()
                async let upcomingM = tmdbService.getUpcomingMovies()
                async let popularTV = tmdbService.getPopularTVShows()
                async let onTheAirTV = tmdbService.getOnTheAirTVShows()
                async let airingTodayTV = tmdbService.getAiringTodayTVShows()
                async let topRatedTV = tmdbService.getTopRatedTVShows()
                async let topRatedM = tmdbService.getTopRatedMovies()
                let tmdbResults = try await (
                    trending, popularM, nowPlayingM, upcomingM, popularTV, onTheAirTV,
                    airingTodayTV, topRatedTV, topRatedM
                )
                
                // Fetch all anime catalogs in a single AniList query (1 API call instead of 5)
                let animeCatalogs = (try? await AniListService.shared.fetchAllAnimeCatalogs(tmdbService: tmdbService)) ?? [:]
                let trendingAnime = animeCatalogs[.trending] ?? []
                let popularAnime = animeCatalogs[.popular] ?? []
                let topRatedAnime = animeCatalogs[.topRated] ?? []
                let airingAnime = animeCatalogs[.airing] ?? []
                let upcomingAnime = animeCatalogs[.upcoming] ?? []
                
                await MainActor.run {
                    self.catalogResults = [
                        "trending": tmdbResults.0,
                        "popularMovies": tmdbResults.1.map { movie in
                            TMDBSearchResult(
                                id: movie.id,
                                mediaType: "movie",
                                title: movie.title,
                                name: nil,
                                overview: movie.overview,
                                posterPath: movie.posterPath,
                                backdropPath: movie.backdropPath,
                                releaseDate: movie.releaseDate,
                                firstAirDate: nil,
                                voteAverage: movie.voteAverage,
                                popularity: movie.popularity,
                                adult: movie.adult,
                                genreIds: movie.genreIds
                            )
                        },
                        "nowPlayingMovies": tmdbResults.2.map { movie in
                            TMDBSearchResult(
                                id: movie.id,
                                mediaType: "movie",
                                title: movie.title,
                                name: nil,
                                overview: movie.overview,
                                posterPath: movie.posterPath,
                                backdropPath: movie.backdropPath,
                                releaseDate: movie.releaseDate,
                                firstAirDate: nil,
                                voteAverage: movie.voteAverage,
                                popularity: movie.popularity,
                                adult: movie.adult,
                                genreIds: movie.genreIds
                            )
                        },
                        "upcomingMovies": tmdbResults.3.map { movie in
                            TMDBSearchResult(
                                id: movie.id,
                                mediaType: "movie",
                                title: movie.title,
                                name: nil,
                                overview: movie.overview,
                                posterPath: movie.posterPath,
                                backdropPath: movie.backdropPath,
                                releaseDate: movie.releaseDate,
                                firstAirDate: nil,
                                voteAverage: movie.voteAverage,
                                popularity: movie.popularity,
                                adult: movie.adult,
                                genreIds: movie.genreIds
                            )
                        },
                        "popularTVShows": tmdbResults.4.map { show in
                            TMDBSearchResult(
                                id: show.id,
                                mediaType: "tv",
                                title: nil,
                                name: show.name,
                                overview: show.overview,
                                posterPath: show.posterPath,
                                backdropPath: show.backdropPath,
                                releaseDate: nil,
                                firstAirDate: show.firstAirDate,
                                voteAverage: show.voteAverage,
                                popularity: show.popularity,
                                adult: nil,
                                genreIds: show.genreIds
                            )
                        },
                        "onTheAirTV": tmdbResults.5.map { show in
                            TMDBSearchResult(
                                id: show.id,
                                mediaType: "tv",
                                title: nil,
                                name: show.name,
                                overview: show.overview,
                                posterPath: show.posterPath,
                                backdropPath: show.backdropPath,
                                releaseDate: nil,
                                firstAirDate: show.firstAirDate,
                                voteAverage: show.voteAverage,
                                popularity: show.popularity,
                                adult: nil,
                                genreIds: show.genreIds
                            )
                        },
                        "airingTodayTV": tmdbResults.6.map { show in
                            TMDBSearchResult(
                                id: show.id,
                                mediaType: "tv",
                                title: nil,
                                name: show.name,
                                overview: show.overview,
                                posterPath: show.posterPath,
                                backdropPath: show.backdropPath,
                                releaseDate: nil,
                                firstAirDate: show.firstAirDate,
                                voteAverage: show.voteAverage,
                                popularity: show.popularity,
                                adult: nil,
                                genreIds: show.genreIds
                            )
                        },
                        "topRatedTVShows": tmdbResults.7.map { show in
                            TMDBSearchResult(
                                id: show.id,
                                mediaType: "tv",
                                title: nil,
                                name: show.name,
                                overview: show.overview,
                                posterPath: show.posterPath,
                                backdropPath: show.backdropPath,
                                releaseDate: nil,
                                firstAirDate: show.firstAirDate,
                                voteAverage: show.voteAverage,
                                popularity: show.popularity,
                                adult: nil,
                                genreIds: show.genreIds
                            )
                        },
                        "topRatedMovies": tmdbResults.8.map { movie in
                            TMDBSearchResult(
                                id: movie.id,
                                mediaType: "movie",
                                title: movie.title,
                                name: nil,
                                overview: movie.overview,
                                posterPath: movie.posterPath,
                                backdropPath: movie.backdropPath,
                                releaseDate: movie.releaseDate,
                                firstAirDate: nil,
                                voteAverage: movie.voteAverage,
                                popularity: movie.popularity,
                                adult: movie.adult,
                                genreIds: movie.genreIds
                            )
                        },
                        "trendingAnime": trendingAnime,
                        "popularAnime": popularAnime,
                        "topRatedAnime": topRatedAnime,
                        "airingAnime": airingAnime,
                        "upcomingAnime": upcomingAnime
                    ]
                    
                    // Set hero content from trending
                    if let hero = tmdbResults.0.first {
                        self.heroContent = hero
                    }
                    
                    self.isLoading = false
                    self.hasLoadedContent = true
                }
                
                // Generate "Just For You" recommendations after catalogs are populated
                let currentResults = await MainActor.run { self.catalogResults }
                let forYou = await RecommendationEngine.shared.generateRecommendations(
                    catalogResults: currentResults,
                    tmdbService: tmdbService
                )
                if !forYou.isEmpty {
                    await MainActor.run {
                        self.catalogResults["forYou"] = forYou
                    }
                }
                
                // Generate "Because you watched X" catalog
                let (bywTitle, bywResults) = await RecommendationEngine.shared.generateBecauseYouWatched(
                    tmdbService: tmdbService
                )
                if !bywResults.isEmpty {
                    await MainActor.run {
                        self.catalogResults["becauseYouWatched"] = bywResults
                        self.becauseYouWatchedTitle = bywTitle
                    }
                }
                
                // Load widget data in secondary pass (non-blocking, progressive)
                self.loadWidgetData(tmdbService: tmdbService, catalogManager: catalogManager)
            } catch {
                await MainActor.run {
                    self.errorMessage = error.localizedDescription
                    self.isLoading = false
                }
            }
        }
    }

    
    func loadWidgetData(
        tmdbService: TMDBService,
        catalogManager: CatalogManager
    ) {
        let enabledCatalogs = catalogManager.getEnabledCatalogs()
        
        Task {
            // Ranked lists reuse existing catalog data — zero extra API calls
            let rankedMappings: [(catalogId: String, sourceKey: String)] = [
                ("bestTVShows", "topRatedTVShows"),
                ("bestMovies", "topRatedMovies"),
                ("bestAnime", "topRatedAnime")
            ]
            let currentResults = await MainActor.run { self.catalogResults }
            for mapping in rankedMappings {
                if enabledCatalogs.contains(where: { $0.id == mapping.catalogId }),
                   let items = currentResults[mapping.sourceKey], !items.isEmpty {
                    await MainActor.run {
                        self.widgetData[mapping.catalogId] = items
                    }
                }
            }
            
            // Networks — parallel discover calls
            if enabledCatalogs.contains(where: { $0.id == "networks" }) {
                await withTaskGroup(of: (Int, [TMDBSearchResult]).self) { group in
                    for network in WidgetNetwork.curated {
                        group.addTask {
                            let results = (try? await tmdbService.discoverByNetwork(networkId: network.id)) ?? []
                            return (network.id, results)
                        }
                    }
                    for await (networkId, results) in group {
                        if !results.isEmpty {
                            await MainActor.run {
                                self.widgetData["network_\(networkId)"] = results
                            }
                        }
                    }
                }
            }
            
            // Genres — parallel discover calls
            if enabledCatalogs.contains(where: { $0.id == "genres" }) {
                await withTaskGroup(of: (Int, [TMDBSearchResult]).self) { group in
                    for genre in WidgetGenre.curated {
                        group.addTask {
                            let results = (try? await tmdbService.discoverByGenre(genreId: genre.id)) ?? []
                            return (genre.id, results)
                        }
                    }
                    for await (genreId, results) in group {
                        if !results.isEmpty {
                            await MainActor.run {
                                self.widgetData["genre_\(genreId)"] = results
                            }
                        }
                    }
                }
            }
            
            // Companies — parallel discover calls
            if enabledCatalogs.contains(where: { $0.id == "companies" }) {
                await withTaskGroup(of: (Int, [TMDBSearchResult]).self) { group in
                    for company in WidgetCompany.curated {
                        group.addTask {
                            let results = (try? await tmdbService.discoverByCompany(companyId: company.id)) ?? []
                            return (company.id, results)
                        }
                    }
                    for await (companyId, results) in group {
                        if !results.isEmpty {
                            await MainActor.run {
                                self.widgetData["company_\(companyId)"] = results
                            }
                        }
                    }
                }
            }
            
            // Featured — pick a random popular genre
            if enabledCatalogs.contains(where: { $0.id == "featured" }) {
                let randomGenre = WidgetGenre.curated.randomElement() ?? WidgetGenre.curated[0]
                let results = (try? await tmdbService.discoverByGenre(genreId: randomGenre.id, mediaType: "tv")) ?? []
                if !results.isEmpty {
                    await MainActor.run {
                        self.widgetData["featured"] = results
                        self.widgetData["featured_genreName"] = [] // Store genre name via key convention
                    }
                    // Store the genre name for display
                    await MainActor.run {
                        self.featuredGenreName = randomGenre.name
                    }
                }
            }
        }
    }
    
    @Published var featuredGenreName: String = ""
    
    func resetContent() {
        catalogResults = [:]
        widgetData = [:]
        isLoading = true
        errorMessage = nil
        heroContent = nil
        hasLoadedContent = false
        featuredGenreName = ""
        becauseYouWatchedTitle = ""
        RecommendationEngine.shared.invalidateCache()
    }
}
