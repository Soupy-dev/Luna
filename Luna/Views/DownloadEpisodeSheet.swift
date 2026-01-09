//
//  DownloadEpisodeSheet.swift
//  Luna
//
//  Wrapper for ModulesSearchResultsSheet in download mode for episodes
//

import SwiftUI

struct DownloadEpisodeSheet: View {
    let episode: TMDBEpisode
    let show: TMDBTVShowWithSeasons
    let searchTitle: String
    let romajiTitle: String?
    let isAnime: Bool
    let onDownloadSelected: (URL) -> Void
    
    @Environment(\.presentationMode) var presentationMode
    
    var body: some View {
        DownloadServiceSelectionView(
            mediaTitle: searchTitle,
            originalTitle: romajiTitle,
            isMovie: false,
            selectedEpisode: episode,
            tmdbId: show.id,
            animeSeasonTitle: isAnime ? "anime" : nil,
            posterPath: show.posterPath,
            onStreamSelected: { url, headers in
                onDownloadSelected(url)
                presentationMode.wrappedValue.dismiss()
            }
        )
    }
}
