//
//  DownloadServiceSheet.swift
//  Luna
//
//  Service sheet for downloading media
//

import SwiftUI

struct DownloadServiceSheet: View {
    let mediaInfo: DownloadMediaInfo
    @StateObject private var viewModel: DownloadServiceViewModel
    @Environment(\.presentationMode) var presentationMode
    
    init(mediaInfo: DownloadMediaInfo) {
        self.mediaInfo = mediaInfo
        self._viewModel = StateObject(wrappedValue: DownloadServiceViewModel(mediaInfo: mediaInfo))
    }
    
    var body: some View {
        NavigationView {
            ZStack {
                Color(UIColor.systemBackground).edgesIgnoringSafeArea(.all)
                
                if viewModel.isSearching {
                    ProgressView("Searching...")
                } else if viewModel.results.isEmpty {
                    emptyStateView
                } else {
                    resultsList
                }
            }
            .navigationTitle("Select Stream to Download")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .navigationBarLeading) {
                    Button("Cancel") {
                        presentationMode.wrappedValue.dismiss()
                    }
                }
            }
        }
        .onAppear {
            viewModel.searchForStreams()
        }
    }
    
    private var emptyStateView: some View {
        VStack(spacing: 16) {
            Image(systemName: "magnifyingglass")
                .font(.system(size: 60))
                .foregroundColor(.gray)
            
            Text("No Streams Found")
                .font(.title2)
                .fontWeight(.semibold)
            
            Text("No streaming sources available")
                .font(.subheadline)
                .foregroundColor(.secondary)
        }
    }
    
    private var resultsList: some View {
        List {
            ForEach(viewModel.groupedResults, id: \.service) { group in
                Section(header: Text(group.service)) {
                    ForEach(group.streams, id: \.title) { stream in
                        Button(action: {
                            viewModel.downloadStream(stream)
                            presentationMode.wrappedValue.dismiss()
                        }) {
                            HStack {
                                VStack(alignment: .leading, spacing: 4) {
                                    Text(stream.title ?? "Unknown")
                                        .font(.subheadline)
                                        .fontWeight(.medium)
                                    
                                    if let quality = stream.quality {
                                        Text(quality)
                                            .font(.caption)
                                            .foregroundColor(.secondary)
                                    }
                                }
                                
                                Spacer()
                                
                                Image(systemName: "arrow.down.circle")
                                    .foregroundColor(.blue)
                            }
                        }
                    }
                }
            }
        }
        .listStyle(InsetGroupedListStyle())
    }
}

// MARK: - Download Media Info

struct DownloadMediaInfo {
    let type: DownloadMediaType
    
    // Movie info
    let movieId: Int?
    let movieTitle: String?
    
    // Episode info
    let showId: Int?
    let showTitle: String?
    let seasonNumber: Int?
    let episodeNumber: Int?
    let episodeTitle: String?
    
    let posterURL: String?
    
    // For sequential downloads
    let onDownloadStarted: (() -> Void)?
    
    static func movie(id: Int, title: String, posterURL: String?) -> DownloadMediaInfo {
        DownloadMediaInfo(
            type: .movie,
            movieId: id,
            movieTitle: title,
            showId: nil,
            showTitle: nil,
            seasonNumber: nil,
            episodeNumber: nil,
            episodeTitle: nil,
            posterURL: posterURL,
            onDownloadStarted: nil
        )
    }
    
    static func episode(showId: Int, showTitle: String, seasonNumber: Int, episodeNumber: Int, episodeTitle: String?, posterURL: String?, onDownloadStarted: (() -> Void)? = nil) -> DownloadMediaInfo {
        DownloadMediaInfo(
            type: .episode,
            movieId: nil,
            movieTitle: nil,
            showId: showId,
            showTitle: showTitle,
            seasonNumber: seasonNumber,
            episodeNumber: episodeNumber,
            episodeTitle: episodeTitle,
            posterURL: posterURL,
            onDownloadStarted: onDownloadStarted
        )
    }
}

// MARK: - Download Service ViewModel

class DownloadServiceViewModel: ObservableObject {
    @Published var results: [ServiceResult] = []
    @Published var isSearching = false
    
    private let mediaInfo: DownloadMediaInfo
    private let serviceManager = ServiceManager.shared
    
    init(mediaInfo: DownloadMediaInfo) {
        self.mediaInfo = mediaInfo
    }
    
    var groupedResults: [(service: String, streams: [StreamData])] {
        let grouped = Dictionary(grouping: results) { $0.service }
        return grouped.map { (service: $0.key, streams: $0.value.flatMap { $0.streams }) }
            .sorted { $0.service < $1.service }
    }
    
    func searchForStreams() {
        isSearching = true
        
        let searchQuery: String
        if let movieTitle = mediaInfo.movieTitle {
            searchQuery = movieTitle
        } else if let showTitle = mediaInfo.showTitle, let season = mediaInfo.seasonNumber, let episode = mediaInfo.episodeNumber {
            searchQuery = "\(showTitle) S\(season)E\(episode)"
        } else {
            isSearching = false
            return
        }
        
        Task {
            do {
                let services = serviceManager.activeServices
                var allResults: [ServiceResult] = []
                
                for service in services {
                    if mediaInfo.type == .movie {
                        let streams = try await service.searchMovies(query: searchQuery)
                        if !streams.isEmpty {
                            allResults.append(ServiceResult(service: service.name, streams: streams))
                        }
                    } else {
                        let streams = try await service.searchTVShows(query: searchQuery)
                        if !streams.isEmpty {
                            allResults.append(ServiceResult(service: service.name, streams: streams))
                        }
                    }
                }
                
                await MainActor.run {
                    self.results = allResults
                    self.isSearching = false
                }
            } catch {
                Logger.shared.log("Download search failed: \(error)", type: "Error")
                await MainActor.run {
                    self.isSearching = false
                }
            }
        }
    }
    
    func downloadStream(_ stream: StreamData) {
        guard let urlString = stream.file ?? stream.url, let url = URL(string: urlString) else {
            Logger.shared.log("Invalid stream URL for download", type: "Error")
            return
        }
        
        if mediaInfo.type == .movie, let movieId = mediaInfo.movieId, let movieTitle = mediaInfo.movieTitle {
            DownloadManager.shared.addMovieDownload(
                url: url,
                movieId: movieId,
                movieTitle: movieTitle,
                posterURL: mediaInfo.posterURL
            )
        } else if mediaInfo.type == .episode,
                  let showId = mediaInfo.showId,
                  let showTitle = mediaInfo.showTitle,
                  let seasonNumber = mediaInfo.seasonNumber,
                  let episodeNumber = mediaInfo.episodeNumber {
            DownloadManager.shared.addEpisodeDownload(
                url: url,
                showId: showId,
                showTitle: showTitle,
                seasonNumber: seasonNumber,
                episodeNumber: episodeNumber,
                episodeTitle: mediaInfo.episodeTitle,
                posterURL: mediaInfo.posterURL
            )
        }
        
        mediaInfo.onDownloadStarted?()
        Logger.shared.log("Download added: \(mediaInfo.movieTitle ?? "\(mediaInfo.showTitle ?? "") S\(mediaInfo.seasonNumber ?? 0)E\(mediaInfo.episodeNumber ?? 0)")", type: "Download")
    }
}

struct ServiceResult {
    let service: String
    let streams: [StreamData]
}
