//
//  HomeViewModel.swift
//  Luna
//
//  Created by Soupy-dev
//

import Foundation
import SwiftUI
import Combine

final class HomeViewModel: ObservableObject {
    static let shared = HomeViewModel()
    
    @Published var catalogResults: [String: [TMDBSearchResult]] = [:]
    @Published var isLoading = true
    @Published var errorMessage: String?
    @Published var heroContent: TMDBSearchResult?
    @Published var ambientColor: Color = Color.black
    @Published var heroLogoURL: String?
    @Published var continueWatchingItems: [ContinueWatchingItem] = []
    @Published var hasLoadedContent = false
    
    private var cancellables = Set<AnyCancellable>()
    
    private init() {
        // Monitor progress manager for continue watching updates
        ProgressManager.shared.$episodeProgressList
            .receive(on: DispatchQueue.main)
            .sink { [weak self] _ in
                self?.updateContinueWatchingItems()
            }
            .store(in: &cancellables)
        
        ProgressManager.shared.$movieProgressList
            .receive(on: DispatchQueue.main)
            .sink { [weak self] _ in
                self?.updateContinueWatchingItems()
            }
            .store(in: &cancellables)
    }
    
    func loadContent(
        tmdbService: TMDBService,
        catalogManager: CatalogManager,
        contentFilter: TMDBContentFilter
    ) {
        // Don't reload if we already have content
        guard !hasLoadedContent else {
            updateContinueWatchingItems()
            return
        }
        
        isLoading = true
        errorMessage = nil
        continueWatchingItems = ProgressManager.shared.getContinueWatchingItems()
        
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
                async let trendingAnime = tmdbService.getTrendingAnime()
                async let popularAnime = tmdbService.getPopularAnime()
                async let topRatedAnime = tmdbService.getTopRatedAnime()
                async let airingAnime = tmdbService.getAiringAnime()
                async let upcomingAnime = tmdbService.getUpcomingAnime()
                
                let results = try await (
                    trending, popularM, nowPlayingM, upcomingM, popularTV, onTheAirTV,
                    airingTodayTV, topRatedTV, topRatedM, trendingAnime, popularAnime,
                    topRatedAnime, airingAnime, upcomingAnime
                )
                
                await MainActor.run {
                    self.catalogResults = [
                        "trending": results.0,
                        "popularMovies": results.1,
                        "nowPlayingMovies": results.2,
                        "upcomingMovies": results.3,
                        "popularTVShows": results.4,
                        "onTheAirTV": results.5,
                        "airingTodayTV": results.6,
                        "topRatedTVShows": results.7,
                        "topRatedMovies": results.8,
                        "trendingAnime": results.9,
                        "popularAnime": results.10,
                        "topRatedAnime": results.11,
                        "airingAnime": results.12,
                        "upcomingAnime": results.13
                    ]
                    
                    // Set hero content from trending
                    if let hero = results.0.first {
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
    
    func updateContinueWatchingItems() {
        continueWatchingItems = ProgressManager.shared.getContinueWatchingItems()
    }
    
    func resetContent() {
        catalogResults = [:]
        isLoading = true
        errorMessage = nil
        heroContent = nil
        heroLogoURL = nil
        hasLoadedContent = false
        continueWatchingItems = []
    }
}
