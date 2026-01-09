//
//  DownloadMovieSheet.swift
//  Luna
//
//  Wrapper for ModulesSearchResultsSheet in download mode for movies
//

import SwiftUI

struct DownloadMovieSheet: View {
    let movie: TMDBMovieDetail
    let romajiTitle: String?
    let onDownloadSelected: (URL) -> Void
    
    @Environment(\.presentationMode) var presentationMode
    
    var body: some View {
        DownloadServiceSelectionView(
            mediaTitle: movie.title,
            originalTitle: romajiTitle,
            isMovie: true,
            selectedEpisode: nil,
            tmdbId: movie.id,
            animeSeasonTitle: nil,
            posterPath: movie.posterPath,
            onStreamSelected: { url, headers in
                onDownloadSelected(url)
                presentationMode.wrappedValue.dismiss()
            }
        )
    }
}
