//
//  DownloadManager.swift
//  Luna
//
//  Created by Soupy-dev on 1/8/26.
//

import Foundation
import Combine

class DownloadManager: NSObject, ObservableObject, URLSessionDownloadDelegate {
    @Published var activeDownload: ActiveDownload?
    @Published var downloadQueue: [DownloadQueueItem] = []
    @Published var completedAssets: [DownloadedAsset] = []
    @Published var isPausedAll: Bool = false
    
    static let shared = DownloadManager()
    
    private var downloadURLSession: URLSession?
    private var currentTask: URLSessionDownloadTask?
    private var lastProgress: Double = 0
    
    override init() {
        super.init()
        initializeDownloadSession()
        loadCompletedAssets()
    }
    
    // MARK: - Session Setup
    
    private func initializeDownloadSession() {
        let config = URLSessionConfiguration.background(withIdentifier: "luna-downloads-\(UUID().uuidString)")
        config.waitsForConnectivity = true
        config.allowsCellularAccess = true
        
        downloadURLSession = URLSession(
            configuration: config,
            delegate: self,
            delegateQueue: .main
        )
    }
    
    // MARK: - Queue Management
    
    func addToQueue(
        url: URL,
        headers: [String: String],
        title: String,
        posterURL: URL?,
        type: DownloadType,
        metadata: DownloadMetadata?,
        subtitleURL: URL?,
        showPosterURL: URL?
    ) {
        let item = DownloadQueueItem(
            id: UUID(),
            url: url,
            headers: headers,
            title: title,
            posterURL: posterURL,
            type: type,
            metadata: metadata,
            subtitleURL: subtitleURL,
            showPosterURL: showPosterURL
        )
        
        downloadQueue.append(item)
        DispatchQueue.main.async {
            self.objectWillChange.send()
        }
        
        // Process queue if nothing is active
        if activeDownload == nil && !isPausedAll {
            processQueue()
        }
    }
    
    func processQueue() {
        guard !downloadQueue.isEmpty, activeDownload == nil, !isPausedAll else { return }
        
        let nextItem = downloadQueue.removeFirst()
        startDownload(item: nextItem)
    }
    
    // MARK: - Download Control
    
    private func startDownload(item: DownloadQueueItem) {
        guard let session = downloadURLSession else { return }
        
        var request = URLRequest(url: item.url)
        item.headers.forEach { request.setValue($0.value, forHTTPHeaderField: $0.key) }
        
        let task = session.downloadTask(with: request)
        currentTask = task
        
        activeDownload = ActiveDownload(
            id: item.id,
            url: item.url,
            headers: item.headers,
            title: item.title,
            posterURL: item.posterURL,
            type: item.type,
            metadata: item.metadata,
            subtitleURL: item.subtitleURL,
            showPosterURL: item.showPosterURL,
            progress: 0,
            status: .downloading,
            task: task
        )
        
        lastProgress = 0
        task.resume()
        
        DispatchQueue.main.async {
            self.objectWillChange.send()
        }
    }
    
    func pauseCurrentDownload() {
        guard let task = currentTask else { return }
        task.pause()
        
        if var active = activeDownload {
            active.status = .paused
            activeDownload = active
        }
        
        DispatchQueue.main.async {
            self.objectWillChange.send()
        }
    }
    
    func resumeCurrentDownload() {
        guard let task = currentTask else { return }
        task.resume()
        
        if var active = activeDownload {
            active.status = .downloading
            activeDownload = active
        }
        
        DispatchQueue.main.async {
            self.objectWillChange.send()
        }
    }
    
    func cancelCurrentDownload() {
        guard let task = currentTask else { return }
        task.cancel()
        currentTask = nil
        
        // Remove from queue if it was queued
        if let idx = downloadQueue.firstIndex(where: { $0.id == activeDownload?.id }) {
            downloadQueue.remove(at: idx)
        }
        
        activeDownload = nil
        
        DispatchQueue.main.async {
            self.objectWillChange.send()
        }
    }
    
    func pauseAll() {
        isPausedAll = true
        pauseCurrentDownload()
    }
    
    func resumeAll() {
        isPausedAll = false
        
        if activeDownload != nil {
            resumeCurrentDownload()
        } else if !downloadQueue.isEmpty {
            processQueue()
        }
    }
    
    func deleteAll() {
        cancelCurrentDownload()
        downloadQueue.removeAll()
        completedAssets.removeAll()
        DownloadPersistence.save([])
        
        DispatchQueue.main.async {
            self.objectWillChange.send()
        }
    }
    
    func deleteNonCompleted() {
        cancelCurrentDownload()
        downloadQueue.removeAll()
        
        DispatchQueue.main.async {
            self.objectWillChange.send()
        }
    }
    
    // MARK: - Asset Management
    
    private func loadCompletedAssets() {
        completedAssets = DownloadPersistence.load()
    }
    
    func deleteAsset(_ asset: DownloadedAsset) {
        let fileManager = FileManager.default
        
        // Delete files
        try? fileManager.removeItem(at: asset.localURL)
        if let subtitleURL = asset.localSubtitleURL {
            try? fileManager.removeItem(at: subtitleURL)
        }
        
        // Remove from persistence
        DownloadPersistence.delete(id: asset.id)
        
        // Update local list
        completedAssets.removeAll { $0.id == asset.id }
        
        DispatchQueue.main.async {
            self.objectWillChange.send()
        }
    }
    
    // MARK: - URLSessionDownloadDelegate
    
    func urlSession(
        _ session: URLSession,
        downloadTask: URLSessionDownloadTask,
        didFinishDownloadingTo location: URL
    ) {
        guard let active = activeDownload else { return }
        
        let fileManager = FileManager.default
        let downloadsDir = fileManager.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("LunaDownloads")
        
        try? fileManager.createDirectory(at: downloadsDir, withIntermediateDirectories: true)
        
        let finalURL = downloadsDir.appendingPathComponent("\(active.id).mp4")
        
        do {
            if fileManager.fileExists(atPath: finalURL.path) {
                try fileManager.removeItem(at: finalURL)
            }
            try fileManager.moveItem(at: location, to: finalURL)
            
            let asset = DownloadedAsset(
                id: active.id,
                name: active.title,
                downloadDate: Date(),
                originalURL: active.url,
                localURL: finalURL,
                type: active.type,
                metadata: active.metadata,
                subtitleURL: active.subtitleURL,
                localSubtitleURL: nil
            )
            
            DownloadPersistence.upsert(asset)
            completedAssets.append(asset)
            
            activeDownload = nil
            currentTask = nil
            
            DispatchQueue.main.async {
                self.objectWillChange.send()
                
                // Auto-start next download if not paused
                if !self.isPausedAll && !self.downloadQueue.isEmpty {
                    self.processQueue()
                }
            }
            
            Logger.shared.log("Download completed: \(active.title)", type: "Downloads")
        } catch {
            Logger.shared.log("Failed to move downloaded file: \(error)", type: "Downloads")
            activeDownload = nil
            currentTask = nil
            
            DispatchQueue.main.async {
                self.objectWillChange.send()
                
                // Try next download
                if !self.isPausedAll && !self.downloadQueue.isEmpty {
                    self.processQueue()
                }
            }
        }
    }
    
    func urlSession(
        _ session: URLSession,
        downloadTask: URLSessionDownloadTask,
        didWriteData bytesWritten: Int64,
        totalBytesWritten: Int64,
        totalBytesExpectedToWrite: Int64
    ) {
        guard totalBytesExpectedToWrite > 0 else { return }
        
        let progress = Double(totalBytesWritten) / Double(totalBytesExpectedToWrite)
        
        // Throttle progress updates
        if abs(progress - lastProgress) > 0.01 {
            lastProgress = progress
            
            if var active = activeDownload {
                active.progress = progress
                activeDownload = active
            }
            
            DispatchQueue.main.async {
                self.objectWillChange.send()
            }
        }
    }
    
    func urlSession(
        _ session: URLSession,
        task: URLSessionTask,
        didCompleteWithError error: Error?
    ) {
        if let error = error {
            Logger.shared.log("Download error: \(error.localizedDescription)", type: "Downloads")
            
            activeDownload = nil
            currentTask = nil
            
            DispatchQueue.main.async {
                self.objectWillChange.send()
                
                // Auto-start next download if not paused
                if !self.isPausedAll && !self.downloadQueue.isEmpty {
                    self.processQueue()
                }
            }
        }
    }
}
