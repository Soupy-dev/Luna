//
//  MediaDetailView.swift
//  Sora
//
//  Created by Francesco on 07/08/25.
//

import SwiftUI
import Kingfisher

struct EpisodeResumeHint {
    let showId: Int
    let season: Int
    let episode: Int
}

struct MediaDetailView: View {
    let searchResult: TMDBSearchResult
    let resumeHint: EpisodeResumeHint?
    let autoPlay: Bool
    
    @StateObject private var tmdbService = TMDBService.shared
    @State private var movieDetail: TMDBMovieDetail?
    @State private var tvShowDetail: TMDBTVShowWithSeasons?
    @State private var selectedSeason: TMDBSeason?
    @State private var seasonDetail: TMDBSeasonDetail?
    @State private var isLoading = true
    @State private var errorMessage: String?
    @State private var ambientColor: Color = Color.black
    @State private var showFullSynopsis: Bool = false
    @State private var selectedEpisodeNumber: Int = 1
    @State private var selectedSeasonIndex: Int = 0
    @State private var synopsis: String = ""
    @State private var isBookmarked: Bool = false
    @State private var showingSearchResults = false
    @State private var showingAddToCollection = false
    @State private var selectedEpisodeForSearch: TMDBEpisode?
    @State private var romajiTitle: String?
    @State private var anilistEpisodes: [AniListEpisode]? = nil
    
    @StateObject private var serviceManager = ServiceManager.shared
    @ObservedObject private var libraryManager = LibraryManager.shared
    
    @Environment(\.presentationMode) var presentationMode
    @Environment(\.verticalSizeClass) private var verticalSizeClass
    @AppStorage("useSolidBackgroundBehindHero") private var useSolidBackgroundBehindHero = false
    @State private var pendingEpisodeSelection: (Int, Int)? = nil
    @State private var shouldAutoPlay = false
    @State private var isAnimeShow = false
    @State private var animeEpisodeCount: Int? = nil
    @State private var animeSeasonEpisodeCache: [Int: [TMDBEpisode]]? = nil  // Maps seasonNumber to episodes

    init(searchResult: TMDBSearchResult, resumeHint: EpisodeResumeHint? = nil, autoPlay: Bool = false) {
        self.searchResult = searchResult
        self.resumeHint = resumeHint
        self.autoPlay = autoPlay
        self._shouldAutoPlay = State(initialValue: autoPlay)
    }

    private var headerHeight: CGFloat {
#if os(tvOS)
        UIScreen.main.bounds.height * 0.8
#else
        550
#endif
    }


    private var minHeaderHeight: CGFloat {
#if os(tvOS)
        UIScreen.main.bounds.height * 0.8
#else
        400
#endif
    }

    private var isCompactLayout: Bool {
        return verticalSizeClass == .compact
    }
    
    private var playButtonText: String {
        if searchResult.isMovie {
            return "Play"
        } else if let selectedEpisode = selectedEpisodeForSearch {
            return "Play S\(selectedEpisode.seasonNumber)E\(selectedEpisode.episodeNumber)"
        } else if let nextEpisode = getNextEpisodeToWatch() {
            return "Play S\(nextEpisode.season)E\(nextEpisode.episode)"
        } else if let hint = resumeHint {
            return "Play S\(hint.season)E\(hint.episode)"
        } else {
            return "Play"
        }
    }

    private var hasResumeHint: Bool {
        if let hint = resumeHint { return hint.showId == searchResult.id }
        return false
    }

    private func getNextEpisodeToWatch() -> (season: Int, episode: Int)? {
        guard let tvShow = tvShowDetail else { return nil }
        let latest = ProgressManager.shared.latestEpisodeProgress(for: tvShow.id)
        guard let latest = latest else { return nil }
        
        // Check if the latest episode is fully watched
        let isWatched = ProgressManager.shared.isEpisodeWatched(
            showId: tvShow.id,
            seasonNumber: latest.seasonNumber,
            episodeNumber: latest.episodeNumber
        )
        
        if !isWatched {
            // Still watching this episode, return it
            return (season: latest.seasonNumber, episode: latest.episodeNumber)
        }
        
        // Episode is fully watched, find the next one
        // Try next episode in same season
        if let season = tvShow.seasons.first(where: { $0.seasonNumber == latest.seasonNumber }),
           season.episodeCount > latest.episodeNumber {
            return (season: latest.seasonNumber, episode: latest.episodeNumber + 1)
        }
        
        // Try first episode of next season
        if let nextSeason = tvShow.seasons.first(where: { $0.seasonNumber > latest.seasonNumber && $0.seasonNumber > 0 }) {
            return (season: nextSeason.seasonNumber, episode: 1)
        }
        
        return nil
    }
    
    var body: some View {
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
#if !os(tvOS)
            navigationOverlay
#endif
        }
        .navigationBarHidden(true)
#if !os(tvOS)
        .gesture(
            DragGesture()
                .onEnded { value in
                    if value.translation.width > 100 && abs(value.translation.height) < 50 {
                        presentationMode.wrappedValue.dismiss()
                    }
                }
        )
#else
        .onExitCommand {
            presentationMode.wrappedValue.dismiss()
        }
#endif
        .onAppear {
            loadMediaDetails()
            updateBookmarkStatus()
        }
        .onChangeComp(of: libraryManager.collections) { _, _ in
            updateBookmarkStatus()
        }
        .sheet(isPresented: $showingSearchResults) {
            ModulesSearchResultsSheet(
                mediaTitle: searchResult.displayTitle,
                originalTitle: romajiTitle,
                isMovie: searchResult.isMovie,
                selectedEpisode: selectedEpisodeForSearch,
                tmdbId: searchResult.id
            )
        }
        .sheet(isPresented: $showingAddToCollection) {
            AddToCollectionView(searchResult: searchResult)
        }
    }
    
    @ViewBuilder
    private var loadingView: some View {
        VStack {
            ProgressView()
                .scaleEffect(1.5)
            Text("Loading...")
                .font(.caption)
                .foregroundColor(.secondary)
                .padding(.top)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
    
    @ViewBuilder
    private func errorView(_ message: String) -> some View {
        VStack {
            Image(systemName: "exclamationmark.triangle")
                .font(.system(size: 60))
                .foregroundColor(.orange)
            
            Text("Error")
                .font(.title2)
                .padding(.top)
            
            Text(message)
                .font(.body)
                .foregroundColor(.secondary)
                .multilineTextAlignment(.center)
                .padding(.horizontal)
            
            Button("Try Again") {
                loadMediaDetails()
            }
            .padding(.top)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
    
    @ViewBuilder
    private var navigationOverlay: some View {
        VStack {
            HStack {
                Button(action: {
                    presentationMode.wrappedValue.dismiss()
                }) {
                    Image(systemName: "chevron.left")
                        .font(.system(size: 16, weight: .medium))
                        .foregroundColor(.white)
                        .frame(width: 32, height: 32)
                        .applyLiquidGlassBackground(cornerRadius: 16)
                }
                
                Spacer()
            }
            .padding(.horizontal)
            
            Spacer()
        }
    }
    
    @ViewBuilder
    private var mainScrollView: some View {
        ScrollView(showsIndicators: false) {
            LazyVStack(spacing: 0) {
                heroImageSection
                contentContainer
            }
        }
        .ignoresSafeArea(edges: [.top, .leading, .trailing])
    }
    
    @ViewBuilder
    private var heroImageSection: some View {
        ZStack(alignment: .bottom) {
            StretchyHeaderView(
                backdropURL: {
                    if searchResult.isMovie {
                        return movieDetail?.fullBackdropURL ?? movieDetail?.fullPosterURL
                    } else {
                        return tvShowDetail?.fullBackdropURL ?? tvShowDetail?.fullPosterURL
                    }
                }(),
                isMovie: searchResult.isMovie,
                headerHeight: headerHeight,
                minHeaderHeight: minHeaderHeight,
                onAmbientColorExtracted: { color in
                    ambientColor = color
                }
            )
            
            gradientOverlay
            headerSection
        }
    }
    
    @ViewBuilder
    private var contentContainer: some View {
        VStack(spacing: 0) {
            VStack(alignment: .leading, spacing: 16) {
                synopsisSection
                playAndBookmarkSection
                
                if searchResult.isMovie {
                    MovieDetailsSection(movie: movieDetail)
                } else {
                    episodesSection
                }
                
                Spacer(minLength: 50)
            }
            .background(Color.clear)
        }
    }
    
    @ViewBuilder
    private var gradientOverlay: some View {
        LinearGradient(
            gradient: Gradient(stops: [
                .init(color: ambientColor.opacity(0.0), location: 0.0),
                .init(color: ambientColor.opacity(0.4), location: 0.2),
                .init(color: ambientColor.opacity(0.6), location: 0.5),
                .init(color: ambientColor.opacity(1), location: 1.0)
            ]),
            startPoint: .top,
            endPoint: .bottom
        )
        .frame(height: 120)
        .clipShape(RoundedRectangle(cornerRadius: 0))
    }
    
    @ViewBuilder
    private var headerSection: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(searchResult.displayTitle)
                .font(.largeTitle)
                .fontWeight(.bold)
                .foregroundColor(.white)
                .lineLimit(3)
                .multilineTextAlignment(.center)
                .frame(maxWidth: .infinity, alignment: .center)
        }
        .frame(maxWidth: .infinity, alignment: .center)
        .padding(.bottom, 40)
        .padding(.horizontal)
    }
    
    @ViewBuilder
    private var synopsisSection: some View {
        VStack(alignment: .leading, spacing: 0) {
            if !synopsis.isEmpty {
                Text(showFullSynopsis ? synopsis : String(synopsis.prefix(180)) + (synopsis.count > 180 ? "..." : ""))
                    .font(.body)
                    .foregroundColor(.white)
                    .lineLimit(showFullSynopsis ? nil : 3)
                    .fixedSize(horizontal: false, vertical: true)
                    .padding(.horizontal)
                    .onTapGesture {
                        withAnimation(.easeInOut(duration: 0.3)) {
                            showFullSynopsis.toggle()
                        }
                    }
            } else if let overview = searchResult.isMovie ? movieDetail?.overview : tvShowDetail?.overview,
                      !overview.isEmpty {
                Text(showFullSynopsis ? overview : String(overview.prefix(200)) + (overview.count > 200 ? "..." : ""))
                    .font(.body)
                    .foregroundColor(.white)
                    .lineLimit(showFullSynopsis ? nil : 3)
                    .fixedSize(horizontal: false, vertical: true)
                    .padding(.horizontal)
                    .onTapGesture {
                        withAnimation(.easeInOut(duration: 0.3)) {
                            showFullSynopsis.toggle()
                        }
                    }
            }
        }
    }
    
    @ViewBuilder
    private var playAndBookmarkSection: some View {
        HStack(spacing: 8) {
            Button(action: {
                searchInServices()
            }) {
                HStack {
                    Image(systemName: serviceManager.activeServices.isEmpty ? "exclamationmark.triangle" : "play.fill")
                    
                    Text(serviceManager.activeServices.isEmpty ? "No Services" : playButtonText)
                        .fontWeight(.semibold)
                }
                .frame(maxWidth: .infinity)
                .padding(.vertical, 12)
                .padding(.horizontal, 25)
                .applyLiquidGlassBackground(
                    cornerRadius: 12,
                    fallbackFill: serviceManager.activeServices.isEmpty ? Color.gray.opacity(0.3) : Color.black.opacity(0.2),
                    fallbackMaterial: serviceManager.activeServices.isEmpty ? .thinMaterial : .ultraThinMaterial,
                    glassTint: serviceManager.activeServices.isEmpty ? Color.gray.opacity(0.3) : nil
                )
                .foregroundColor(serviceManager.activeServices.isEmpty ? .secondary : .white)
                .cornerRadius(8)
            }
            .disabled(serviceManager.activeServices.isEmpty)
            
            Button(action: {
                toggleBookmark()
            }) {
                Image(systemName: isBookmarked ? "bookmark.fill" : "bookmark")
                    .font(.title2)
                    .frame(width: 42, height: 42)
                    .applyLiquidGlassBackground(cornerRadius: 12)
                    .foregroundColor(isBookmarked ? .yellow : .white)
                    .cornerRadius(8)
            }
            
            Button(action: {
                showingAddToCollection = true
            }) {
                Image(systemName: "plus")
                    .font(.title2)
                    .frame(width: 42, height: 42)
                    .applyLiquidGlassBackground(cornerRadius: 12)
                    .foregroundColor(.white)
                    .cornerRadius(8)
            }
        }
        .padding(.horizontal)
    }
    
    @ViewBuilder
    private var episodesSection: some View {
        if !searchResult.isMovie {
            TVShowSeasonsSection(
                tvShow: tvShowDetail,
                isAnime: isAnimeShow,
                animeEpisodeCount: animeEpisodeCount,
                selectedSeason: $selectedSeason,
                seasonDetail: $seasonDetail,
                selectedEpisodeForSearch: $selectedEpisodeForSearch,
                animeSeasonCache: animeSeasonEpisodeCache,
                pendingEpisodeSelection: $pendingEpisodeSelection,
                tmdbService: tmdbService
            )
        }
    }

    private func detectAnime(from detail: TMDBTVShowWithSeasons) -> Bool {
        let genreAnime = detail.genres.contains { $0.id == 16 }
        let originJP = detail.originCountry?.contains("JP") ?? false
        let originCN = detail.originCountry?.contains("CN") ?? false
        // Require animation genre AND (Japanese OR Chinese origin) to avoid misclassifying western animation
        return genreAnime && (originJP || originCN)
    }
    
    private func toggleBookmark() {
        withAnimation(.easeInOut(duration: 0.2)) {
            libraryManager.toggleBookmark(for: searchResult)
            updateBookmarkStatus()
        }
    }
    
    private func updateBookmarkStatus() {
        isBookmarked = libraryManager.isBookmarked(searchResult)
    }
    
    private func searchInServices() {
        // This function will only be called when services are available
        // since the button is disabled when no services are active
        
        if !searchResult.isMovie {
            if selectedEpisodeForSearch != nil {
                // already set
            } else if let pending = pendingEpisodeSelection,
                      let seasonDetail = seasonDetail,
                      let match = seasonDetail.episodes.first(where: { $0.episodeNumber == pending.1 }) {
                selectedEpisodeForSearch = match
            } else if let seasonDetail = seasonDetail, !seasonDetail.episodes.isEmpty {
                selectedEpisodeForSearch = seasonDetail.episodes.first
            } else {
                selectedEpisodeForSearch = nil
            }
        } else {
            selectedEpisodeForSearch = nil
        }
        
        showingSearchResults = true
        shouldAutoPlay = false
    }
    
    private func loadMediaDetails() {
        isLoading = true
        errorMessage = nil
        
        Task {
            do {
                if searchResult.isMovie {
                    let detail = try await tmdbService.getMovieDetails(id: searchResult.id)
                    let romaji = await tmdbService.getRomajiTitle(for: "movie", id: searchResult.id)
                    await MainActor.run {
                        self.movieDetail = detail
                        self.synopsis = detail.overview ?? ""
                        self.romajiTitle = romaji
                        self.isLoading = false
                    }
                } else {
                    let detail = try await tmdbService.getTVShowWithSeasons(id: searchResult.id)
                    let romaji = await tmdbService.getRomajiTitle(for: "tv", id: searchResult.id)
                    let animeFlag = detectAnime(from: detail)
                    self.isAnimeShow = animeFlag

                    // Prefer the last in-progress episode if we have one for this show
                    let resume = ProgressManager.shared.latestEpisodeProgress(for: detail.id)

                    if animeFlag {
                        // Use Jikan (MyAnimeList) for anime data
                        let jikanDetails = try? await JikanService.shared.fetchAnimeDetailsWithEpisodes(malId: searchResult.id)
                        
                        // Cache AniList ID for tracking (convert MAL ID → AniList ID) - must be done outside MainActor
                        var anilistId: Int? = nil
                        if let malId = jikanDetails?.malId {
                            anilistId = try? await AniListService.shared.getAniListId(fromMalId: malId)
                        }
                        
                        // Also fetch TMDB episodes for images (if available)
                        var tmdbEpisodeImages: [Int: String] = [:] // Maps episode number to stillPath
                        do {
                            let tvShowDetail = try await tmdbService.getTVShowWithSeasons(id: searchResult.id)
                            for season in tvShowDetail.seasons where season.seasonNumber > 0 {
                                if let seasonDetail = try? await tmdbService.getSeasonDetails(tvShowId: searchResult.id, seasonNumber: season.seasonNumber) {
                                    for episode in seasonDetail.episodes {
                                        if let stillPath = episode.stillPath {
                                            tmdbEpisodeImages[episode.episodeNumber] = stillPath
                                        }
                                    }
                                }
                            }
                            Logger.shared.log("Fetched TMDB images for \(tmdbEpisodeImages.count) episodes", type: "Anime")
                        } catch {
                            Logger.shared.log("TMDB episodes not available for this anime, using Jikan data only", type: "Anime")
                        }

                        await MainActor.run {
                            Logger.shared.log("Anime detected for: \(detail.name)", type: "Anime")
                            Logger.shared.log("Jikan returned \(jikanDetails?.totalEpisodes ?? 0) episodes", type: "Anime")
                            
                            // Jikan anime are all single-season shows with all episodes
                            let totalEps = jikanDetails?.totalEpisodes ?? 0
                            let aniSeasons = [TMDBSeason(
                                id: detail.id * 1000 + 1,
                                name: "Season 1",
                                overview: "",
                                posterPath: jikanDetails?.posterUrl ?? detail.posterPath,
                                seasonNumber: 1,
                                episodeCount: totalEps,
                                airDate: nil
                            )]
                            
                            Logger.shared.log("Built anime as 1 season with \(totalEps) episodes", type: "Anime")
                            
                            // Cache the AniList ID if we got one
                            if let anilistId = anilistId, let malId = jikanDetails?.malId {
                                TrackerManager.shared.cacheAniListId(tmdbId: detail.id, anilistId: anilistId)
                                Logger.shared.log("Cached AniList ID \(anilistId) for TMDB ID \(detail.id) (MAL ID: \(malId))", type: "Anime")
                            }
                            
                            // Create a new tvShowDetail with anime season
                            let detailWithAniSeasons = TMDBTVShowWithSeasons(
                                id: detail.id,
                                name: detail.name,
                                overview: jikanDetails?.synopsis ?? detail.overview,
                                posterPath: jikanDetails?.posterUrl ?? detail.posterPath,
                                backdropPath: detail.backdropPath,
                                firstAirDate: detail.firstAirDate,
                                lastAirDate: detail.lastAirDate,
                                voteAverage: detail.voteAverage,
                                popularity: detail.popularity,
                                genres: detail.genres,
                                tagline: detail.tagline,
                                status: jikanDetails?.status ?? detail.status,
                                originalLanguage: detail.originalLanguage,
                                originalName: detail.originalName,
                                adult: detail.adult,
                                voteCount: detail.voteCount,
                                numberOfSeasons: 1,
                                numberOfEpisodes: totalEps,
                                episodeRunTime: detail.episodeRunTime,
                                inProduction: detail.inProduction,
                                languages: detail.languages,
                                originCountry: detail.originCountry,
                                type: detail.type,
                                seasons: aniSeasons,
                                contentRatings: detail.contentRatings
                            )
                            
                            self.tvShowDetail = detailWithAniSeasons
                            self.synopsis = jikanDetails?.synopsis ?? detail.overview ?? ""
                            self.romajiTitle = jikanDetails?.title ?? romaji
                            
                            // Set the season and episodes
                            self.selectedSeason = aniSeasons.first
                            
                            // Build episodes from Jikan data + TMDB images
                            let seasonEpisodes: [TMDBEpisode] = jikanDetails?.episodes.enumerated().map { index, jikanEp -> TMDBEpisode in
                                let episodeNum = index + 1
                                return TMDBEpisode(
                                    id: detail.id * 1000 + 100 + episodeNum,
                                    name: jikanEp.title ?? "Episode \(episodeNum)",
                                    overview: nil,
                                    stillPath: tmdbEpisodeImages[episodeNum],
                                    episodeNumber: episodeNum,
                                    seasonNumber: 1,
                                    airDate: jikanEp.aired,
                                    runtime: detail.episodeRunTime?.first,
                                    voteAverage: jikanEp.score ?? 0,
                                    voteCount: 0
                                )
                            } ?? []
                            
                            // Cache the episodes for this season
                            var seasonCache: [Int: [TMDBEpisode]] = [:]
                            seasonCache[1] = seasonEpisodes
                            self.animeSeasonEpisodeCache = seasonCache
                            
                            // Set season detail
                            self.seasonDetail = TMDBSeasonDetail(
                                id: detail.id,
                                name: "Season 1",
                                overview: "",
                                posterPath: jikanDetails?.posterUrl ?? detail.posterPath,
                                seasonNumber: 1,
                                airDate: nil,
                                episodes: seasonEpisodes
                            )
                            self.selectedEpisodeForSearch = self.seasonDetail?.episodes.first
                            self.isLoading = false
                        }
                    } else {
                        await MainActor.run {
                            self.tvShowDetail = detail
                            self.synopsis = detail.overview ?? ""
                            self.romajiTitle = romaji
                            
                            Logger.shared.log("Non-anime show loaded: \(detail.name), seasons: \(detail.seasons.count)", type: "MediaDetail")
                            for season in detail.seasons.filter({ $0.seasonNumber > 0 }) {
                                Logger.shared.log("  Season \(season.seasonNumber): \(season.episodeCount) episodes", type: "MediaDetail")
                            }

                            if let resume = resume {
                                if let matchedSeason = detail.seasons.first(where: { $0.seasonNumber == resume.seasonNumber }) {
                                    self.selectedSeason = matchedSeason
                                } else if let firstSeason = detail.seasons.first(where: { $0.seasonNumber > 0 }) {
                                    self.selectedSeason = firstSeason
                                }
                                self.pendingEpisodeSelection = (resume.seasonNumber, resume.episodeNumber)
                            } else if let hint = resumeHint, hint.showId == detail.id,
                                      let matchedSeason = detail.seasons.first(where: { $0.seasonNumber == hint.season }) {
                                self.selectedSeason = matchedSeason
                                self.pendingEpisodeSelection = (hint.season, hint.episode)
                            } else if let firstSeason = detail.seasons.first(where: { $0.seasonNumber > 0 }) {
                                self.selectedSeason = firstSeason
                            }

                            self.selectedEpisodeForSearch = nil
                            self.isLoading = false
                        }
                    }

                    // If autoPlay was requested, attempt to start search after season details are loaded
                    if shouldAutoPlay {
                        Task { @MainActor in
                            if selectedEpisodeForSearch == nil,
                               let pending = pendingEpisodeSelection,
                               let seasonDetail = self.seasonDetail,
                               let match = seasonDetail.episodes.first(where: { $0.episodeNumber == pending.1 }) {
                                self.selectedEpisodeForSearch = match
                            }
                            if !serviceManager.activeServices.isEmpty {
                                self.searchInServices()
                            } else {
                                // No services; just show details
                                self.shouldAutoPlay = false
                            }
                        }
                    }
                }
            } catch {
                await MainActor.run {
                    self.errorMessage = error.localizedDescription
                    self.isLoading = false
                }
            }
        }
    }
}
