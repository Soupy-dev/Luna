//
//  DownloadServiceSelectionView.swift
//  Luna
//
//  Service selection view for downloads - wraps ModulesSearchResultsSheet
//

import SwiftUI

struct DownloadServiceSelectionView: View {
    let mediaTitle: String
    let originalTitle: String?
    let isMovie: Bool
    let selectedEpisode: TMDBEpisode?
    let tmdbId: Int
    let animeSeasonTitle: String?
    let posterPath: String?
    let onStreamSelected: (URL, [String: String]?) -> Void
    
    var body: some View {
        ModulesSearchResultsSheet(
            mediaTitle: mediaTitle,
            originalTitle: originalTitle,
            isMovie: isMovie,
            selectedEpisode: selectedEpisode,
            tmdbId: tmdbId,
            animeSeasonTitle: animeSeasonTitle,
            posterPath: posterPath
        )
        .environment(\.downloadMode, DownloadModeKey.Value(
            isEnabled: true,
            onDownloadSelected: onStreamSelected
        ))
    }
}
