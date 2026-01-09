//
//  DownloadsView.swift
//  Luna
//
//  Created by Soupy-dev on 1/8/26.
//

import SwiftUI
import UIKit

struct DownloadsView: View {
    @StateObject private var downloadManager = DownloadManager.shared
    @State private var selectedTab = 0
    @State private var showDeleteAlert = false
    @State private var assetToDelete: DownloadedAsset?
    
    var body: some View {
        ZStack {
            VStack(spacing: 0) {
                // Tab selector
                Picker("", selection: $selectedTab) {
                    Text("Active").tag(0)
                    Text("Completed").tag(1)
                }
                .pickerStyle(.segmented)
                .padding()
                
                Divider()
                
                // Content
                if selectedTab == 0 {
                    activeDownloadsView
                } else {
                    completedDownloadsView
                }
            }
            .navigationTitle("Downloads")
            
            // Alert for delete
            .alert("Delete Download", isPresented: $showDeleteAlert) {
                Button("Cancel", role: .cancel) {}
                Button("Delete", role: .destructive) {
                    if let asset = assetToDelete {
                        downloadManager.deleteAsset(asset)
                    }
                }
            } message: {
                if let asset = assetToDelete {
                    Text("Are you sure you want to delete '\(asset.name)'?")
                }
            }
        }
    }
    
    @ViewBuilder
    private var activeDownloadsView: some View {
        if downloadManager.activeDownload == nil && downloadManager.downloadQueue.isEmpty {
            emptyView(title: "No Active Downloads", message: "Downloads will appear here")
        } else {
            ScrollView {
                VStack(spacing: 16) {
                    if let active = downloadManager.activeDownload {
                        activeDownloadCardView(active)
                    }
                    
                    if !downloadManager.downloadQueue.isEmpty {
                        VStack(alignment: .leading, spacing: 8) {
                            Text("Queue (\(downloadManager.downloadQueue.count))")
                                .font(.headline)
                                .padding(.horizontal)
                            
                            ForEach(downloadManager.downloadQueue) { item in
                                queueItemRowView(item)
                            }
                        }
                    }
                    
                    // Control buttons
                    controlButtonsView
                }
                .padding()
            }
        }
    }
    
    @ViewBuilder
    private func activeDownloadCardView(_ download: ActiveDownload) -> some View {
        VStack(spacing: 12) {
            HStack {
                VStack(alignment: .leading, spacing: 4) {
                    Text(download.title)
                        .font(.headline)
                        .lineLimit(2)
                    
                    Text("Downloading...")
                        .font(.caption)
                        .foregroundColor(.secondary)
                }
                
                Spacer()
                
                if let poster = download.posterURL {
                    AsyncImage(url: poster) { image in
                        image.resizable().aspectRatio(contentMode: .fill)
                    } placeholder: {
                        Color.gray.opacity(0.3)
                    }
                    .frame(width: 50, height: 75)
                    .clipShape(RoundedRectangle(cornerRadius: 4))
                }
            }
            
            // Progress bar
            VStack(spacing: 4) {
                ProgressView(value: download.progress)
                    .tint(.accentColor)
                
                Text("\(Int(download.progress * 100))%")
                    .font(.caption2)
                    .foregroundColor(.secondary)
            }
            
            // Control buttons for active download
            HStack(spacing: 12) {
                if downloadManager.activeDownload?.status == .downloading {
                    Button(action: { downloadManager.pauseCurrentDownload() }) {
                        Label("Pause", systemImage: "pause.fill")
                            .font(.caption)
                    }
                    .buttonStyle(.bordered)
                } else if downloadManager.activeDownload?.status == .paused {
                    Button(action: { downloadManager.resumeCurrentDownload() }) {
                        Label("Resume", systemImage: "play.fill")
                            .font(.caption)
                    }
                    .buttonStyle(.bordered)
                }
                
                Button(action: { downloadManager.cancelCurrentDownload() }) {
                    Label("Cancel", systemImage: "xmark")
                        .font(.caption)
                }
                .buttonStyle(.bordered)
                .tint(.red)
                
                Spacer()
            }
        }
        .padding()
        .background(.ultraThinMaterial)
        .clipShape(RoundedRectangle(cornerRadius: 8))
    }
    
    @ViewBuilder
    private func queueItemRowView(_ item: DownloadQueueItem) -> some View {
        HStack {
            VStack(alignment: .leading, spacing: 4) {
                Text(item.title)
                    .font(.subheadline)
                    .lineLimit(1)
                
                Text("Queued")
                    .font(.caption2)
                    .foregroundColor(.secondary)
            }
            
            Spacer()
            
            Button(action: {
                if let index = downloadManager.downloadQueue.firstIndex(where: { $0.id == item.id }) {
                    downloadManager.downloadQueue.remove(at: index)
                }
            }) {
                Image(systemName: "xmark")
                    .foregroundColor(.secondary)
            }
        }
        .padding(.horizontal)
        .padding(.vertical, 8)
        .background(Color(.systemGray6))
        .clipShape(RoundedRectangle(cornerRadius: 6))
    }
    
    @ViewBuilder
    private var controlButtonsView: some View {
        HStack(spacing: 12) {
            if downloadManager.activeDownload != nil {
                if !downloadManager.isPausedAll {
                    Button(action: { downloadManager.pauseAll() }) {
                        Label("Pause All", systemImage: "pause.fill")
                            .font(.caption)
                    }
                    .buttonStyle(.bordered)
                } else {
                    Button(action: { downloadManager.resumeAll() }) {
                        Label("Resume All", systemImage: "play.fill")
                            .font(.caption)
                    }
                    .buttonStyle(.bordered)
                }
            }
            
            Spacer()
            
            if !downloadManager.downloadQueue.isEmpty {
                Button(action: { downloadManager.deleteNonCompleted() }) {
                    Label("Clear Queue", systemImage: "trash")
                        .font(.caption)
                }
                .buttonStyle(.bordered)
                .tint(.orange)
            }
        }
        .padding()
    }
    
    @ViewBuilder
    private var completedDownloadsView: some View {
        if downloadManager.completedAssets.isEmpty {
            emptyView(title: "No Downloads", message: "Downloaded media will appear here")
        } else {
            ScrollView {
                VStack(spacing: 12) {
                    downloadsSummary
                    
                    downloadedGroupedList
                    
                    deleteAllButton
                }
                .padding()
            }
        }
    }
    
    @ViewBuilder
    private var downloadsSummary: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("\(downloadManager.completedAssets.count) Downloaded")
                .font(.headline)
            
            let totalSize = downloadManager.completedAssets.reduce(0) { $0 + $1.fileSize }
            Text("Total: \(formatBytes(totalSize))")
                .font(.caption)
                .foregroundColor(.secondary)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding()
        .background(.ultraThinMaterial)
        .clipShape(RoundedRectangle(cornerRadius: 8))
    }
    
    @ViewBuilder
    private var downloadedGroupedList: some View {
        let grouped = Dictionary(grouping: downloadManager.completedAssets) { $0.groupTitle }
        
        ForEach(grouped.keys.sorted(), id: \.self) { groupTitle in
            VStack(alignment: .leading, spacing: 8) {
                Text(groupTitle)
                    .font(.subheadline)
                    .fontWeight(.semibold)
                    .padding(.horizontal)
                
                if let assets = grouped[groupTitle] {
                    ForEach(assets.sorted { $0.episodeOrderPriority < $1.episodeOrderPriority }) { asset in
                        downloadAssetRowView(asset)
                    }
                }
            }
        }
    }
    
    @ViewBuilder
    private func downloadAssetRowView(_ asset: DownloadedAsset) -> some View {
        HStack {
            VStack(alignment: .leading, spacing: 4) {
                Text(asset.episodeDisplayName)
                    .font(.subheadline)
                    .lineLimit(2)
                
                Text(formatBytes(asset.fileSize))
                    .font(.caption2)
                    .foregroundColor(.secondary)
            }
            
            Spacer()
            
            Menu {
                Button(action: {
                    playDownloadedAsset(asset)
                }) {
                    Label("Play", systemImage: "play.fill")
                }
                
                Button(role: .destructive, action: {
                    assetToDelete = asset
                    showDeleteAlert = true
                }) {
                    Label("Delete", systemImage: "trash")
                }
            } label: {
                Image(systemName: "ellipsis")
                    .foregroundColor(.secondary)
            }
        }
        .padding(.horizontal)
        .padding(.vertical, 8)
        .background(Color(.systemGray6))
        .clipShape(RoundedRectangle(cornerRadius: 6))
    }
    
    @ViewBuilder
    private var deleteAllButton: some View {
        Button(role: .destructive, action: {
            downloadManager.deleteAll()
        }) {
            Label("Delete All Downloads", systemImage: "trash")
                .frame(maxWidth: .infinity)
        }
        .buttonStyle(.bordered)
        .tint(.red)
    }
    
    @ViewBuilder
    private func emptyView(title: String, message: String) -> some View {
        VStack(spacing: 16) {
            Image(systemName: "arrow.down.circle")
                .font(.largeTitle)
                .foregroundColor(.secondary)
            
            VStack(spacing: 4) {
                Text(title)
                    .font(.headline)
                Text(message)
                    .font(.caption)
                    .foregroundColor(.secondary)
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .center)
    }
    
    private func formatBytes(_ bytes: Int64) -> String {
        let formatter = ByteCountFormatter()
        formatter.allowedUnits = [.useKB, .useMB, .useGB]
        formatter.countStyle = .file
        return formatter.string(fromByteCount: bytes)
    }
    
    private func playDownloadedAsset(_ asset: DownloadedAsset) {
        guard FileManager.default.fileExists(atPath: asset.localURL.path) else {
            Logger.shared.log("Downloaded file not found at \(asset.localURL.path)", type: "Downloads")
            return
        }
        
        let usePlayerViewController = UserDefaults.standard.bool(forKey: "usePlayerViewController")
        
        if usePlayerViewController {
            // Open with mpv PlayerViewController
            if let windowScene = UIApplication.shared.connectedScenes.first as? UIWindowScene,
               let rootViewController = windowScene.windows.first?.rootViewController {
                let playerVC = PlayerViewController(url: asset.localURL, preset: .hls)
                playerVC.modalPresentationStyle = .fullScreen
                rootViewController.present(playerVC, animated: true)
            }
        } else {
            // Open with standard AVPlayer (NormalPlayer)
            if let windowScene = UIApplication.shared.connectedScenes.first as? UIWindowScene,
               let rootViewController = windowScene.windows.first?.rootViewController {
                let normalPlayer = NormalPlayer()
                normalPlayer.player = AVPlayer(url: asset.localURL)
                rootViewController.present(normalPlayer, animated: true)
            }
        }
        
        Logger.shared.log("Playing downloaded: \(asset.name)", type: "Downloads")
    }
}

#Preview {
    DownloadsView()
}