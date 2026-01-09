//
//  DownloadsView.swift
//  Luna
//
//  Downloads management view
//

import SwiftUI

struct DownloadsView: View {
    @StateObject private var downloadManager = DownloadManager.shared
    @Environment(\.presentationMode) var presentationMode
    
    var body: some View {
        NavigationView {
            ZStack {
                Color(UIColor.systemBackground).edgesIgnoringSafeArea(.all)
                
                if downloadManager.downloads.isEmpty {
                    emptyStateView
                } else {
                    downloadsList
                }
            }
            .navigationTitle("Downloads")
            .navigationBarTitleDisplayMode(.large)
            .toolbar {
                ToolbarItem(placement: .navigationBarLeading) {
                    Button("Done") {
                        presentationMode.wrappedValue.dismiss()
                    }
                }
                
                ToolbarItem(placement: .navigationBarTrailing) {
                    Menu {
                        if downloadManager.isPausedAll {
                            Button(action: { downloadManager.resumeAll() }) {
                                Label("Resume All", systemImage: "play.fill")
                            }
                        } else {
                            Button(action: { downloadManager.pauseAll() }) {
                                Label("Pause All", systemImage: "pause.fill")
                            }
                        }
                        
                        Divider()
                        
                        Button(role: .destructive, action: {
                            downloadManager.deleteAllNonCompleted()
                        }) {
                            Label("Delete All Non-Completed", systemImage: "trash")
                        }
                        
                        Button(role: .destructive, action: {
                            downloadManager.deleteAll()
                        }) {
                            Label("Delete All", systemImage: "trash.fill")
                        }
                    } label: {
                        Image(systemName: "ellipsis.circle")
                    }
                }
            }
        }
    }
    
    private var emptyStateView: some View {
        VStack(spacing: 16) {
            Image(systemName: "arrow.down.circle")
                .font(.system(size: 60))
                .foregroundColor(.gray)
            
            Text("No Downloads")
                .font(.title2)
                .fontWeight(.semibold)
            
            Text("Downloaded content will appear here")
                .font(.subheadline)
                .foregroundColor(.secondary)
        }
        .padding()
    }
    
    private var downloadsList: some View {
        List {
            ForEach(downloadManager.groupedDownloads, id: \.key) { group in
                Section(header: Text(group.key)) {
                    ForEach(group.items.sorted(by: { download1, download2 in
                        // Sort episodes by season and episode number
                        if let s1 = download1.seasonNumber, let e1 = download1.episodeNumber,
                           let s2 = download2.seasonNumber, let e2 = download2.episodeNumber {
                            if s1 == s2 {
                                return e1 < e2
                            }
                            return s1 < s2
                        }
                        return download1.createdAt < download2.createdAt
                    })) { download in
                        DownloadRow(download: download)
                    }
                }
            }
        }
        .listStyle(InsetGroupedListStyle())
    }
}

struct DownloadRow: View {
    @ObservedObject var download: DownloadItem
    @StateObject private var downloadManager = DownloadManager.shared
    
    var body: some View {
        HStack(spacing: 12) {
            // Thumbnail
            if let posterURL = download.posterURL, let url = URL(string: posterURL) {
                AsyncImage(url: url) { image in
                    image
                        .resizable()
                        .aspectRatio(contentMode: .fill)
                } placeholder: {
                    Rectangle()
                        .fill(Color.gray.opacity(0.3))
                }
                .frame(width: 50, height: 75)
                .cornerRadius(6)
            } else {
                Rectangle()
                    .fill(Color.gray.opacity(0.3))
                    .frame(width: 50, height: 75)
                    .cornerRadius(6)
                    .overlay(
                        Image(systemName: download.mediaType == .movie ? "film" : "tv")
                            .foregroundColor(.white)
                    )
            }
            
            VStack(alignment: .leading, spacing: 4) {
                Text(download.displayTitle)
                    .font(.subheadline)
                    .fontWeight(.medium)
                    .lineLimit(2)
                
                HStack(spacing: 8) {
                    stateIcon
                    
                    if download.state == .downloading || download.state == .paused {
                        Text(download.formattedProgress)
                            .font(.caption)
                            .foregroundColor(.secondary)
                        
                        Text(download.formattedSize)
                            .font(.caption)
                            .foregroundColor(.secondary)
                    } else if download.state == .completed {
                        Text(download.formattedSize)
                            .font(.caption)
                            .foregroundColor(.secondary)
                    } else if download.state == .failed {
                        Text(download.error ?? "Failed")
                            .font(.caption)
                            .foregroundColor(.red)
                            .lineLimit(1)
                    }
                }
                
                if download.state == .downloading || download.state == .paused {
                    ProgressView(value: download.progress)
                        .progressViewStyle(LinearProgressViewStyle())
                }
            }
            
            Spacer()
            
            // Action buttons
            HStack(spacing: 8) {
                // Play button for completed downloads
                if download.state == .completed, let fileURL = download.localFileURL {
                    Button(action: {
                        playDownload(download: download, fileURL: fileURL)
                    }) {
                        Image(systemName: "play.circle.fill")
                            .font(.title3)
                            .foregroundColor(.green)
                    }
                }
                
                if download.state == .downloading {
                    Button(action: {
                        downloadManager.pauseDownload(download)
                    }) {
                        Image(systemName: "pause.circle.fill")
                            .font(.title3)
                            .foregroundColor(.orange)
                    }
                } else if download.state == .paused || download.state == .queued {
                    Button(action: {
                        downloadManager.resumeDownload(download)
                    }) {
                        Image(systemName: "play.circle.fill")
                            .font(.title3)
                            .foregroundColor(.blue)
                    }
                }
                
                Button(action: {
                    downloadManager.deleteDownload(download)
                }) {
                    Image(systemName: "trash.circle.fill")
                        .font(.title3)
                        .foregroundColor(.red)
                }
            }
        }
        .padding(.vertical, 4)
    }
    
    private func playDownload(download: DownloadItem, fileURL: URL) {
        Logger.shared.log("[Downloads] Playing file: \(fileURL.path)", type: "Download")
        
#if os(iOS)
        let inAppRaw = UserDefaults.standard.string(forKey: "inAppPlayer") ?? "Normal"
        
        if inAppRaw == "mpv" {
            let preset = PlayerPreset.presets.first ?? PlayerPreset(id: .sdrRec709, title: "Default", summary: "", stream: nil, commands: [])
            let pvc = PlayerViewController(url: fileURL, preset: preset, headers: nil, subtitles: nil)
            
            // Set media info based on download type
            if download.mediaType == .movie, let id = download.movieId, let title = download.movieTitle {
                pvc.mediaInfo = .movie(id: id, title: title, posterURL: download.posterURL)
            } else if download.mediaType == .episode,
                      let showId = download.showId,
                      let showTitle = download.showTitle,
                      let season = download.seasonNumber,
                      let episode = download.episodeNumber {
                pvc.mediaInfo = .episode(
                    showId: showId,
                    seasonNumber: season,
                    episodeNumber: episode,
                    showTitle: showTitle,
                    episodeTitle: download.episodeTitle,
                    showPosterURL: download.posterURL
                )
            }
            
            pvc.modalPresentationStyle = .fullScreen
            
            if let windowScene = UIApplication.shared.connectedScenes.first as? UIWindowScene,
               let rootVC = windowScene.windows.first?.rootViewController {
                var topVC = rootVC
                while let presented = topVC.presentedViewController {
                    topVC = presented
                }
                topVC.present(pvc, animated: true)
            }
        } else {
            let vlcPlayer = VLCPlayer()
            
            // Set media info based on download type
            if download.mediaType == .movie, let id = download.movieId, let title = download.movieTitle {
                vlcPlayer.mediaInfo = .movie(id: id, title: title, posterURL: download.posterURL)
            } else if download.mediaType == .episode,
                      let showId = download.showId,
                      let showTitle = download.showTitle,
                      let season = download.seasonNumber,
                      let episode = download.episodeNumber {
                vlcPlayer.mediaInfo = .episode(
                    showId: showId,
                    seasonNumber: season,
                    episodeNumber: episode,
                    showTitle: showTitle,
                    episodeTitle: download.episodeTitle,
                    showPosterURL: download.posterURL
                )
            }
            
            vlcPlayer.load(url: fileURL, headers: nil, preset: nil)
            
            let hostingController = UIHostingController(rootView: vlcPlayer)
            hostingController.modalPresentationStyle = .fullScreen
            
            if let windowScene = UIApplication.shared.connectedScenes.first as? UIWindowScene,
               let rootVC = windowScene.windows.first?.rootViewController {
                var topVC = rootVC
                while let presented = topVC.presentedViewController {
                    topVC = presented
                }
                topVC.present(hostingController, animated: true)
            }
        }
#endif
    }
    
    @ViewBuilder
    private var stateIcon: some View {
        switch download.state {
        case .queued:
            Image(systemName: "clock")
                .font(.caption)
                .foregroundColor(.orange)
            Text("Queued")
                .font(.caption)
                .foregroundColor(.secondary)
        case .downloading:
            Image(systemName: "arrow.down.circle.fill")
                .font(.caption)
                .foregroundColor(.blue)
            Text("Downloading")
                .font(.caption)
                .foregroundColor(.secondary)
        case .paused:
            Image(systemName: "pause.circle")
                .font(.caption)
                .foregroundColor(.orange)
            Text("Paused")
                .font(.caption)
                .foregroundColor(.secondary)
        case .completed:
            Image(systemName: "checkmark.circle.fill")
                .font(.caption)
                .foregroundColor(.green)
            Text("Completed")
                .font(.caption)
                .foregroundColor(.secondary)
        case .failed:
            Image(systemName: "exclamationmark.triangle.fill")
                .font(.caption)
                .foregroundColor(.red)
            Text("Failed")
                .font(.caption)
                .foregroundColor(.red)
        }
    }
}

#Preview {
    DownloadsView()
}
