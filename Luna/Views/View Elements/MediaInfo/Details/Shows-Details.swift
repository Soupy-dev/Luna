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
    let animeEpisodeCount: Int?
    @Binding var selectedSeason: TMDBSeason?
    @Binding var seasonDetail: TMDBSeasonDetail?
    @Binding var selectedEpisodeForSearch: TMDBEpisode?
    var animeSeasonCache: [Int: [TMDBEpisode]]? = nil  // For anime: pre-built episodes for all seasons
    @Binding var pendingEpisodeSelection: (Int, Int)?
    let tmdbService: TMDBService
    
    @State private var isLoadingSeason = false
    @State private var showingSearchResults = false
    @State private var showingNoServicesAlert = false
    @State private var romajiTitle: String?
    
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
                if isAnime {
                    setAnimeSeasonDetail(for: selectedSeason, tvShow: tvShow)
                } else {
                    loadSeasonDetails(tvShowId: tvShow.id, season: selectedSeason)
                    Task {
                        let romaji = await tmdbService.getRomajiTitle(for: "tv", id: tvShow.id)
                        await MainActor.run {
                            self.romajiTitle = romaji
                        }
                    }
                }
            }
        }
        .sheet(isPresented: $showingSearchResults) {
            ModulesSearchResultsSheet(
                mediaTitle: tvShow?.name ?? "Unknown Show",
                originalTitle: romajiTitle,
                isMovie: false,
                selectedEpisode: selectedEpisodeForSearch,
                tmdbId: tvShow?.id ?? 0
            )
        }
        .alert("No Active Services", isPresented: $showingNoServicesAlert) {
            Button("OK") { }
        } message: {
            Text("You don't have any active services. Please go to the Services tab to download and activate services.")
        }
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
                        if isAnime {
                            setAnimeSeasonDetail(for: season, tvShow: tvShow)
                        } else {
                            loadSeasonDetails(tvShowId: tvShow.id, season: season)
                        }
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
                                if isAnime {
                                    setAnimeSeasonDetail(for: season, tvShow: tvShow)
                                } else {
                                    loadSeasonDetails(tvShowId: tvShow.id, season: season)
                                }
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
                onResetProgress: { resetProgress(episode: episode) }
            )
        } else {
            EmptyView()
        }
    }
    
    private func episodeTapAction(episode: TMDBEpisode) {
        Logger.shared.log("Episode tapped: S\(episode.seasonNumber)E\(episode.episodeNumber) - \(episode.name)", type: "Anime")
        selectedEpisodeForSearch = episode
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
        
        Logger.shared.log("Loading season \(season.seasonNumber) for show \(tvShowId)", type: "Shows")
        
        Task {
            do {
                let detail = try await tmdbService.getSeasonDetails(tvShowId: tvShowId, seasonNumber: season.seasonNumber)
                await MainActor.run {
                    Logger.shared.log("Loaded season \(season.seasonNumber): \(detail.episodes.count) episodes", type: "Shows")
                    self.seasonDetail = detail
                    self.isLoadingSeason = false

                    if let pending = pendingEpisodeSelection,
                       pending.0 == season.seasonNumber,
                       let match = detail.episodes.first(where: { $0.episodeNumber == pending.1 }) {
                        self.selectedEpisodeForSearch = match
                        self.pendingEpisodeSelection = nil
                    } else if let firstEpisode = detail.episodes.first {
                        self.selectedEpisodeForSearch = firstEpisode
                    }
                }
            } catch {
                await MainActor.run {
                    self.isLoadingSeason = false
                }
            }
        }
    }

    private func setAnimeSeasonDetail(for season: TMDBSeason, tvShow: TMDBTVShowWithSeasons) {
        // For anime, ALWAYS use pre-built cache from MediaDetailView
        // This cache is authoritative and already has correct TMDB episode mappings
        let cacheKeys = animeSeasonCache?.keys.map { String($0) }.joined(separator: ", ") ?? "empty"
        Logger.shared.log("setAnimeSeasonDetail: Looking for season \(season.seasonNumber) in cache (available: \(cacheKeys))", type: "Anime")
        
        guard let cachedEpisodes = animeSeasonCache?[season.seasonNumber] else {
            Logger.shared.log("ERROR: No cache for season \(season.seasonNumber)! This indicates a bug in MediaDetailView cache building.", type: "Anime")
            seasonDetail = nil
            return
        }
        
        Logger.shared.log("Cache HIT for season \(season.seasonNumber): \(cachedEpisodes.count) episodes", type: "Anime")
        for (idx, ep) in cachedEpisodes.prefix(3).enumerated() {
            Logger.shared.log("  Episode \(idx+1): S\(ep.seasonNumber)E\(ep.episodeNumber) - \(ep.name)", type: "Anime")
        }
        
        seasonDetail = TMDBSeasonDetail(
            id: tvShow.id,
            name: season.name,
            overview: season.overview ?? "",
            posterPath: season.posterPath,
            seasonNumber: season.seasonNumber,
            airDate: season.airDate,
            episodes: cachedEpisodes
        )
        
        if let pending = pendingEpisodeSelection,
           pending.0 == season.seasonNumber,
           let match = cachedEpisodes.first(where: { $0.episodeNumber == pending.1 }) {
            self.selectedEpisodeForSearch = match
            self.pendingEpisodeSelection = nil
        } else if let firstEpisode = cachedEpisodes.first {
            self.selectedEpisodeForSearch = firstEpisode
        }
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
