//
//  DownloadModels.swift
//  Luna
//
//  Created by Soupy-dev on 1/8/26.
//

import Foundation

// MARK: - Quality Preference
enum DownloadQualityPreference: String, CaseIterable {
    case best = "Best"
    case high = "High"
    case medium = "Medium"
    case low = "Low"
    
    static var defaultPreference: DownloadQualityPreference {
        return .best
    }
    
    static var userDefaultsKey: String {
        return "downloadQuality"
    }
    
    static var current: DownloadQualityPreference {
        let storedValue = UserDefaults.standard.string(forKey: userDefaultsKey) ?? defaultPreference.rawValue
        return DownloadQualityPreference(rawValue: storedValue) ?? defaultPreference
    }
    
    var description: String {
        switch self {
        case .best:
            return "Maximum quality available (largest file size)"
        case .high:
            return "High quality (720p or better)"
        case .medium:
            return "Medium quality (480p to 720p)"
        case .low:
            return "Minimum quality available (smallest file size)"
        }
    }
}

// MARK: - Download Type
enum DownloadType: String, Codable {
    case movie
    case episode
    
    var description: String {
        switch self {
        case .movie:
            return "Movie"
        case .episode:
            return "Episode"
        }
    }
}

// MARK: - Download Metadata
struct DownloadMetadata: Codable {
    let title: String
    let overview: String?
    let posterURL: URL?
    let showTitle: String?  // For episodes
    let season: Int?
    let episode: Int?
    let showPosterURL: URL?  // Main show poster
    
    enum CodingKeys: String, CodingKey {
        case title, overview, posterURL, showTitle, season, episode, showPosterURL
    }
}

// MARK: - Downloaded Asset
struct DownloadedAsset: Identifiable, Codable, Equatable {
    let id: UUID
    var name: String
    let downloadDate: Date
    let originalURL: URL
    let localURL: URL
    let type: DownloadType
    let metadata: DownloadMetadata?
    let subtitleURL: URL?
    let localSubtitleURL: URL?
    
    static func == (lhs: DownloadedAsset, rhs: DownloadedAsset) -> Bool {
        return lhs.id == rhs.id
    }
    
    var fileSize: Int64 {
        let fileManager = FileManager.default
        var totalSize: Int64 = 0
        
        if fileManager.fileExists(atPath: localURL.path) {
            var isDirectory: ObjCBool = false
            fileManager.fileExists(atPath: localURL.path, isDirectory: &isDirectory)
            
            if isDirectory.boolValue {
                totalSize += calculateDirectorySize(localURL)
            } else {
                do {
                    let attributes = try fileManager.attributesOfItem(atPath: localURL.path)
                    if let size = attributes[.size] as? Int64 {
                        totalSize += size
                    }
                } catch {
                    Logger.shared.log("Error getting file size: \(error)", type: "Downloads")
                }
            }
        }
        
        if let subtitlePath = localSubtitleURL?.path, fileManager.fileExists(atPath: subtitlePath) {
            do {
                let attributes = try fileManager.attributesOfItem(atPath: subtitlePath)
                if let size = attributes[.size] as? Int64 {
                    totalSize += size
                }
            } catch {}
        }
        
        return totalSize
    }
    
    var fileExists: Bool {
        return FileManager.default.fileExists(atPath: localURL.path)
    }
    
    var groupTitle: String {
        if type == .episode, let showTitle = metadata?.showTitle, !showTitle.isEmpty {
            return showTitle
        }
        return name
    }
    
    var episodeDisplayName: String {
        guard type == .episode else { return name }
        return name
    }
    
    var episodeOrderPriority: Int {
        guard type == .episode else { return 0 }
        let seasonValue = metadata?.season ?? 0
        let episodeValue = metadata?.episode ?? 0
        return (seasonValue * 1000) + episodeValue
    }
    
    private func calculateDirectorySize(_ directoryURL: URL) -> Int64 {
        let fileManager = FileManager.default
        var totalSize: Int64 = 0
        
        do {
            let contents = try fileManager.contentsOfDirectory(
                at: directoryURL,
                includingPropertiesForKeys: [.fileSizeKey, .isDirectoryKey],
                options: []
            )
            
            for url in contents {
                let resourceValues = try url.resourceValues(forKeys: [.isDirectoryKey, .fileSizeKey])
                
                if let isDirectory = resourceValues.isDirectory, isDirectory {
                    totalSize += calculateDirectorySize(url)
                } else {
                    if let fileSize = resourceValues.fileSize {
                        totalSize += Int64(fileSize)
                    }
                }
            }
        } catch {
            Logger.shared.log("Error calculating directory size: \(error)", type: "Downloads")
        }
        
        return totalSize
    }
}

// MARK: - Download Queue Item
struct DownloadQueueItem: Identifiable {
    let id: UUID
    let url: URL
    let headers: [String: String]
    let title: String
    let posterURL: URL?
    let type: DownloadType
    let metadata: DownloadMetadata?
    let subtitleURL: URL?
    let showPosterURL: URL?
    
    var progress: Double = 0
    var status: DownloadStatus = .queued
}

// MARK: - Download Status
enum DownloadStatus: String {
    case queued = "Queued"
    case downloading = "Downloading"
    case paused = "Paused"
    case completed = "Completed"
    case failed = "Failed"
    case cancelled = "Cancelled"
}

// MARK: - Active Download
struct ActiveDownload: Identifiable {
    let id: UUID
    let url: URL
    let headers: [String: String]
    let title: String
    let posterURL: URL?
    let type: DownloadType
    let metadata: DownloadMetadata?
    let subtitleURL: URL?
    let showPosterURL: URL?
    
    var progress: Double = 0
    var status: DownloadStatus = .downloading
    var task: URLSessionDownloadTask?
}
