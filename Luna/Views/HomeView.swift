//
//  HomeView.swift
//  Sora
//
//  Created by Francesco on 07/08/25.
//

import SwiftUI
import Kingfisher

struct DetailLaunch: Identifiable {
    let id = UUID()
    let searchResult: TMDBSearchResult
    let resumeHint: EpisodeResumeHint?
    let autoPlay: Bool
}

struct HomeView: View {
    @State private var showingSettings = false
    @State private var catalogResults: [String: [TMDBSearchResult]] = [:]
    @State private var isLoading = true
    @State private var errorMessage: String?
    @State private var heroContent: TMDBSearchResult?
    @State private var ambientColor: Color = Color.black
    @State private var isHoveringWatchNow = false
    @State private var isHoveringWatchlist = false

    @State private var hasLoadedContent = false
    
    @StateObject private var catalogManager = CatalogManager.shared
    @StateObject private var tmdbService = TMDBService.shared
    @StateObject private var contentFilter = TMDBContentFilter.shared
    @StateObject private var continueVM = ContinueWatchingViewModel()
    @State private var continueDetailToShow: DetailLaunch? = nil
    
    private var heroHeight: CGFloat {
#if os(tvOS)
        UIScreen.main.bounds.height * 0.8
#else
        580
#endif
    }

    private var enabledCatalogs: [Catalog] {
        // Access the @Published property directly to ensure view updates when catalogs change
        _ = catalogManager.catalogs // Trigger observation
        return catalogManager.getEnabledCatalogs()
    }
    
    var body: some View {
        if #available(iOS 16.0, *) {
            NavigationStack {
                homeContent
            }
        } else {
            NavigationView {
                homeContent
            }
            .navigationViewStyle(StackNavigationViewStyle())
        }
    }
    
    private var homeContent: some View {
        ZStack {
            Group {
                ambientColor
            }
            .ignoresSafeArea(.all)
            
            if isLoading {
                loadingView
            } else if let errorMessage = errorMessage {
                errorView(errorMessage)
            } else {
                mainScrollView
            }
        }
        .navigationBarHidden(true)
        .onAppear {
            if !hasLoadedContent {
                loadContent()
            }
        }
        .onReceive(NotificationCenter.default.publisher(for: Notification.Name("ContinueWatchingOpenDetail"))) { note in
            guard let userInfo = note.userInfo else { return }
            if let tmdbId = userInfo["tmdbId"] as? Int, let isMovie = userInfo["isMovie"] as? Bool {
                if isMovie {
                    let title = userInfo["title"] as? String
                    let sr = TMDBSearchResult(id: tmdbId, mediaType: "movie", title: title, name: nil, overview: nil, posterPath: nil, backdropPath: nil, releaseDate: nil, firstAirDate: nil, voteAverage: nil, popularity: 0.0, adult: nil, genreIds: nil)
                    let autoPlay = (userInfo["autoPlay"] as? Bool) ?? false
                    continueDetailToShow = DetailLaunch(searchResult: sr, resumeHint: nil, autoPlay: autoPlay)
                } else {
                    let title = userInfo["title"] as? String
                    let sr = TMDBSearchResult(id: tmdbId, mediaType: "tv", title: nil, name: title, overview: nil, posterPath: nil, backdropPath: nil, releaseDate: nil, firstAirDate: nil, voteAverage: nil, popularity: 0.0, adult: nil, genreIds: nil)
                    var hint: EpisodeResumeHint? = nil
                    if let season = userInfo["seasonNumber"] as? Int, let episode = userInfo["episodeNumber"] as? Int {
                        hint = EpisodeResumeHint(showId: tmdbId, season: season, episode: episode)
                    }
                    let autoPlay = (userInfo["autoPlay"] as? Bool) ?? false
                    continueDetailToShow = DetailLaunch(searchResult: sr, resumeHint: hint, autoPlay: autoPlay)
                }
            }
        }
        .onChangeComp(of: contentFilter.filterHorror) { _, _ in
            if hasLoadedContent {
                loadContent()
            }
        }
        .sheet(isPresented: $showingSettings) {
            SettingsView()
        }
        .sheet(item: $continueDetailToShow) { launch in
            MediaDetailView(searchResult: launch.searchResult, resumeHint: launch.resumeHint, autoPlay: launch.autoPlay)
        }
    }
    
    @ViewBuilder
    private var loadingView: some View {
        VStack(spacing: 16) {
            ProgressView()
                .scaleEffect(1.5)
            Text("Loading amazing content...")
                .font(.caption)
                .foregroundColor(.secondary)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
    
    @ViewBuilder
    private func errorView(_ message: String) -> some View {
        VStack(spacing: 16) {
            Image(systemName: "wifi.slash")
                .font(.system(size: 50))
                .foregroundColor(.orange)
            
            Text("Connection Error")
                .font(.title2)
                .fontWeight(.semibold)
            
            Text(message)
                .font(.body)
                .foregroundColor(.secondary)
                .multilineTextAlignment(.center)
                .padding(.horizontal, 40)
            
            Button("Retry") {
                loadContent()
            }
            .padding(.horizontal, 24)
            .padding(.vertical, 12)
            .foregroundColor(.white)
            .cornerRadius(8)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
    
    @ViewBuilder
    private var mainScrollView: some View {
        ScrollView(showsIndicators: false) {
            LazyVStack(spacing: 0) {
                heroSection
                contentSections
            }
        }
        .ignoresSafeArea(edges: [.top, .leading, .trailing])
    }
    
    @ViewBuilder
    private var heroSection: some View {
        ZStack(alignment: .bottom) {
            StretchyHeaderView(
                backdropURL: heroContent?.fullBackdropURL ?? heroContent?.fullPosterURL,
                isMovie: heroContent?.isMovie ?? true,
                headerHeight: heroHeight,
                minHeaderHeight: 300,
                onAmbientColorExtracted: { color in
                    ambientColor = color
                }
            )
            
            heroGradientOverlay
            heroContentInfo
        }
    }
    
    @ViewBuilder
    private var heroGradientOverlay: some View {
        LinearGradient(
            gradient: Gradient(stops: [
                .init(color: ambientColor.opacity(0.0), location: 0.0),
                .init(color: ambientColor.opacity(0.4), location: 0.2),
                .init(color: ambientColor.opacity(0.7), location: 0.6),
                .init(color: ambientColor.opacity(1), location: 1.0)
            ]),
            startPoint: .top,
            endPoint: .bottom
        )
        .frame(height: 150)
        .clipShape(RoundedRectangle(cornerRadius: 0))
    }
    
    @ViewBuilder
    private var heroContentInfo: some View {
        if let hero = heroContent {
            VStack(alignment: .center, spacing: isTvOS ? 30 : 12) {
                HStack {
                    Text(hero.isMovie ? "Movie" : "TV Series")
                        .font(.caption)
                        .fontWeight(.semibold)
                        .foregroundColor(.white)
                        .padding(.horizontal, isTvOS ? 16 : 8)
                        .padding(.vertical, isTvOS ? 10 : 4)
                        .applyLiquidGlassBackground(cornerRadius: 12)
                    
                    if (hero.voteAverage ?? 0.0) > 0 {
                        HStack(alignment: .firstTextBaseline, spacing: 2) {
                            Image(systemName: "star.fill")
                                .foregroundColor(.yellow)
                            
                            Text(String(format: "%.1f", hero.voteAverage ?? 0.0))
                                .fontWeight(.medium)
                                .foregroundColor(.white)
                        }
                        .font(.caption)
                        .foregroundColor(.white)
                        .padding(.horizontal, isTvOS ? 16 : 8)
                        .padding(.vertical, isTvOS ? 10 : 4)
                        .applyLiquidGlassBackground(cornerRadius: 12)
                    }
                }
                
                Text(hero.displayTitle)
                    .font(.system(size: isTvOS ? 40 : 25))
                    .fontWeight(.bold)
                    .shadow(color: .black.opacity(0.6), radius: 8, x: 0, y: 4)
                    .foregroundColor(.white)
                    .lineLimit(2)
                    .multilineTextAlignment(.center)
                
                if let overview = hero.overview, !overview.isEmpty {
                    Text(String(overview.prefix(100)) + (overview.count > 100 ? "..." : ""))
                        .font(.system(size: isTvOS ? 30 : 15))
                        .shadow(color: .black.opacity(0.6), radius: 8, x: 0, y: 4)
                        .foregroundColor(.white.opacity(0.9))
                        .lineLimit(2)
                        .multilineTextAlignment(.center)
                        .padding(.horizontal, 20)
                }
                
                HStack(spacing: 16) {
                    NavigationLink(destination: MediaDetailView(searchResult: hero)) {
                        HStack(spacing: 8) {
                            Image(systemName: "play.fill")
                                .font(.subheadline)
                            Text("Watch Now")
                                .fontWeight(.semibold)
                                .fixedSize()
                                .lineLimit(1)
                        }
                        .foregroundColor(isHoveringWatchNow ? .black : .white)
                        .tvos({ view in
                            view.frame(width: 200, height: 60)
                                .buttonStyle(PlainButtonStyle())
#if os(tvOS)
                                .onContinuousHover { phase in
                                    switch phase {
                                    case .active(_): isHoveringWatchNow = true
                                    case .ended: isHoveringWatchNow = false
                                    }
                                }
#endif
                        }, else: { view in
                            view
                                .frame(width: 140, height: 42)
                                .buttonStyle(PlainButtonStyle())
                                .applyLiquidGlassBackground(cornerRadius: 12)
                        })
                    }
                    
                    Button(action: {
                        // TODO: Add to watchlist
                    }) {
                        HStack(spacing: 8) {
                            Image(systemName: "plus")
                                .font(.subheadline)
                            Text("Watchlist")
                                .fontWeight(.semibold)
                                .fixedSize()
                                .lineLimit(1)
                        }
                        .foregroundColor(isHoveringWatchlist ? .black : .white)
                        .tvos({ view in
                            view.frame(width: 200, height: 60)
                                .buttonStyle(PlainButtonStyle())
#if os(tvOS)
                                .onContinuousHover { phase in
                                    switch phase {
                                    case .active(_): isHoveringWatchlist = true
                                    case .ended: isHoveringWatchlist = false
                                    }
                                }
#endif
                        }, else: { view in
                            view.frame(width: 140, height: 42)
                                .background(
                                    RoundedRectangle(cornerRadius: 12)
                                        .fill(Color.black.opacity(0.3))
                                        .background(
                                            RoundedRectangle(cornerRadius: 12)
                                                .stroke(.white.opacity(0.3), lineWidth: 1)
                                        )
                                )
                        })
                        .shadow(color: .black.opacity(0.1), radius: 4, x: 0, y: 2)
                    }
                }
            }
            .frame(maxWidth: .infinity)
            .padding(.horizontal)
        }
    }
    
    @ViewBuilder
    private var contentSections: some View {
        VStack(spacing: 0) {
            // Continue Watching unified section
            if !continueVM.entries.isEmpty {
                VStack(alignment: .leading, spacing: 16) {
                    HStack {
                        Text("Continue Watching")
                            .font(isTvOS ? .headline : .title2)
                            .fontWeight(.bold)
                            .foregroundColor(.white)
                        Spacer()
                    }
                    .padding(.horizontal, isTvOS ? 40 : 16)

                    ScrollView(.horizontal, showsIndicators: false) {
                        LazyHStack(spacing: isTvOS ? 50.0 : 20.0) {
                            ForEach(continueVM.entries) { entry in
                                ContinueWatchingCard(entry: entry,
                                                     onResume: { e in continueVM.resume(e) },
                                                     onPlayFromStart: { e in continueVM.playFromStart(e) })
                            }
                        }
                        .padding(.horizontal, isTvOS ? 40 : 16)
                    }
                    .modifier(ScrollClipModifier())
                    .buttonStyle(.borderless)
                }
                .padding(.top, isTvOS ? 40 : 24)
                .opacity(continueVM.entries.isEmpty ? 0 : 1)
            }
            
            // Display all enabled catalogs
            ForEach(enabledCatalogs) { catalog in
                if let items = catalogResults[catalog.id], !items.isEmpty {
                    let limitedItems = Array(items.prefix(15))
                    let displayItems = catalog.id == "trending"
                        ? limitedItems.filter { $0.id != heroContent?.id }
                        : limitedItems
                    MediaSection(
                        title: catalog.name,
                        items: displayItems
                    )
                }
            }
            
            Spacer(minLength: 50)
        }
        .background(Color.clear)
    }
    
    private func loadContent() {
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

                async let trendingAnime = AniListService.shared.fetchAnimeCatalog(.trending, limit: 20, tmdbService: tmdbService)
                async let popularAnime = AniListService.shared.fetchAnimeCatalog(.popular, limit: 20, tmdbService: tmdbService)
                async let topRatedAnime = AniListService.shared.fetchAnimeCatalog(.topRated, limit: 20, tmdbService: tmdbService)
                async let airingAnime = AniListService.shared.fetchAnimeCatalog(.airing, limit: 50, tmdbService: tmdbService)
                async let upcomingAnime = AniListService.shared.fetchAnimeCatalog(.upcoming, limit: 50, tmdbService: tmdbService)
                
                let (
                    trendingResult,
                    popularMoviesResult,
                    nowPlayingMoviesResult,
                    upcomingMoviesResult,
                    popularTVResult,
                    onTheAirTVResult,
                    airingTodayTVResult,
                    topRatedTVResult,
                    topRatedMoviesResult,
                    trendingAnimeResult,
                    popularAnimeResult,
                    topRatedAnimeResult,
                    airingAnimeResult,
                    upcomingAnimeResult
                ) = try await (
                    trending,
                    popularM,
                    nowPlayingM,
                    upcomingM,
                    popularTV,
                    onTheAirTV,
                    airingTodayTV,
                    topRatedTV,
                    topRatedM,
                    trendingAnime,
                    popularAnime,
                    topRatedAnime,
                    airingAnime,
                    upcomingAnime
                )
                
                await MainActor.run {
                    withAnimation(.easeInOut(duration: 0.5)) {
                        var updated: [String: [TMDBSearchResult]] = [:]
                        updated["trending"] = contentFilter.filterSearchResults(trendingResult)
                        updated["popularMovies"] = contentFilter.filterMovies(popularMoviesResult).map { $0.asSearchResult }
                        updated["nowPlayingMovies"] = contentFilter.filterMovies(nowPlayingMoviesResult).map { $0.asSearchResult }
                        updated["upcomingMovies"] = contentFilter.filterMovies(upcomingMoviesResult).map { $0.asSearchResult }
                        updated["popularTVShows"] = contentFilter.filterTVShows(popularTVResult).map { $0.asSearchResult }
                        updated["onTheAirTV"] = contentFilter.filterTVShows(onTheAirTVResult).map { $0.asSearchResult }
                        updated["airingTodayTV"] = contentFilter.filterTVShows(airingTodayTVResult).map { $0.asSearchResult }
                        updated["topRatedTVShows"] = contentFilter.filterTVShows(topRatedTVResult).map { $0.asSearchResult }
                        updated["topRatedMovies"] = contentFilter.filterMovies(topRatedMoviesResult).map { $0.asSearchResult }
                        updated["trendingAnime"] = contentFilter.filterSearchResults(trendingAnimeResult)
                        updated["popularAnime"] = contentFilter.filterSearchResults(popularAnimeResult)
                        updated["topRatedAnime"] = contentFilter.filterSearchResults(topRatedAnimeResult)
                        updated["airingAnime"] = contentFilter.filterSearchResults(airingAnimeResult)
                        updated["upcomingAnime"] = contentFilter.filterSearchResults(upcomingAnimeResult)

                        self.catalogResults = updated
                        
                        // Log all catalog data for debugging
                        Logger.shared.log("Loaded \(updated.count) catalog types with data", type: "HomeView")
                        for (catalogId, items) in updated {
                            Logger.shared.log("  \(catalogId): \(items.count) items", type: "HomeView")
                        }
                        
                        Logger.shared.log("Enabled catalogs: \(self.enabledCatalogs.map { $0.id }.joined(separator: ", "))", type: "HomeView")

                        let heroPool = !(updated["trending"] ?? []).isEmpty ? (updated["trending"] ?? []) : updated.values.flatMap { $0 }
                        self.heroContent = heroPool.first { $0.backdropPath != nil } ?? heroPool.first
                        self.isLoading = false
                        self.hasLoadedContent = true
                    }
                }
            } catch {
                await MainActor.run {
                    self.errorMessage = error.localizedDescription
                    self.isLoading = false
                    Logger.shared.log("Error loading content: \(error)", type: "Error")
                }
            }
        }
    }
}

struct MediaSection: View {
    let title: String
    let items: [TMDBSearchResult]
    let isLarge: Bool
    
    var gap: Double { isTvOS ? 50.0 : 20.0 }
    
    init(title: String, items: [TMDBSearchResult], isLarge: Bool = Bool.random()) {
        self.title = title
        self.items = items
        self.isLarge = isLarge
    }
    
    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            HStack {
                Text(title)
                    .font(isTvOS ? .headline : .title2)
                    .fontWeight(.bold)
                    .foregroundColor(.white)
                Spacer()
            }
            .padding(.horizontal, isTvOS ? 40 : 16)
            
            ScrollView(.horizontal, showsIndicators: false) {
                LazyHStack(spacing: gap) {
                    ForEach(items) { item in
                        MediaCard(result: item)
                    }
                }
                .padding(.horizontal, isTvOS ? 40 : 16)
            }
            .modifier(ScrollClipModifier())
            .buttonStyle(.borderless)
        }
        .padding(.top, isTvOS ? 40 : 24)
        .opacity(items.isEmpty ? 0 : 1)
    }
}

struct ScrollClipModifier: ViewModifier {
    func body(content: Content) -> some View {
        if #available(iOS 17.0, *) {
            content.scrollClipDisabled()
        } else {
            content
        }
    }
}

struct MediaCard: View {
    let result: TMDBSearchResult
    @State private var isHovering: Bool = false
    
    var body: some View {
        NavigationLink(destination: MediaDetailView(searchResult: result)) {
            VStack(alignment: .leading, spacing: 6) {
                KFImage(URL(string: result.fullPosterURL ?? ""))
                    .placeholder {
                        FallbackImageView(
                            isMovie: result.isMovie,
                            size: CGSize(width: 120, height: 180)
                        )
                    }
                    .resizable()
                    .aspectRatio(2/3, contentMode: .fill)
                    .tvos({ view in
                        view
                            .frame(width: 280, height: 380)
                            .clipShape(RoundedRectangle(cornerRadius: 20))
                            .hoverEffect(.highlight)
                            .modifier(ContinuousHoverModifier(isHovering: $isHovering))
                            .padding(.vertical, 30)
                    }, else: { view in
                        view
                            .frame(width: 120, height: 180)
                            .clipShape(RoundedRectangle(cornerRadius: 10))
                            .shadow(color: .black.opacity(0.1), radius: 3, x: 0, y: 1)
                    })
                
                VStack(alignment: .leading, spacing: isTvOS ? 10 : 3) {
                    Text(result.displayTitle)
                        .tvos({ view in
                            view
                                .foregroundColor(isHovering ? .white : .secondary)
                                .fontWeight(.semibold)
                        }, else: { view in
                            view
                                .foregroundColor(.white)
                                .fontWeight(.medium)
                        })
                        .font(.caption)
                        .lineLimit(1)
                        .multilineTextAlignment(.center)
                        .frame(maxWidth: .infinity, alignment: .center)

                    HStack(alignment: .center, spacing: isTvOS ? 18 : 8) {
                        HStack(alignment: .firstTextBaseline, spacing: 4) {
                            Image(systemName: "star.fill")
                                .font(.caption2)
                                .foregroundColor(.yellow)
                            
                            Text(String(format: "%.1f", result.voteAverage ?? 0.0))
                                .font(.caption2)
                                .foregroundColor(.white)
                                .lineLimit(1)
                                .fixedSize()
                        }
                            .padding(.horizontal, isTvOS ? 16 : 8)
                            .padding(.vertical, isTvOS ? 10 : 4)
                            .applyLiquidGlassBackground(cornerRadius: 12)

                        Spacer()

                        Text(result.isMovie ? "Movie" : "TV")
                            .font(.caption2)
                            .foregroundColor(.white)
                            .lineLimit(1)
                            .fixedSize()
                            .padding(.horizontal, isTvOS ? 16 : 8)
                            .padding(.vertical, isTvOS ? 10 : 4)
                            .applyLiquidGlassBackground(cornerRadius: 12)
                    }
                }
                .frame(width: isTvOS ? 280 : 120, alignment: .leading)
            }
        }
        .tvos({ view in
            view.buttonStyle(BorderlessButtonStyle())
        }, else: { view in
            view.buttonStyle(PlainButtonStyle())
        })
    }
}

struct ContinueWatchingCard: View {
    let entry: ContinueWatchingEntry
    var onResume: (ContinueWatchingEntry) -> Void
    var onPlayFromStart: (ContinueWatchingEntry) -> Void
    @State private var isHovering: Bool = false
    @State private var showDetail: Bool = false
    @State private var showActions: Bool = false

    private func makeSearchResult() -> TMDBSearchResult? {
        switch entry.type {
        case .movie:
            if let idStr = entry.id.split(separator: "_").last, let movieId = Int(idStr) {
                return TMDBSearchResult(id: movieId, mediaType: "movie", title: entry.showTitle ?? entry.title, name: nil, overview: nil, posterPath: entry.imageURL?.replacingOccurrences(of: TMDBService.tmdbImageBaseURL, with: "") , backdropPath: nil, releaseDate: nil, firstAirDate: nil, voteAverage: nil, popularity: 0.0, adult: nil, genreIds: nil)
            }
            return nil
        case .episode:
            if let showId = entry.showId {
                return TMDBSearchResult(id: showId, mediaType: "tv", title: nil, name: entry.showTitle ?? entry.title, overview: nil, posterPath: entry.imageURL?.replacingOccurrences(of: TMDBService.tmdbImageBaseURL, with: ""), backdropPath: nil, releaseDate: nil, firstAirDate: nil, voteAverage: nil, popularity: 0.0, adult: nil, genreIds: nil)
            }
            return nil
        }
    }

    var body: some View {
        Button(action: {
            onResume(entry)
        }) {
            VStack(alignment: .leading, spacing: 6) {
                if let urlStr = entry.imageURL, let url = URL(string: urlStr) {
                    KFImage(url)
                        .placeholder {
                            FallbackImageView(isMovie: entry.type == .movie, size: CGSize(width: 120, height: 180))
                        }
                        .resizable()
                        .aspectRatio(2/3, contentMode: .fill)
                        .frame(width: 120, height: 180)
                        .clipShape(RoundedRectangle(cornerRadius: 10))
                        .shadow(color: .black.opacity(0.1), radius: 3, x: 0, y: 1)
                } else {
                    FallbackImageView(isMovie: entry.type == .movie, size: CGSize(width: 120, height: 180))
                        .frame(width: 120, height: 180)
                        .clipShape(RoundedRectangle(cornerRadius: 10))
                        .shadow(color: .black.opacity(0.1), radius: 3, x: 0, y: 1)
                }

                VStack(alignment: .leading, spacing: isTvOS ? 10 : 3) {
                    Text(entry.showTitle ?? entry.title)
                        .foregroundColor(.white)
                        .fontWeight(.medium)
                        .font(.caption)
                        .lineLimit(1)
                        .multilineTextAlignment(.center)
                        .frame(maxWidth: .infinity, alignment: .center)

                    if entry.type == .episode, let season = entry.seasonNumber, let ep = entry.episodeNumber {
                        Text("S\(season)E\(ep)")
                            .foregroundColor(.white.opacity(0.8))
                            .font(.caption2)
                            .lineLimit(1)
                            .multilineTextAlignment(.center)
                            .frame(maxWidth: .infinity, alignment: .center)
                    }

                    HStack(alignment: .center, spacing: isTvOS ? 18 : 8) {
                        ProgressView(value: entry.currentTime, total: max(entry.totalDuration, 1))
                            .progressViewStyle(LinearProgressViewStyle(tint: .green))
                            .frame(width: 60)

                        Spacer()

                        Text(entry.type == .movie ? "Movie" : "TV")
                            .font(.caption2)
                            .foregroundColor(.white)
                            .lineLimit(1)
                            .fixedSize()
                            .padding(.horizontal, isTvOS ? 16 : 8)
                            .padding(.vertical, isTvOS ? 10 : 4)
                            .applyLiquidGlassBackground(cornerRadius: 12)
                    }
                }
                .frame(width: 120, alignment: .leading)
            }
        }
        .buttonStyle(PlainButtonStyle())
        .onLongPressGesture {
            // show action sheet on touch devices
            showActions = true
        }
        .contextMenu {
            Button(action: {
                // Open details from context menu
                showDetail = true
            }) {
                Text("Open Details")
            }

            Button(action: {
                // Resume playback
                onResume(entry)
            }) {
                Text("Resume")
            }

            Button(action: {
                onPlayFromStart(entry)
            }) {
                Text("Play from Beginning")
            }
        }
        #if os(macOS) || targetEnvironment(macCatalyst)
        .onTapGesture(count: 2) {
            // double-click to resume on mac
            onResume(entry)
        }
        #endif
        .confirmationDialog("Continue Watching", isPresented: $showActions, titleVisibility: .visible) {
            Button(action: { onResume(entry) }) {
                Text("Resume")
            }
            Button(action: { onPlayFromStart(entry) }) {
                Text("Play from Beginning")
            }
            Button(action: { showDetail = true }) {
                Text("Show Details")
            }
            Button("Cancel", role: .cancel) {}
        }
        .background(
            // hidden NavigationLink for long-press or context-menu -> details
            Group {
                if let sr = makeSearchResult() {
                    NavigationLink(destination: MediaDetailView(searchResult: sr), isActive: $showDetail) {
                        EmptyView()
                    }.hidden()
                } else {
                    EmptyView()
                }
            }
        )
    }
}

struct ContinuousHoverModifier: ViewModifier {
    @Binding var isHovering: Bool
    
    func body(content: Content) -> some View {
        if #available(iOS 17.0, *) {
            content
                .onContinuousHover { phase in
                    switch phase {
                    case .active(_):
                        isHovering = true
                    case .ended:
                        isHovering = false
                    }
                }
        } else {
            content
        }
    }
}
