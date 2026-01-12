//
//  HomeSection.swift
//  Sora
//
//  Created by Francesco on 11/09/25.
//

import Foundation

struct HomeSection: Identifiable, Codable {
    let id: String
    let title: String
    var isEnabled: Bool
    var order: Int
    
    static let defaultSections = [
        HomeSection(id: "trending", title: "Trending This Week", isEnabled: true, order: 0),
        HomeSection(id: "popularMovies", title: "Popular Movies", isEnabled: true, order: 1),
        HomeSection(id: "nowPlayingMovies", title: "Now Playing Movies", isEnabled: false, order: 2),
        HomeSection(id: "upcomingMovies", title: "Upcoming Movies", isEnabled: false, order: 3),
        HomeSection(id: "popularTVShows", title: "Popular TV Shows", isEnabled: true, order: 4),
        HomeSection(id: "onTheAirTV", title: "On The Air TV Shows", isEnabled: false, order: 5),
        HomeSection(id: "airingTodayTV", title: "Airing Today TV Shows", isEnabled: false, order: 6),
        HomeSection(id: "topRatedTVShows", title: "Top Rated TV Shows", isEnabled: true, order: 7),
        HomeSection(id: "topRatedMovies", title: "Top Rated Movies", isEnabled: true, order: 8),
        HomeSection(id: "trendingAnime", title: "Trending Anime", isEnabled: true, order: 9),
        HomeSection(id: "popularAnime", title: "Popular Anime", isEnabled: true, order: 10),
        HomeSection(id: "topRatedAnime", title: "Top Rated Anime", isEnabled: true, order: 11),
        HomeSection(id: "airingAnime", title: "Currently Airing Anime", isEnabled: false, order: 12),
        HomeSection(id: "upcomingAnime", title: "Upcoming Anime", isEnabled: false, order: 13)
    ]
}
