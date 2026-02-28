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
                
                // Fetch anime catalogs sequentially to respect AniList rate limits
                let trendingAnime = (try? await AniListService.shared.fetchAnimeCatalog(.trending, tmdbService: tmdbService)) ?? []
                let popularAnime = (try? await AniListService.shared.fetchAnimeCatalog(.popular, tmdbService: tmdbService)) ?? []
                let topRatedAnime = (try? await AniListService.shared.fetchAnimeCatalog(.topRated, tmdbService: tmdbService)) ?? []
                let airingAnime = (try? await AniListService.shared.fetchAnimeCatalog(.airing, tmdbService: tmdbService)) ?? []
                let upcomingAnime = (try? await AniListService.shared.fetchAnimeCatalog(.upcoming, tmdbService: tmdbService)) ?? []
                
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
            } catch {
                await MainActor.run {
                    self.errorMessage = error.localizedDescription
                    self.isLoading = false
                }
            }
        }
    }

    
    func resetContent() {
        catalogResults = [:]
        isLoading = true
        errorMessage = nil
        heroContent = nil
        hasLoadedContent = false
    }
}
