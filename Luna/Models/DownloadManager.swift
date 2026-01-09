//
//  DownloadManager.swift
//  Luna
//
//  Manages download queue with single concurrent download
//

import Foundation
import Combine

class DownloadManager: ObservableObject {
    static let shared = DownloadManager()
    
    @Published var downloads: [DownloadItem] = []
    @Published var isPausedAll: Bool = false
    
    private var currentDownloadTask: URLSessionDownloadTask?
    private var urlSession: URLSession!
    private let queue = DispatchQueue(label: "com.luna.downloadmanager", attributes: .concurrent)
    private let persistenceKey = "SavedDownloads"
    
    private init() {
        let config = URLSessionConfiguration.background(withIdentifier: "com.luna.downloads")
        config.isDiscretionary = false
        config.sessionSendsLaunchEvents = true
        urlSession = URLSession(configuration: config, delegate: nil, delegateQueue: nil)
        
        loadDownloads()
        processQueue()
    }
    
    // MARK: - Add Downloads
    
    func addMovieDownload(url: URL, movieId: Int, movieTitle: String, posterURL: String?) {
        let download = DownloadItem(url: url, movieId: movieId, movieTitle: movieTitle, posterURL: posterURL)
        queue.async(flags: .barrier) { [weak self] in
            DispatchQueue.main.async {
                self?.downloads.append(download)
                self?.saveDownloads()
                self?.processQueue()
            }
        }
        Logger.shared.log("Added movie download: \(movieTitle)", type: "Download")
    }
    
    func addEpisodeDownload(url: URL, showId: Int, showTitle: String, seasonNumber: Int, episodeNumber: Int, episodeTitle: String?, posterURL: String?) {
        let download = DownloadItem(url: url, showId: showId, showTitle: showTitle, seasonNumber: seasonNumber, episodeNumber: episodeNumber, episodeTitle: episodeTitle, posterURL: posterURL)
        queue.async(flags: .barrier) { [weak self] in
            DispatchQueue.main.async {
                self?.downloads.append(download)
                self?.saveDownloads()
                self?.processQueue()
            }
        }
        Logger.shared.log("Added episode download: \(showTitle) S\(seasonNumber)E\(episodeNumber)", type: "Download")
    }
    
    // MARK: - Download Control
    
    func pauseDownload(_ download: DownloadItem) {
        guard download.state == .downloading else { return }
        
        currentDownloadTask?.cancel()
        currentDownloadTask = nil
        
        download.state = .paused
        saveDownloads()
        Logger.shared.log("Paused download: \(download.displayTitle)", type: "Download")
    }
    
    func resumeDownload(_ download: DownloadItem) {
        guard download.state == .paused || download.state == .queued else { return }
        
        download.state = .queued
        saveDownloads()
        processQueue()
        Logger.shared.log("Resumed download: \(download.displayTitle)", type: "Download")
    }
    
    func deleteDownload(_ download: DownloadItem) {
        if download.state == .downloading {
            currentDownloadTask?.cancel()
            currentDownloadTask = nil
        }
        
        // Delete file if completed
        if download.state == .completed {
            let documentsPath = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)[0]
            let filePath = documentsPath.appendingPathComponent(download.destinationPath)
            try? FileManager.default.removeItem(at: filePath)
        }
        
        downloads.removeAll { $0.id == download.id }
        saveDownloads()
        processQueue()
        Logger.shared.log("Deleted download: \(download.displayTitle)", type: "Download")
    }
    
    func pauseAll() {
        isPausedAll = true
        currentDownloadTask?.cancel()
        currentDownloadTask = nil
        
        for download in downloads where download.state == .downloading {
            download.state = .paused
        }
        saveDownloads()
        Logger.shared.log("Paused all downloads", type: "Download")
    }
    
    func resumeAll() {
        isPausedAll = false
        
        for download in downloads where download.state == .paused {
            download.state = .queued
        }
        saveDownloads()
        processQueue()
        Logger.shared.log("Resumed all downloads", type: "Download")
    }
    
    func deleteAll() {
        for download in downloads {
            if download.state == .completed {
                let documentsPath = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)[0]
                let filePath = documentsPath.appendingPathComponent(download.destinationPath)
                try? FileManager.default.removeItem(at: filePath)
            }
        }
        
        currentDownloadTask?.cancel()
        currentDownloadTask = nil
        downloads.removeAll()
        saveDownloads()
        Logger.shared.log("Deleted all downloads", type: "Download")
    }
    
    func deleteAllNonCompleted() {
        let toDelete = downloads.filter { $0.state != .completed }
        
        for download in toDelete {
            if download.state == .downloading {
                currentDownloadTask?.cancel()
                currentDownloadTask = nil
            }
        }
        
        downloads.removeAll { $0.state != .completed }
        saveDownloads()
        processQueue()
        Logger.shared.log("Deleted \(toDelete.count) non-completed downloads", type: "Download")
    }
    
    // MARK: - Queue Processing
    
    private func processQueue() {
        guard !isPausedAll else { return }
        guard currentDownloadTask == nil else { return }
        
        // Find next queued download
        guard let nextDownload = downloads.first(where: { $0.state == .queued }) else {
            return
        }
        
        startDownload(nextDownload)
    }
    
    private func startDownload(_ download: DownloadItem) {
        download.state = .downloading
        download.startedAt = Date()
        saveDownloads()
        
        Logger.shared.log("Starting download: \(download.displayTitle)", type: "Download")
        
        let task = urlSession.downloadTask(with: download.url)
        
        // Progress observation
        let observation = task.progress.observe(\.fractionCompleted) { [weak self, weak download] progress, _ in
            DispatchQueue.main.async {
                download?.progress = progress.fractionCompleted
                download?.downloadedBytes = progress.completedUnitCount
                download?.totalBytes = progress.totalUnitCount
            }
        }
        
        currentDownloadTask = task
        task.resume()
        
        // Handle completion
        DispatchQueue.global().async { [weak self] in
            task.waitForCompletion()
            
            DispatchQueue.main.async {
                if task.error == nil {
                    self?.downloadCompleted(download, task: task)
                } else {
                    self?.downloadFailed(download, error: task.error?.localizedDescription ?? "Unknown error")
                }
                self?.currentDownloadTask = nil
                self?.processQueue()
            }
        }
    }
    
    private func downloadCompleted(_ download: DownloadItem, task: URLSessionDownloadTask) {
        download.state = .completed
        download.completedAt = Date()
        download.progress = 1.0
        saveDownloads()
        
        Logger.shared.log("Download completed: \(download.displayTitle)", type: "Download")
    }
    
    private func downloadFailed(_ download: DownloadItem, error: String) {
        download.state = .failed
        download.error = error
        saveDownloads()
        
        Logger.shared.log("Download failed: \(download.displayTitle) - \(error)", type: "Error")
    }
    
    // MARK: - Grouping
    
    var groupedDownloads: [(key: String, items: [DownloadItem])] {
        let grouped = Dictionary(grouping: downloads) { download -> String in
            if download.mediaType == .movie {
                return download.movieTitle ?? "Unknown Movie"
            } else {
                return download.showTitle ?? "Unknown Show"
            }
        }
        
        return grouped.sorted { $0.key < $1.key }
    }
    
    // MARK: - Persistence
    
    private func saveDownloads() {
        queue.async(flags: .barrier) { [weak self] in
            guard let self = self else { return }
            
            do {
                let data = try JSONEncoder().encode(self.downloads)
                UserDefaults.standard.set(data, forKey: self.persistenceKey)
            } catch {
                Logger.shared.log("Failed to save downloads: \(error)", type: "Error")
            }
        }
    }
    
    private func loadDownloads() {
        guard let data = UserDefaults.standard.data(forKey: persistenceKey) else { return }
        
        do {
            downloads = try JSONDecoder().decode([DownloadItem].self, from: data)
            
            // Reset downloading state to queued on app restart
            for download in downloads where download.state == .downloading {
                download.state = .queued
            }
            
            Logger.shared.log("Loaded \(downloads.count) downloads", type: "Download")
        } catch {
            Logger.shared.log("Failed to load downloads: \(error)", type: "Error")
        }
    }
}

extension URLSessionDownloadTask {
    func waitForCompletion() {
        let semaphore = DispatchSemaphore(value: 0)
        
        DispatchQueue.global().asyncAfter(deadline: .now() + 0.1) {
            while self.state == .running || self.state == .suspended {
                Thread.sleep(forTimeInterval: 0.1)
            }
            semaphore.signal()
        }
        
        semaphore.wait()
    }
}
