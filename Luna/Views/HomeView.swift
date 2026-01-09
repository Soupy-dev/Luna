//
//  HomeView.swift
//  Sora

import SwiftUI
import Kingfisher

struct HomeView: View {
    @State private var showingSettings = false
    @State private var isHoveringWatchNow = false
    @State private var isHoveringWatchlist = false
    
    @AppStorage("tmdbLanguage") private var selectedLanguage = "en-US"
    
    @StateObject private var homeViewModel = HomeViewModel()
    @ObservedObject private var catalogManager = CatalogManager.shared
    @StateObject private var tmdbService = TMDBService.shared
    @StateObject private var contentFilter = TMDBContentFilter.shared
    
    private var enabledCatalogs: [Catalog] {
        return catalogManager.getEnabledCatalogs()
    }
    
    private var heroHeight: CGFloat {
#if os(tvOS)
        UIScreen.main.bounds.height * 0.8
#else
        580
#endif
    }

    private var ambientColor: Color { homeViewModel.ambientColor }
    
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
                homeViewModel.ambientColor
            }
            .ignoresSafeArea(.all)
            
            if homeViewModel.isLoading {
                loadingView
            } else if let errorMessage = homeViewModel.errorMessage {
                errorView(errorMessage)
            } else {
                mainScrollView
            }
        }
        .navigationBarHidden(true)
        .onAppear {
            if !homeViewModel.hasLoadedContent {
                homeViewModel.loadContent(tmdbService: tmdbService, catalogManager: catalogManager, contentFilter: contentFilter)
            } else {
                homeViewModel.updateContinueWatchingItems()
            }
        }
        .onChangeComp(of: contentFilter.filterHorror) { _, _ in
            if homeViewModel.hasLoadedContent {
                homeViewModel.loadContent(tmdbService: tmdbService, catalogManager: catalogManager, contentFilter: contentFilter)
            }
        }
        .sheet(isPresented: $showingSettings) {
            SettingsView()
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
                continueWatchingSection
                contentSections
            }
        }
        .ignoresSafeArea(edges: [.top, .leading, .trailing])
    }
    
    @ViewBuilder
    private var continueWatchingSection: some View {
        if !homeViewModel.continueWatchingItems.isEmpty {
            ContinueWatchingSection(
                items: homeViewModel.continueWatchingItems,
                tmdbService: tmdbService
            )
        }
    }
    
    @ViewBuilder
    private var heroSection: some View {
        ZStack(alignment: .bottom) {
            StretchyHeaderView(
                backdropURL: homeViewModel.heroContent?.fullBackdropURL ?? homeViewModel.heroContent?.fullPosterURL,
                isMovie: homeViewModel.heroContent?.mediaType == "movie",
                headerHeight: heroHeight,
                minHeaderHeight: 300,
                onAmbientColorExtracted: { color in
                    homeViewModel.ambientColor = color
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
        if let hero = homeViewModel.heroContent {
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
                
                if let heroLogoURL = homeViewModel.heroLogoURL {
                    KFImage(URL(string: heroLogoURL))
                        .placeholder {
                            heroTitleText(hero)
                        }
                        .resizable()
                        .aspectRatio(contentMode: .fit)
                        .frame(maxWidth: isTvOS ? 400 : 280, maxHeight: isTvOS ? 120 : 80)
                        .shadow(color: .black.opacity(0.6), radius: 8, x: 0, y: 4)
                } else {
                    heroTitleText(hero)
                }
                
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
    private func heroTitleText(_ hero: TMDBSearchResult) -> some View {
        Text(hero.displayTitle)
            .font(.system(size: isTvOS ? 40 : 25))
            .fontWeight(.bold)
            .shadow(color: .black.opacity(0.6), radius: 8, x: 0, y: 4)
            .foregroundColor(.white)
            .lineLimit(2)
            .multilineTextAlignment(.center)
    }
    
    @ViewBuilder
    private var contentSections: some View {
        VStack(spacing: 0) {
            // Display all enabled catalogs
            ForEach(enabledCatalogs) { catalog in
                if let items = homeViewModel.catalogResults[catalog.id], !items.isEmpty {
                    let limitedItems = Array(items.prefix(15))
                    let displayItems = catalog.id == "trending"
                        ? limitedItems.filter { $0.id != homeViewModel.heroContent?.id }
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
        homeViewModel.loadContent(
            tmdbService: tmdbService,
            catalogManager: catalogManager,
            contentFilter: contentFilter
        )
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

// MARK: - Continue Watching Section

struct ContinueWatchingSection: View {
    let items: [ContinueWatchingItem]
    let tmdbService: TMDBService
    
    var gap: Double { isTvOS ? 50.0 : 16.0 }
    
    var body: some View {
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
                LazyHStack(spacing: gap) {
                    ForEach(items) { item in
                        ContinueWatchingCard(item: item, tmdbService: tmdbService)
                    }
                }
                .padding(.horizontal, isTvOS ? 40 : 16)
            }
            .modifier(ScrollClipModifier())
            .buttonStyle(.borderless)
        }
        .padding(.top, isTvOS ? 40 : 24)
    }
}

struct ContinueWatchingCard: View {
    let item: ContinueWatchingItem
    let tmdbService: TMDBService
    
    @AppStorage("tmdbLanguage") private var selectedLanguage = "en-US"
    
    @State private var posterURL: String?
    @State private var title: String
    @State private var isHovering: Bool = false
    @State private var isLoaded: Bool = false
    @State private var showingServices = false
    @State private var isAnime: Bool = false
    @State private var animeSeasonTitle: String?
    @State private var showingDetails = false
    
    init(item: ContinueWatchingItem, tmdbService: TMDBService) {
        self.item = item
        self.tmdbService = tmdbService
        // Initialize with data from item
        _posterURL = State(initialValue: item.posterURL)
        _title = State(initialValue: item.title.isEmpty ? (item.isMovie ? "Loading..." : "Loading...") : item.title)
    }
    
    private var cardWidth: CGFloat { isTvOS ? 280 : 120 }
    private var cardHeight: CGFloat { isTvOS ? 380 : 180 }
    private var logoMaxWidth: CGFloat { isTvOS ? 200 : 140 }
    private var logoMaxHeight: CGFloat { isTvOS ? 60 : 40 }
    
    var body: some View {
        Button(action: {
            showingServices = true
        }) {
            VStack(spacing: isTvOS ? 4 : 2) {
                // Poster
                ZStack {
                    if let posterURL = posterURL {
                        KFImage(URL(string: posterURL))
                            .placeholder {
                                posterPlaceholder
                            }
                            .resizable()
                            .aspectRatio(contentMode: .fill)
                    } else {
                        posterPlaceholder
                    }
                }
                .frame(width: cardWidth, height: cardWidth * 1.5)
                .clipped()
                .clipShape(RoundedRectangle(cornerRadius: isTvOS ? 8 : 6))
                
                // Title
                Text(title)
                    .font(isTvOS ? .caption : .caption2)
                    .fontWeight(.semibold)
                    .foregroundColor(.primary)
                    .lineLimit(1)
                    .multilineTextAlignment(.center)
                    .frame(width: cardWidth)
                
                // Episode info and remaining time
                HStack(spacing: isTvOS ? 8 : 6) {
                    if !item.isMovie, let season = item.seasonNumber, let episode = item.episodeNumber {
                        Text("S\(season)E\(episode)")
                            .font(.caption2)
                            .foregroundColor(.secondary)
                    }
                    
                    Spacer()
                    
                    Text(item.remainingTime)
                        .font(.caption2)
                        .foregroundColor(.secondary)
                }
                .frame(width: cardWidth)
                
                // Progress bar
                GeometryReader { geometry in
                    ZStack(alignment: .leading) {
                        RoundedRectangle(cornerRadius: 1)
                            .fill(Color.gray.opacity(0.3))
                            .frame(height: 2)
                        
                        RoundedRectangle(cornerRadius: 1)
                            .fill(Color.accentColor)
                            .frame(width: geometry.size.width * item.progress, height: 2)
                    }
                }
                .frame(height: 2)
                .frame(width: cardWidth)
            }
            .frame(width: cardWidth)
            .clipShape(RoundedRectangle(cornerRadius: isTvOS ? 12 : 8))
            .shadow(color: .black.opacity(0.2), radius: isHovering ? 8 : 4, x: 0, y: isHovering ? 6 : 3)
            .scaleEffect(isHovering ? 1.05 : 1.0)
            .animation(.easeInOut(duration: 0.2), value: isHovering)
            .modifier(ContinuousHoverModifier(isHovering: $isHovering))
        }
        .tvos({ view in
            view.buttonStyle(BorderlessButtonStyle())
        }, else: { view in
            view.buttonStyle(PlainButtonStyle())
        })
        .contextMenu {
            Button(action: {
                showingServices = true
            }) {
                Label("Resume", systemImage: "play.fill")
            }
            
            Button(action: {
                showingDetails = true
            }) {
                Label("Show Details", systemImage: "info.circle")
            }
        }
        .sheet(isPresented: $showingServices) {
            if isLoaded {
                ModulesSearchResultsSheet(
                    mediaTitle: title,
                    originalTitle: nil,
                    isMovie: item.isMovie,
                    selectedEpisode: item.isMovie ? nil : TMDBEpisode(
                        id: 0,
                        name: "",
                        overview: nil,
                        stillPath: nil,
                        episodeNumber: item.episodeNumber ?? 1,
                        seasonNumber: item.seasonNumber ?? 1,
                        airDate: nil,
                        runtime: nil,
                        voteAverage: 0,
                        voteCount: 0
                    ),
                    tmdbId: item.tmdbId,
                    animeSeasonTitle: isAnime ? animeSeasonTitle : nil,
                    posterPath: posterURL
                )
            }
        }
        .sheet(isPresented: $showingDetails) {
            if isLoaded {
                let searchResult = TMDBSearchResult(
                    id: item.tmdbId,
                    mediaType: item.isMovie ? "movie" : "tv",
                    title: item.isMovie ? title : nil,
                    name: item.isMovie ? nil : title,
                    overview: nil,
                    posterPath: nil,
                    backdropPath: nil,
                    releaseDate: nil,
                    firstAirDate: nil,
                    voteAverage: nil,
                    popularity: 0.0,
                    adult: nil,
                    genreIds: nil
                )
                
                MediaDetailView(searchResult: searchResult)
            }
        }
        .task {
            await loadMediaDetails()
        }
    }
    
    @ViewBuilder
    private var posterPlaceholder: some View {
        Rectangle()
            .fill(
                LinearGradient(
                    colors: [Color.gray.opacity(0.4), Color.gray.opacity(0.2)],
                    startPoint: .topLeading,
                    endPoint: .bottomTrailing
                )
            )
            .overlay(
                Image(systemName: item.isMovie ? "film" : "tv")
                    .font(isTvOS ? .largeTitle : .title)
                    .foregroundColor(.gray.opacity(0.5))
            )
    }
    
    private func loadMediaDetails() async {
        // Only load if we don't have title or poster
        guard title.isEmpty || posterURL == nil else {
            isLoaded = true
            return
        }
        
        do {
            if item.isMovie {
                async let detailsTask = tmdbService.getMovieDetails(id: item.tmdbId)
                let details = try await detailsTask
                
                await MainActor.run {
                    if self.title.isEmpty {
                        self.title = details.title
                    }
                    if self.posterURL == nil {
                        self.posterURL = details.fullPosterURL
                    }
                    self.isLoaded = true
                    
                    // Update progress manager with poster URL
                    if let posterURL = details.fullPosterURL {
                        ProgressManager.shared.updateMoviePoster(movieId: item.tmdbId, posterURL: posterURL)
                    }
                }
            } else {
                async let detailsTask = tmdbService.getTVShowDetails(id: item.tmdbId)
                let details = try await detailsTask
                
                // Check if this is anime
                let animeFlag = detectAnime(from: details)
                
                await MainActor.run {
                    if self.title.isEmpty {
                        self.title = details.name
                    }
                    if self.posterURL == nil {
                        self.posterURL = details.fullPosterURL
                    }
                    self.isAnime = animeFlag
                    self.isLoaded = true
                    
                    // Update progress manager with show metadata
                    ProgressManager.shared.updateShowMetadata(showId: item.tmdbId, title: details.name, posterURL: details.fullPosterURL)
                }
                
                // If anime, fetch season titles from AniList
                if animeFlag, let seasonNumber = item.seasonNumber {
                    do {
                        let aniDetails = try await AniListService.shared.fetchAnimeDetailsWithEpisodes(
                            title: details.name,
                            tmdbShowId: item.tmdbId,
                            tmdbService: tmdbService,
                            tmdbShowPoster: details.posterPath,
                            token: nil
                        )
                        
                        if let seasonTitle = aniDetails.seasons.first(where: { $0.seasonNumber == seasonNumber })?.title {
                            await MainActor.run {
                                self.animeSeasonTitle = seasonTitle
                            }
                        }
                    } catch {
                        Logger.shared.log("Failed to fetch anime season title: \(error.localizedDescription)", type: "Error")
                    }
                }
            }
        } catch {
            await MainActor.run {
                self.title = item.isMovie ? "Movie" : "TV Show"
                self.isLoaded = true
            }
        }
    }
    
    private func detectAnime(from detail: TMDBTVShowDetail) -> Bool {
        let genreAnime = detail.genres.contains { $0.id == 16 }
        let asianCountries: Set<String> = ["JP", "CN", "KR", "TW"]
        let hasAsianOrigin = (detail.originCountry ?? []).contains { asianCountries.contains($0) }
        // Require animation genre AND Asian origin to avoid misclassifying western animation
        return genreAnime && hasAsianOrigin
    }
}
