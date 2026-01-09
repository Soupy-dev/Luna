//
//  ShowsDetails.swift
//  Sora
//
//  Created by Francesco on 07/08/25.
//

import SwiftUI
import Kingfisher

struct TVShowSeasonsSection: View {
    let tvShow: TMDBTVShowWithSeasons?
    let isAnime: Bool
    @Binding var selectedSeason: TMDBSeason?
    @Binding var seasonDetail: TMDBSeasonDetail?
    @Binding var selectedEpisodeForSearch: TMDBEpisode?
    var animeEpisodes: [AniListEpisode]? = nil
    var animeSeasonTitles: [Int: String]? = nil
    let tmdbService: TMDBService
    
    @State private var isLoadingSeason = false
    @State private var showingSearchResults = false
    @State private var showingDownloadSheet = false
    @State private var showingNoServicesAlert = false
    @State private var downloadEpisodeForSheet: TMDBEpisode?
    @State private var romajiTitle: String?
    @State private var currentSeasonTitle: String?
    @State private var batchDownloadEpisodes: [TMDBEpisode] = []
    @State private var currentBatchIndex: Int = 0
    @State private var isBatchDownloading: Bool = false
    
    @StateObject private var serviceManager = ServiceManager.shared
    @AppStorage("horizontalEpisodeList") private var horizontalEpisodeList: Bool = false
    
    private var isGroupedBySeasons: Bool {
        return tvShow?.seasons.filter { $0.seasonNumber > 0 }.count ?? 0 > 1
    }
    
    private var useSeasonMenu: Bool {
        return UserDefaults.standard.bool(forKey: "seasonMenu")
    }
    
    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            if let tvShow = tvShow {
                Text("Details")
                    .font(.title2)
                    .fontWeight(.bold)
                    .padding(.horizontal)
                    .padding(.top)
                    .foregroundColor(.white)
                
                VStack(spacing: 12) {
                    if let numberOfSeasons = tvShow.numberOfSeasons, numberOfSeasons > 0 {
                        DetailRow(title: "Seasons", value: "\(numberOfSeasons)")
                    }
                    
                    if let numberOfEpisodes = tvShow.numberOfEpisodes, numberOfEpisodes > 0 {
                        DetailRow(title: "Episodes", value: "\(numberOfEpisodes)")
                    }
                    
                    if !tvShow.genres.isEmpty {
                        DetailRow(title: "Genres", value: tvShow.genres.map { $0.name }.joined(separator: ", "))
                    }
                    
                    if tvShow.voteAverage > 0 {
                        DetailRow(title: "Rating", value: String(format: "%.1f/10", tvShow.voteAverage))
                    }
                    
                    if let ageRating = getAgeRating(from: tvShow.contentRatings) {
                        DetailRow(title: "Age Rating", value: ageRating)
                    }
                    
                    if let firstAirDate = tvShow.firstAirDate, !firstAirDate.isEmpty {
                        DetailRow(title: "First aired", value: "\(firstAirDate)")
                    }
                    
                    if let lastAirDate = tvShow.lastAirDate, !lastAirDate.isEmpty {
                        DetailRow(title: "Last aired", value: "\(lastAirDate)")
                    }
                    
                    if let status = tvShow.status {
                        DetailRow(title: "Status", value: status)
                    }
                }
                .padding(.horizontal)
                .padding(.vertical, 16)
                .applyLiquidGlassBackground(cornerRadius: 12)
                .padding(.horizontal)
                
                if !tvShow.seasons.isEmpty {
                    if isGroupedBySeasons && !useSeasonMenu {
                        HStack {
                            Text("Seasons")
                                .font(.title2)
                                .fontWeight(.bold)
                            Spacer()
                        }
                        .foregroundColor(.white)
                        .padding(.horizontal)
                        .padding(.top)
                        
                        seasonSelectorStyled
                        
                        HStack {
                            Text("Episodes")
                                .font(.title2)
                                .fontWeight(.bold)
                            Spacer()
                            if seasonDetail != nil {
                                Button(action: downloadAllEpisodes) {
                                    Image(systemName: "arrow.down.circle.fill")
                                        .font(.title3)
                                        .foregroundColor(.accentColor)
                                }
                            }
                        }
                        .foregroundColor(.white)
                        .padding(.horizontal)
                        .padding(.top)
                    } else {
                        episodesSectionHeader
                    }
                    
                    episodeListSection
                }
            }
        }
        .onAppear {
            if let tvShow = tvShow, let selectedSeason = selectedSeason {
                loadSeasonDetails(tvShowId: tvShow.id, season: selectedSeason)
                Task {
                    let romaji = await tmdbService.getRomajiTitle(for: "tv", id: tvShow.id)
                    await MainActor.run {
                        self.romajiTitle = romaji
                    }
                }
            }
        }
        .sheet(isPresented: $showingSearchResults) {
            ModulesSearchResultsSheet(
                mediaTitle: getSearchTitle(),
                originalTitle: romajiTitle,
                isMovie: false,
                selectedEpisode: selectedEpisodeForSearch,
                tmdbId: tvShow?.id ?? 0,
                animeSeasonTitle: isAnime ? "anime" : nil
            )
        }
        .sheet(isPresented: $showingDownloadSheet) {
            ModulesSearchResultsSheet(
                mediaTitle: getSearchTitle(),
                originalTitle: romajiTitle,
                isMovie: false,
                selectedEpisode: downloadEpisodeForSheet,
                tmdbId: tvShow?.id ?? 0,
                animeSeasonTitle: isAnime ? "anime" : nil,
                isDownload: true,
                onDownloadSelected: { displayTitle, url, headers in
                    let metadata = DownloadMetadata(
                        title: tvShow?.name ?? "Unknown Show",
                        overview: tvShow?.overview,
                        posterURL: tvShow?.posterURL,
                        showTitle: tvShow?.name,
                        season: downloadEpisodeForSheet?.seasonNumber,
                        episode: downloadEpisodeForSheet?.episodeNumber,
                        showPosterURL: tvShow?.posterPath.flatMap { URL(string: $0) }
                    )
                    DownloadManager.shared.addToQueue(
                        url: url,
                        headers: headers ?? [:],
                        title: displayTitle,
                        posterURL: tvShow?.posterURL,
                        type: .episode,
                        metadata: metadata,
                        subtitleURL: nil,
                        showPosterURL: tvShow?.posterPath.flatMap { URL(string: $0) }
                    )
                    
                    if isBatchDownloading {
                        continueNextBatchDownload()
                    } else {
                        showingDownloadSheet = false
                    }
                }
            )
        }
        .alert("No Active Services", isPresented: $showingNoServicesAlert) {
            Button("OK") { }
        } message: {
            Text("You don't have any active services. Please go to the Services tab to download and activate services.")
        }
    }
    
    private func getSearchTitle() -> String {
        // For anime, use the season-specific AniList title; otherwise use show name
        if isAnime, let episode = selectedEpisodeForSearch, let seasonTitle = animeSeasonTitles?[episode.seasonNumber] {
            return seasonTitle
        }
        return tvShow?.name ?? "Unknown Show"
    }
    
    @ViewBuilder
    private var episodesSectionHeader: some View {
        HStack {
            Text("Episodes")
                .font(.title2)
                .fontWeight(.bold)
                .foregroundColor(.white)
            
            Spacer()
            
            if let tvShow = tvShow, isGroupedBySeasons && useSeasonMenu {
                seasonMenu(for: tvShow)
            }
        }
        .padding(.horizontal)
        .padding(.top)
    }
    
    @ViewBuilder
    private func seasonMenu(for tvShow: TMDBTVShowWithSeasons) -> some View {
        let seasons = tvShow.seasons.filter { $0.seasonNumber > 0 }
        
        if seasons.count > 1 {
            Menu {
                ForEach(seasons) { season in
                    Button(action: {
                        selectedSeason = season
                        loadSeasonDetails(tvShowId: tvShow.id, season: season)
                    }) {
                        HStack {
                            Text(season.name)
                            if selectedSeason?.id == season.id {
                                Spacer()
                                Image(systemName: "checkmark")
                            }
                        }
                    }
                }
            } label: {
                HStack(spacing: 4) {
                    Text(selectedSeason?.name ?? "Season 1")
                    
                    Image(systemName: "chevron.down")
                }
                .foregroundColor(.white)
            }
        }
    }
    
    @ViewBuilder
    private var seasonSelectorStyled: some View {
        if let tvShow = tvShow {
            let seasons = tvShow.seasons.filter { $0.seasonNumber > 0 }
            if seasons.count > 1 {
                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(spacing: 12) {
                        ForEach(seasons) { season in
                            Button(action: {
                                selectedSeason = season
                                loadSeasonDetails(tvShowId: tvShow.id, season: season)
                            }) {
                                VStack(spacing: 8) {
                                    KFImage(URL(string: season.fullPosterURL ?? ""))
                                        .placeholder {
                                            Rectangle()
                                                .fill(Color.gray.opacity(0.3))
                                                .frame(width: 80, height: 120)
                                                .overlay(
                                                    VStack {
                                                        Image(systemName: "tv")
                                                            .font(.title2)
                                                            .foregroundColor(.white.opacity(0.7))
                                                        Text("S\(season.seasonNumber)")
                                                            .font(.caption)
                                                            .fontWeight(.bold)
                                                            .foregroundColor(.white.opacity(0.7))
                                                    }
                                                )
                                        }
                                        .resizable()
                                        .aspectRatio(2/3, contentMode: .fill)
                                        .frame(width: 80, height: 120)
                                        .clipShape(RoundedRectangle(cornerRadius: 8))
                                        .overlay(
                                            RoundedRectangle(cornerRadius: 8)
                                                .stroke(selectedSeason?.id == season.id ? Color.accentColor : Color.clear, lineWidth: 2)
                                        )
                                    
                                    Text(season.name)
                                        .font(.caption)
                                        .fontWeight(.medium)
                                        .lineLimit(1)
                                        .multilineTextAlignment(.center)
                                        .frame(width: 80)
                                        .foregroundColor(selectedSeason?.id == season.id ? .accentColor : .white)
                                }
                            }
                            .buttonStyle(PlainButtonStyle())
                        }
                    }
                    .padding(.horizontal)
                }
            }
        }
    }
    
    @ViewBuilder
    private var episodeListSection: some View {
        Group {
            if let seasonDetail = seasonDetail {
                if horizontalEpisodeList {
                    ScrollView(.horizontal, showsIndicators: false) {
                        LazyHStack(alignment: .top, spacing: 15) {
                            ForEach(Array(seasonDetail.episodes.enumerated()), id: \.element.id) { index, episode in
                                createEpisodeCell(episode: episode, index: index)
                            }
                        }
                    }
                    .padding(.horizontal)
                } else {
                    LazyVStack(spacing: 15) {
                        ForEach(Array(seasonDetail.episodes.enumerated()), id: \.element.id) { index, episode in
                            createEpisodeCell(episode: episode, index: index)
                        }
                    }
                    .padding(.horizontal)
                }
            } else if isLoadingSeason {
                VStack(spacing: 12) {
                    ProgressView()
                        .scaleEffect(1.2)
                    Text("Loading episodes...")
                        .font(.caption)
                        .foregroundColor(.secondary)
                }
                .frame(maxWidth: .infinity)
                .padding(.vertical, 40)
            }
        }
    }
    
    @ViewBuilder
    private func createEpisodeCell(episode: TMDBEpisode, index: Int) -> some View {
        if let tvShow = tvShow {
            let progress = ProgressManager.shared.getEpisodeProgress(
                showId: tvShow.id,
                seasonNumber: episode.seasonNumber,
                episodeNumber: episode.episodeNumber
            )
            let isSelected = selectedEpisodeForSearch?.id == episode.id
            
            EpisodeCell(
                episode: episode,
                showId: tvShow.id,
                progress: progress,
                isSelected: isSelected,
                onTap: { episodeTapAction(episode: episode) },
                onMarkWatched: { markAsWatched(episode: episode) },
                onResetProgress: { resetProgress(episode: episode) },
                onDownload: { downloadEpisode(episode: episode, showId: tvShow.id) }
            )
        } else {
            EmptyView()
        }
    }
    
    private func episodeTapAction(episode: TMDBEpisode) {
        selectedEpisodeForSearch = episode
        
        // Ensure current season title is set before opening search
        if let seasonTitle = animeSeasonTitles?[episode.seasonNumber] {
            currentSeasonTitle = seasonTitle
        } else {
            currentSeasonTitle = nil
        }
        
        searchInServicesForEpisode(episode: episode)
    }
    
    private func searchInServicesForEpisode(episode: TMDBEpisode) {
        guard (tvShow?.name) != nil else { return }
        
        if serviceManager.activeServices.isEmpty {
            showingNoServicesAlert = true
            return
        }
        
        showingSearchResults = true
    }
    
    private func markAsWatched(episode: TMDBEpisode) {
        guard let tvShow = tvShow else { return }
        ProgressManager.shared.markEpisodeAsWatched(
            showId: tvShow.id,
            seasonNumber: episode.seasonNumber,
            episodeNumber: episode.episodeNumber
        )
    }
    
    private func resetProgress(episode: TMDBEpisode) {
        guard let tvShow = tvShow else { return }
        ProgressManager.shared.resetEpisodeProgress(
            showId: tvShow.id,
            seasonNumber: episode.seasonNumber,
            episodeNumber: episode.episodeNumber
        )
    }
    
    private func loadSeasonDetails(tvShowId: Int, season: TMDBSeason) {
        isLoadingSeason = true
        seasonDetail = nil
        selectedEpisodeForSearch = nil
        
        Task {
            do {
                // For anime, build season detail from cached AniList episodes
                if isAnime, let animeEpisodes = animeEpisodes {
                    let seasonEpisodes = animeEpisodes.filter { $0.seasonNumber == season.seasonNumber }
                    
                    let tmdbEpisodes: [TMDBEpisode] = seasonEpisodes.map { aniEp in
                        TMDBEpisode(
                            id: tvShowId * 1000 + season.seasonNumber * 100 + aniEp.number,
                            name: aniEp.title,
                            overview: aniEp.description,
                            stillPath: aniEp.stillPath,
                            episodeNumber: aniEp.number,
                            seasonNumber: aniEp.seasonNumber,
                            airDate: aniEp.airDate,
                            runtime: nil,
                            voteAverage: 0,
                            voteCount: 0
                        )
                    }
                    
                    let detail = TMDBSeasonDetail(
                        id: season.id,
                        name: season.name,
                        overview: season.overview ?? "",
                        posterPath: season.posterPath,
                        seasonNumber: season.seasonNumber,
                        airDate: season.airDate,
                        episodes: tmdbEpisodes
                    )
                    
                    await MainActor.run {
                        // Update current season title for anime
                        if let seasonTitle = animeSeasonTitles?[season.seasonNumber] {
                            self.currentSeasonTitle = seasonTitle
                        }
                        self.seasonDetail = detail
                        self.isLoadingSeason = false
                        if let firstEpisode = detail.episodes.first {
                            self.selectedEpisodeForSearch = firstEpisode
                        }
                    }
                } else {
                    // For regular TV shows, fetch from TMDB
                    let detail = try await tmdbService.getSeasonDetails(tvShowId: tvShowId, seasonNumber: season.seasonNumber)
                    await MainActor.run {
                        self.currentSeasonTitle = nil
                        self.seasonDetail = detail
                        self.isLoadingSeason = false
                        if let firstEpisode = detail.episodes.first {
                            self.selectedEpisodeForSearch = firstEpisode
                        }
                    }
                }
            } catch {
                await MainActor.run {
                    self.isLoadingSeason = false
                }
            }
        }
    }
    
    private func downloadEpisode(episode: TMDBEpisode, showId: Int) {
        guard !serviceManager.activeServices.isEmpty else {
            showingNoServicesAlert = true
            return
        }

        downloadEpisodeForSheet = episode
        selectedEpisodeForSearch = episode
        showingDownloadSheet = true
    }
    
    private func downloadAllEpisodes() {
        guard !serviceManager.activeServices.isEmpty else {
            showingNoServicesAlert = true
            return
        }
        
        guard let episodes = seasonDetail?.episodes, !episodes.isEmpty else {
            return
        }
        
        batchDownloadEpisodes = episodes
        currentBatchIndex = 0
        isBatchDownloading = true
        downloadEpisodeForSheet = episodes[0]
        selectedEpisodeForSearch = episodes[0]
        showingDownloadSheet = true
    }
    
    private func continueNextBatchDownload() {
        let nextIndex = currentBatchIndex + 1
        
        if nextIndex < batchDownloadEpisodes.count {
            currentBatchIndex = nextIndex
            downloadEpisodeForSheet = batchDownloadEpisodes[nextIndex]
            selectedEpisodeForSearch = batchDownloadEpisodes[nextIndex]
            // Sheet stays open; search automatically triggers for new episode
        } else {
            // Batch complete
            isBatchDownloading = false
            showingDownloadSheet = false
            batchDownloadEpisodes = []
            currentBatchIndex = 0
        }
    }
    
    private func getAgeRating(from contentRatings: TMDBContentRatings?) -> String? {
        guard let contentRatings = contentRatings else { return nil }
        
        for rating in contentRatings.results {
            if rating.iso31661 == "US" && !rating.rating.isEmpty {
                return rating.rating
            }
        }
        
        for rating in contentRatings.results {
            if !rating.rating.isEmpty {
                return rating.rating
            }
        }
        
        return nil
    }
}
