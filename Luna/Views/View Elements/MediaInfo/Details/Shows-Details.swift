//
//  ShowsDetails.swift
//  Sora
//
//  Created by Francesco on 07/08/25.
//

import SwiftUI
import Kingfisher

struct TVShowSeasonsSection<InsertedContent: View>: View {
    let tvShow: TMDBTVShowWithSeasons?
    let isAnime: Bool
    @Binding var selectedSeason: TMDBSeason?
    @Binding var seasonDetail: TMDBSeasonDetail?
    @Binding var selectedEpisodeForSearch: TMDBEpisode?
    var animeEpisodes: [AniListEpisode]? = nil
    var animeSeasonTitles: [Int: String]? = nil
    var relatedAnimeEntries: [AniListRelatedAnimeEntry] = []
    var initialRelatedAniListId: Int? = nil
    let tmdbService: TMDBService
    @ViewBuilder let insertedContent: () -> InsertedContent
    
    @State private var isLoadingSeason = false
    @State private var showingSearchResults = false
    @State private var showingDownloadSheet = false
    @State private var downloadEpisode: TMDBEpisode? = nil
    @State private var downloadAllQueue: [TMDBEpisode] = []
    @State private var isDownloadingAll = false
    @State private var downloadWasEnqueued = false
    @State private var downloadWasSkipped = false
    @State private var showingNoServicesAlert = false
    @State private var romajiTitle: String?
    @State private var currentSeasonTitle: String?
    @State private var selectedRelatedAniListId: Int?
    @State private var didApplyInitialRelatedSelection = false
    
    @StateObject private var serviceManager = ServiceManager.shared
    @StateObject private var stremioManager = StremioAddonManager.shared
    @AppStorage("horizontalEpisodeList") private var horizontalEpisodeList: Bool = false
    private var isGroupedBySeasons: Bool {
        return tvShow?.seasons.filter { $0.seasonNumber > 0 }.count ?? 0 > 1
    }
    
    private var useSeasonMenu: Bool {
        return UserDefaults.standard.bool(forKey: "seasonMenu")
    }

    private var hasActiveSources: Bool {
        !serviceManager.activeServices.isEmpty || !stremioManager.activeAddons.isEmpty
    }

    private struct EpisodeRenderItem: Identifiable {
        let id: String
        let index: Int
        let episode: TMDBEpisode
    }

    private func episodeRenderItems(for detail: TMDBSeasonDetail) -> [EpisodeRenderItem] {
        detail.episodes.enumerated().map { index, episode in
            EpisodeRenderItem(
                id: "\(detail.seasonNumber)-\(episode.seasonNumber)-\(episode.episodeNumber)-\(episode.id)-\(index)",
                index: index,
                episode: episode
            )
        }
    }
    
    private func getSearchTitle() -> String {
        if isAnime, let currentSeasonTitle, !currentSeasonTitle.isEmpty {
            return currentSeasonTitle
        }
        if isAnime, let seasonName = selectedSeason?.name, !seasonName.isEmpty {
            return seasonName
        }
        return tvShow?.name ?? "Unknown Show"
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
                .applyLiquidGlassBackground(cornerRadius: 16)
                .padding(.horizontal)
                
                insertedContent()
                
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
                        relatedAnimeSelector
                        HStack {
                            Text("Episodes")
                                .font(.title2)
                                .fontWeight(.bold)
                            
                            Spacer()
                            
                            if seasonDetail != nil && hasActiveSources {
                                Button(action: startDownloadAllSeason) {
                                    Image(systemName: "arrow.down.circle")
                                        .font(.title3)
                                        .foregroundColor(.white)
                                }
                                .disabled(isDownloadingAll)
                            }
                        }
                        .foregroundColor(.white)
                        .padding(.horizontal)
                        .padding(.top)
                    } else {
                        episodesSectionHeader
                        relatedAnimeSelector
                    }
                    
                    episodeListSection
                }
            }
        }
        .onAppear {
            if let tvShow = tvShow, let selectedSeason = selectedSeason {
                if applyInitialRelatedSelectionIfNeeded(tvShowId: tvShow.id) {
                    Logger.shared.log("TVShowSeasonsSection auto-selected related id=\(selectedRelatedAniListId ?? 0) showId=\(tvShow.id)", type: "CrashProbe")
                } else {
                    loadSeasonDetails(tvShowId: tvShow.id, season: selectedSeason)
                }
                Task {
                    let romaji = await tmdbService.getRomajiTitle(for: "tv", id: tvShow.id)
                    await MainActor.run {
                        self.romajiTitle = romaji
                    }
                }
            }
        }
        .onChangeComp(of: initialRelatedAniListId) { _, _ in
            if let tvShow = tvShow {
                _ = applyInitialRelatedSelectionIfNeeded(tvShowId: tvShow.id)
            }
        }
        .sheet(isPresented: $showingSearchResults) {
            ModulesSearchResultsSheet(
                mediaTitle: getSearchTitle(),
                seasonTitleOverride: currentSeasonTitle,
                originalTitle: romajiTitle,
                isMovie: false,
                isAnimeContent: isAnime,
                selectedEpisode: selectedEpisodeForSearch,
                tmdbId: tvShow?.id ?? 0,
                animeSeasonTitle: isAnime ? currentSeasonTitle : nil,
                posterPath: tvShow?.posterPath,
                imdbId: tvShow?.externalIds?.imdbId,
                originalTMDBSeasonNumber: originalTMDBNumbers?.season,
                originalTMDBEpisodeNumber: originalTMDBNumbers?.episode,
                autoModeOnly: UserDefaults.standard.bool(forKey: "servicesAutoModeEnabled")
            )
        }
        .sheet(isPresented: $showingDownloadSheet, onDismiss: {
            if isDownloadingAll {
                if downloadWasEnqueued || downloadWasSkipped {
                    // Download enqueued or skipped — advance to next episode
                    downloadWasEnqueued = false
                    downloadWasSkipped = false
                    if !downloadAllQueue.isEmpty {
                        DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) {
                            showNextDownloadSheet()
                        }
                    } else {
                        isDownloadingAll = false
                    }
                } else {
                    // "Done" was tapped without download/skip — cancel entire queue
                    downloadAllQueue.removeAll()
                    isDownloadingAll = false
                }
            }
        }) {
            ModulesSearchResultsSheet(
                mediaTitle: getSearchTitle(),
                seasonTitleOverride: currentSeasonTitle,
                originalTitle: romajiTitle,
                isMovie: false,
                isAnimeContent: isAnime,
                selectedEpisode: downloadEpisode ?? selectedEpisodeForSearch,
                tmdbId: tvShow?.id ?? 0,
                animeSeasonTitle: isAnime ? currentSeasonTitle : nil,
                posterPath: tvShow?.posterPath,
                imdbId: tvShow?.externalIds?.imdbId,
                originalTMDBSeasonNumber: originalTMDBNumbers?.season,
                originalTMDBEpisodeNumber: originalTMDBNumbers?.episode,
                downloadMode: true,
                autoModeOnly: UserDefaults.standard.bool(forKey: "servicesAutoModeEnabled"),
                onDownloadEnqueued: isDownloadingAll ? {
                    downloadWasEnqueued = true
                } : nil,
                onSkipRequested: isDownloadingAll ? {
                    downloadWasSkipped = true
                } : nil
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
            
            if seasonDetail != nil && hasActiveSources {
                Button(action: startDownloadAllSeason) {
                    Image(systemName: "arrow.down.circle")
                        .font(.title3)
                        .foregroundColor(.white)
                }
                .disabled(isDownloadingAll)
            }
            
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
                        selectSeason(season, tvShowId: tvShow.id)
                    }) {
                        HStack {
                            Text(season.name)
                            if selectedRelatedAniListId == nil && selectedSeason?.id == season.id {
                                Spacer()
                                Image(systemName: "checkmark")
                            }
                        }
                    }
                }
                if !relatedAnimeEntries.isEmpty {
                    Divider()
                    ForEach(relatedAnimeEntries) { entry in
                        Button(action: {
                            selectRelatedEntry(entry, tvShowId: tvShow.id)
                        }) {
                            HStack {
                                Text(entry.title)
                                if selectedRelatedAniListId == entry.id {
                                    Spacer()
                                    Image(systemName: "checkmark")
                                }
                            }
                        }
                    }
                }
            } label: {
                HStack(spacing: 4) {
                    Text(currentSeasonTitle ?? selectedSeason?.name ?? "Season 1")
                    
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
                                selectSeason(season, tvShowId: tvShow.id)
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
                                        .clipShape(RoundedRectangle(cornerRadius: 12))
                                        .overlay(
                                            RoundedRectangle(cornerRadius: 12)
                                                .stroke(selectedRelatedAniListId == nil && selectedSeason?.id == season.id ? Color.accentColor : Color.clear, lineWidth: 2)
                                        )
                                    
                                    Text(season.name)
                                        .font(.caption)
                                        .fontWeight(.medium)
                                        .lineLimit(1)
                                        .multilineTextAlignment(.center)
                                        .frame(width: 80)
                                        .foregroundColor(selectedRelatedAniListId == nil && selectedSeason?.id == season.id ? .accentColor : .white)
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
    private var relatedAnimeSelector: some View {
        if isAnime && !relatedAnimeEntries.isEmpty, let tvShow = tvShow {
            VStack(alignment: .leading, spacing: 10) {
                HStack {
                    Text("Specials & Related")
                        .font(.title3)
                        .fontWeight(.bold)
                    Spacer()
                }
                .foregroundColor(.white)
                .padding(.horizontal)

                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(spacing: 12) {
                        ForEach(relatedAnimeEntries) { entry in
                            Button(action: {
                                selectRelatedEntry(entry, tvShowId: tvShow.id)
                            }) {
                                VStack(spacing: 8) {
                                    KFImage(URL(string: entry.posterUrl ?? ""))
                                        .placeholder {
                                            Rectangle()
                                                .fill(Color.gray.opacity(0.3))
                                                .frame(width: 80, height: 120)
                                                .overlay(
                                                    Image(systemName: relatedIconName(for: entry))
                                                        .font(.title2)
                                                        .foregroundColor(.white.opacity(0.7))
                                                )
                                        }
                                        .resizable()
                                        .aspectRatio(2/3, contentMode: .fill)
                                        .frame(width: 80, height: 120)
                                        .clipShape(RoundedRectangle(cornerRadius: 12))
                                        .overlay(
                                            RoundedRectangle(cornerRadius: 12)
                                                .stroke(selectedRelatedAniListId == entry.id ? Color.accentColor : Color.clear, lineWidth: 2)
                                        )

                                    Text(entry.title)
                                        .font(.caption)
                                        .fontWeight(.medium)
                                        .lineLimit(2)
                                        .multilineTextAlignment(.center)
                                        .frame(width: 86, height: 34)
                                        .foregroundColor(selectedRelatedAniListId == entry.id ? .accentColor : .white)

                                    Text(relatedLabel(for: entry))
                                        .font(.caption2)
                                        .lineLimit(1)
                                        .foregroundColor(.white.opacity(0.65))
                                        .frame(width: 86)
                                }
                            }
                            .buttonStyle(PlainButtonStyle())
                        }
                    }
                    .padding(.horizontal)
                }
            }
            .padding(.top, 4)
        }
    }

    @ViewBuilder
    private var episodeListSection: some View {
        Group {
            if let seasonDetail = seasonDetail {
                let episodeItems = episodeRenderItems(for: seasonDetail)
                if horizontalEpisodeList {
                    ScrollView(.horizontal, showsIndicators: false) {
                        LazyHStack(alignment: .top, spacing: 15) {
                            ForEach(episodeItems) { item in
                                createEpisodeCell(episode: item.episode, index: item.index)
                            }
                        }
                        .onAppear {
                            Logger.shared.log("TVShowSeasonsSection episode list appeared: showId=\(tvShow?.id ?? 0) season=\(seasonDetail.seasonNumber) count=\(episodeItems.count) layout=horizontal", type: "CrashProbe")
                        }
                    }
                    .padding(.horizontal)
                } else {
                    LazyVStack(spacing: 15) {
                        ForEach(episodeItems) { item in
                            createEpisodeCell(episode: item.episode, index: item.index)
                        }
                    }
                    .onAppear {
                        Logger.shared.log("TVShowSeasonsSection episode list appeared: showId=\(tvShow?.id ?? 0) season=\(seasonDetail.seasonNumber) count=\(episodeItems.count) layout=vertical", type: "CrashProbe")
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
                showTitle: tvShow.name,
                showPosterURL: tvShow.fullPosterURL,
                progress: progress,
                isSelected: isSelected,
                onTap: { episodeTapAction(episode: episode) },
                onMarkWatched: { markAsWatched(episode: episode) },
                onResetProgress: { resetProgress(episode: episode) },
                onDownload: {
                    if hasActiveSources {
                        downloadEpisode = episode
                        selectedEpisodeForSearch = episode
                        showingDownloadSheet = true
                    }
                }
            )
        } else {
            EmptyView()
        }
    }
    
    private func episodeTapAction(episode: TMDBEpisode) {
        selectedEpisodeForSearch = episode
        searchInServicesForEpisode(episode: episode)
    }
    
    /// Look up the original TMDB season/episode numbers for the currently selected episode.
    /// Returns nil for non-anime or when no AniList episode match is found.
    private var originalTMDBNumbers: (season: Int, episode: Int)? {
        guard isAnime,
              let ep = selectedEpisodeForSearch,
              let animeEps = animeEpisodes,
              let match = animeEps.first(where: { $0.seasonNumber == ep.seasonNumber && $0.number == ep.episodeNumber }),
              let s = match.tmdbSeasonNumber,
              let e = match.tmdbEpisodeNumber
        else { return nil }
        return (s, e)
    }
    
    private func searchInServicesForEpisode(episode: TMDBEpisode) {
        guard (tvShow?.name) != nil else { return }
        
        if !hasActiveSources {
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

    private func selectSeason(_ season: TMDBSeason, tvShowId: Int) {
        selectedRelatedAniListId = nil
        selectedSeason = season
        currentSeasonTitle = isAnime ? (animeSeasonTitles?[season.seasonNumber] ?? season.name) : nil
        Logger.shared.log("TVShowSeasonsSection selected season: showId=\(tvShowId) season=\(season.seasonNumber)", type: "CrashProbe")
        loadSeasonDetails(tvShowId: tvShowId, season: season)
    }

    private func selectRelatedEntry(_ entry: AniListRelatedAnimeEntry, tvShowId: Int) {
        selectedRelatedAniListId = entry.id
        selectedSeason = nil
        currentSeasonTitle = entry.title
        isLoadingSeason = false

        let episodes = entry.episodes.map { aniEp in
            TMDBEpisode(
                id: -abs(entry.id * 1000 + aniEp.number),
                name: aniEp.title,
                overview: aniEp.description,
                stillPath: aniEp.stillPath,
                episodeNumber: aniEp.number,
                seasonNumber: aniEp.seasonNumber,
                airDate: aniEp.airDate,
                runtime: aniEp.runtime,
                voteAverage: 0,
                voteCount: 0
            )
        }

        seasonDetail = TMDBSeasonDetail(
            id: -entry.id,
            name: entry.title,
            overview: "",
            posterPath: entry.posterUrl,
            seasonNumber: -entry.id,
            airDate: nil,
            episodes: episodes
        )
        selectedEpisodeForSearch = episodes.first
        Logger.shared.log("TVShowSeasonsSection selected related: showId=\(tvShowId) anilistId=\(entry.id) title=\(entry.title) episodes=\(episodes.count)", type: "CrashProbe")
    }

    private func applyInitialRelatedSelectionIfNeeded(tvShowId: Int) -> Bool {
        guard !didApplyInitialRelatedSelection,
              let initialRelatedAniListId,
              let entry = relatedAnimeEntries.first(where: { $0.id == initialRelatedAniListId })
        else { return false }

        didApplyInitialRelatedSelection = true
        selectRelatedEntry(entry, tvShowId: tvShowId)
        return true
    }

    private func relatedLabel(for entry: AniListRelatedAnimeEntry) -> String {
        if let format = entry.format, !format.isEmpty {
            return format.replacingOccurrences(of: "_", with: " ").capitalized
        }
        return entry.relationType.replacingOccurrences(of: "_", with: " ").capitalized
    }

    private func relatedIconName(for entry: AniListRelatedAnimeEntry) -> String {
        switch entry.format {
        case "MOVIE":
            return "film"
        case "OVA", "SPECIAL":
            return "sparkles"
        default:
            return "tv"
        }
    }
    
    private func loadSeasonDetails(tvShowId: Int, season: TMDBSeason) {
        Logger.shared.log("TVShowSeasonsSection loadSeasonDetails start: showId=\(tvShowId) season=\(season.seasonNumber) isAnime=\(isAnime)", type: "CrashProbe")
        selectedRelatedAniListId = nil
        currentSeasonTitle = isAnime ? (animeSeasonTitles?[season.seasonNumber] ?? season.name) : nil
        isLoadingSeason = true
        seasonDetail = nil
        selectedEpisodeForSearch = nil
        
        Task {
            do {
                // For anime, build season detail from cached AniList episodes with TMDB metadata
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
                        self.seasonDetail = detail
                        self.isLoadingSeason = false
                        if let firstEpisode = detail.episodes.first {
                            self.selectedEpisodeForSearch = firstEpisode
                        }
                        Logger.shared.log("TVShowSeasonsSection loadSeasonDetails anime done: showId=\(tvShowId) season=\(season.seasonNumber) episodes=\(detail.episodes.count)", type: "CrashProbe")
                    }
                } else {
                    // For regular TV shows, fetch from TMDB
                    let detail = try await tmdbService.getSeasonDetails(tvShowId: tvShowId, seasonNumber: season.seasonNumber)
                    await MainActor.run {
                        self.seasonDetail = detail
                        self.isLoadingSeason = false
                        if let firstEpisode = detail.episodes.first {
                            self.selectedEpisodeForSearch = firstEpisode
                        }
                        Logger.shared.log("TVShowSeasonsSection loadSeasonDetails tmdb done: showId=\(tvShowId) season=\(season.seasonNumber) episodes=\(detail.episodes.count)", type: "CrashProbe")
                    }
                }
            } catch {
                await MainActor.run {
                    self.isLoadingSeason = false
                    Logger.shared.log("TVShowSeasonsSection loadSeasonDetails failed: showId=\(tvShowId) season=\(season.seasonNumber) error=\(error.localizedDescription)", type: "CrashProbe")
                }
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
    
    private func startDownloadAllSeason() {
        guard let episodes = seasonDetail?.episodes, !episodes.isEmpty else { return }
        isDownloadingAll = true
        downloadAllQueue = Array(episodes.dropFirst())
        if let first = episodes.first {
            downloadEpisode = first
            selectedEpisodeForSearch = first
            showingDownloadSheet = true
        }
    }
    
    private func showNextDownloadSheet() {
        guard !downloadAllQueue.isEmpty else {
            isDownloadingAll = false
            return
        }
        let next = downloadAllQueue.removeFirst()
        downloadEpisode = next
        selectedEpisodeForSearch = next
        showingDownloadSheet = true
    }
}
