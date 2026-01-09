//
//  DownloadItem.swift
//  Luna
//
//  Download item model for tracking media downloads
//

import Foundation

enum DownloadState: String, Codable {
    case queued
    case downloading
    case paused
    case completed
    case failed
}

enum DownloadMediaType: String, Codable {
    case movie
    case episode
}

class DownloadItem: Identifiable, Codable, ObservableObject {
    let id: UUID
    @Published var state: DownloadState
    @Published var progress: Double
    @Published var downloadedBytes: Int64
    @Published var totalBytes: Int64
    
    let url: URL
    let destinationPath: String
    let mediaType: DownloadMediaType
    
    // Movie metadata
    let movieId: Int?
    let movieTitle: String?
    
    // Episode metadata
    let showId: Int?
    let showTitle: String?
    let seasonNumber: Int?
    let episodeNumber: Int?
    let episodeTitle: String?
    
    let posterURL: String?
    let createdAt: Date
    var startedAt: Date?
    var completedAt: Date?
    var error: String?
    
    // For Codable
    enum CodingKeys: String, CodingKey {
        case id, state, progress, downloadedBytes, totalBytes
        case url, destinationPath, mediaType
        case movieId, movieTitle
        case showId, showTitle, seasonNumber, episodeNumber, episodeTitle
        case posterURL, createdAt, startedAt, completedAt, error
    }
    
    // Movie initializer
    init(url: URL, movieId: Int, movieTitle: String, posterURL: String?) {
        self.id = UUID()
        self.state = .queued
        self.progress = 0
        self.downloadedBytes = 0
        self.totalBytes = 0
        
        self.url = url
        self.mediaType = .movie
        self.destinationPath = "Downloads/Movies/\(movieTitle.sanitizedFilename())-\(movieId).mp4"
        
        self.movieId = movieId
        self.movieTitle = movieTitle
        
        self.showId = nil
        self.showTitle = nil
        self.seasonNumber = nil
        self.episodeNumber = nil
        self.episodeTitle = nil
        
        self.posterURL = posterURL
        self.createdAt = Date()
    }
    
    // Episode initializer
    init(url: URL, showId: Int, showTitle: String, seasonNumber: Int, episodeNumber: Int, episodeTitle: String?, posterURL: String?) {
        self.id = UUID()
        self.state = .queued
        self.progress = 0
        self.downloadedBytes = 0
        self.totalBytes = 0
        
        self.url = url
        self.mediaType = .episode
        self.destinationPath = "Downloads/Shows/\(showTitle.sanitizedFilename())/Season \(seasonNumber)/S\(String(format: "%02d", seasonNumber))E\(String(format: "%02d", episodeNumber)) - \(episodeTitle?.sanitizedFilename() ?? "Episode \(episodeNumber)").mp4"
        
        self.movieId = nil
        self.movieTitle = nil
        
        self.showId = showId
        self.showTitle = showTitle
        self.seasonNumber = seasonNumber
        self.episodeNumber = episodeNumber
        self.episodeTitle = episodeTitle
        
        self.posterURL = posterURL
        self.createdAt = Date()
    }
    
    required init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        id = try container.decode(UUID.self, forKey: .id)
        state = try container.decode(DownloadState.self, forKey: .state)
        progress = try container.decode(Double.self, forKey: .progress)
        downloadedBytes = try container.decode(Int64.self, forKey: .downloadedBytes)
        totalBytes = try container.decode(Int64.self, forKey: .totalBytes)
        url = try container.decode(URL.self, forKey: .url)
        destinationPath = try container.decode(String.self, forKey: .destinationPath)
        mediaType = try container.decode(DownloadMediaType.self, forKey: .mediaType)
        movieId = try container.decodeIfPresent(Int.self, forKey: .movieId)
        movieTitle = try container.decodeIfPresent(String.self, forKey: .movieTitle)
        showId = try container.decodeIfPresent(Int.self, forKey: .showId)
        showTitle = try container.decodeIfPresent(String.self, forKey: .showTitle)
        seasonNumber = try container.decodeIfPresent(Int.self, forKey: .seasonNumber)
        episodeNumber = try container.decodeIfPresent(Int.self, forKey: .episodeNumber)
        episodeTitle = try container.decodeIfPresent(String.self, forKey: .episodeTitle)
        posterURL = try container.decodeIfPresent(String.self, forKey: .posterURL)
        createdAt = try container.decode(Date.self, forKey: .createdAt)
        startedAt = try container.decodeIfPresent(Date.self, forKey: .startedAt)
        completedAt = try container.decodeIfPresent(Date.self, forKey: .completedAt)
        error = try container.decodeIfPresent(String.self, forKey: .error)
    }
    
    func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(id, forKey: .id)
        try container.encode(state, forKey: .state)
        try container.encode(progress, forKey: .progress)
        try container.encode(downloadedBytes, forKey: .downloadedBytes)
        try container.encode(totalBytes, forKey: .totalBytes)
        try container.encode(url, forKey: .url)
        try container.encode(destinationPath, forKey: .destinationPath)
        try container.encode(mediaType, forKey: .mediaType)
        try container.encodeIfPresent(movieId, forKey: .movieId)
        try container.encodeIfPresent(movieTitle, forKey: .movieTitle)
        try container.encodeIfPresent(showId, forKey: .showId)
        try container.encodeIfPresent(showTitle, forKey: .showTitle)
        try container.encodeIfPresent(seasonNumber, forKey: .seasonNumber)
        try container.encodeIfPresent(episodeNumber, forKey: .episodeNumber)
        try container.encodeIfPresent(episodeTitle, forKey: .episodeTitle)
        try container.encodeIfPresent(posterURL, forKey: .posterURL)
        try container.encode(createdAt, forKey: .createdAt)
        try container.encodeIfPresent(startedAt, forKey: .startedAt)
        try container.encodeIfPresent(completedAt, forKey: .completedAt)
        try container.encodeIfPresent(error, forKey: .error)
    }
    
    var displayTitle: String {
        if let movieTitle = movieTitle {
            return movieTitle
        } else if let showTitle = showTitle, let season = seasonNumber, let episode = episodeNumber {
            if let episodeTitle = episodeTitle {
                return "\(showTitle) - S\(season)E\(episode): \(episodeTitle)"
            } else {
                return "\(showTitle) - S\(season)E\(episode)"
            }
        }
        return "Unknown"
    }
    
    var formattedProgress: String {
        return String(format: "%.1f%%", progress * 100)
    }
    
    var formattedSize: String {
        let downloaded = ByteCountFormatter.string(fromByteCount: downloadedBytes, countStyle: .file)
        if totalBytes > 0 {
            let total = ByteCountFormatter.string(fromByteCount: totalBytes, countStyle: .file)
            return "\(downloaded) / \(total)"
        }
        return downloaded
    }
}

extension String {
    func sanitizedFilename() -> String {
        let invalidCharacters = CharacterSet(charactersIn: ":/\\?%*|\"<>")
        return components(separatedBy: invalidCharacters).joined(separator: "_")
    }
}
