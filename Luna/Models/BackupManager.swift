//
//  BackupManager.swift
//  Luna
//
//  Created by Soupy-dev on 05/01/2026.
//

import Foundation
import UIKit

// MARK: - Backup Data Model

struct BackupData: Codable {
    let version: String
    let createdDate: Date
    
    // Settings
    var accentColor: Data?
    var tmdbLanguage: String
    var selectedAppearance: String
    var enableSubtitlesByDefault: Bool
    var defaultSubtitleLanguage: String

    var preferredAnimeAudioLanguage: String
    var playerChoice: String
    var showScheduleTab: Bool
    var showLocalScheduleTime: Bool
    
    // Collections (Library)
    var collections: [BackupCollection] = []
    
    // Progress Tracking
    var progressData: ProgressData = ProgressData()
    
    // Tracker Services (AniList, Trakt, etc.)
    var trackerState: TrackerState = TrackerState()
    
    // Catalogs
    var catalogs: [Catalog] = []

    // Services (custom JS modules)
    var services: [BackupService] = []

    enum CodingKeys: String, CodingKey {
        case version, createdDate
        case accentColor, tmdbLanguage, selectedAppearance, enableSubtitlesByDefault, defaultSubtitleLanguage, preferredAnimeAudioLanguage, playerChoice, showScheduleTab, showLocalScheduleTime
        case collections, progressData, trackerState, catalogs, services
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)

        version = try container.decodeIfPresent(String.self, forKey: .version) ?? "1.0"
        createdDate = try container.decode(Date.self, forKey: .createdDate)
        accentColor = try container.decodeIfPresent(Data.self, forKey: .accentColor)
        tmdbLanguage = try container.decodeIfPresent(String.self, forKey: .tmdbLanguage) ?? "en-US"
        selectedAppearance = try container.decodeIfPresent(String.self, forKey: .selectedAppearance) ?? "system"
        enableSubtitlesByDefault = try container.decodeIfPresent(Bool.self, forKey: .enableSubtitlesByDefault) ?? false
        defaultSubtitleLanguage = try container.decodeIfPresent(String.self, forKey: .defaultSubtitleLanguage) ?? "eng"

        preferredAnimeAudioLanguage = try container.decodeIfPresent(String.self, forKey: .preferredAnimeAudioLanguage) ?? "jpn"
        playerChoice = try container.decodeIfPresent(String.self, forKey: .playerChoice) ?? "mpv"
        showScheduleTab = try container.decodeIfPresent(Bool.self, forKey: .showScheduleTab) ?? true
        showLocalScheduleTime = try container.decodeIfPresent(Bool.self, forKey: .showLocalScheduleTime) ?? true
        collections = try container.decodeIfPresent([BackupCollection].self, forKey: .collections) ?? []
        progressData = try container.decodeIfPresent(ProgressData.self, forKey: .progressData) ?? ProgressData()
        trackerState = try container.decodeIfPresent(TrackerState.self, forKey: .trackerState) ?? TrackerState()
        catalogs = try container.decodeIfPresent([Catalog].self, forKey: .catalogs) ?? []
        services = try container.decodeIfPresent([BackupService].self, forKey: .services) ?? []
    }

    func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(version, forKey: .version)
        try container.encode(createdDate, forKey: .createdDate)
        try container.encodeIfPresent(accentColor, forKey: .accentColor)
        try container.encode(tmdbLanguage, forKey: .tmdbLanguage)
        try container.encode(selectedAppearance, forKey: .selectedAppearance)
        try container.encode(enableSubtitlesByDefault, forKey: .enableSubtitlesByDefault)
        try container.encode(defaultSubtitleLanguage, forKey: .defaultSubtitleLanguage)

        try container.encode(preferredAnimeAudioLanguage, forKey: .preferredAnimeAudioLanguage)
        try container.encode(playerChoice, forKey: .playerChoice)
        try container.encode(showScheduleTab, forKey: .showScheduleTab)
        try container.encode(showLocalScheduleTime, forKey: .showLocalScheduleTime)
        try container.encode(collections, forKey: .collections)
        try container.encode(progressData, forKey: .progressData)
        try container.encode(trackerState, forKey: .trackerState)
        try container.encode(catalogs, forKey: .catalogs)
        try container.encode(services, forKey: .services)
    }
    
    init(
        version: String = "1.0",
        createdDate: Date,
        accentColor: Data? = nil,
        tmdbLanguage: String,
        selectedAppearance: String,
        enableSubtitlesByDefault: Bool,
        defaultSubtitleLanguage: String,

        preferredAnimeAudioLanguage: String,
        playerChoice: String,
        showScheduleTab: Bool,
        showLocalScheduleTime: Bool,
        collections: [BackupCollection] = [],
        progressData: ProgressData = ProgressData(),
        trackerState: TrackerState = TrackerState(),
        catalogs: [Catalog] = [],
        services: [BackupService] = []
    ) {
        self.version = version
        self.createdDate = createdDate
        self.accentColor = accentColor
        self.tmdbLanguage = tmdbLanguage
        self.selectedAppearance = selectedAppearance
        self.enableSubtitlesByDefault = enableSubtitlesByDefault
        self.defaultSubtitleLanguage = defaultSubtitleLanguage

        self.preferredAnimeAudioLanguage = preferredAnimeAudioLanguage
        self.playerChoice = playerChoice
        self.showScheduleTab = showScheduleTab
        self.showLocalScheduleTime = showLocalScheduleTime
        self.collections = collections
        self.progressData = progressData
        self.trackerState = trackerState
        self.catalogs = catalogs
        self.services = services
    }

}

// Codable wrapper for Service
struct BackupService: Codable {
    let id: UUID
    let url: String
    let jsonMetadata: String
    let jsScript: String
    let isActive: Bool
    let sortIndex: Int64
}

// Codable wrapper for LibraryCollection
struct BackupCollection: Codable {
    let id: UUID
    let name: String
    let items: [LibraryItem]
    let description: String?
    
    init(from collection: LibraryCollection) {
        self.id = collection.id
        self.name = collection.name
        self.items = collection.items
        self.description = collection.description
    }
    
    func toLibraryCollection() -> LibraryCollection {
        return LibraryCollection(id: id, name: name, items: items, description: description)
    }
}

// MARK: - Backup Manager

class BackupManager {
    static let shared = BackupManager()
    
    private let fileManager = FileManager.default
    private let dateFormatter = ISO8601DateFormatter()
    
    // MARK: - Export Backup
    
    /// Creates a backup file and returns the URL
    func createBackup() -> URL? {
        let backupData = gatherBackupData()
        
        do {
            let encoder = JSONEncoder()
            encoder.dateEncodingStrategy = .iso8601
            encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
            
            let jsonData = try encoder.encode(backupData)
            
            // Create filename with timestamp
            let timestamp = Date()
            let formatter = DateFormatter()
            formatter.dateFormat = "yyyy-MM-dd_HH-mm-ss"
            let filename = "Luna_Backup_\(formatter.string(from: timestamp)).json"
            
            // Use Documents directory instead of temporary
            let documentsDir = fileManager.urls(for: .documentDirectory, in: .userDomainMask)[0]
            let backupURL = documentsDir.appendingPathComponent(filename)
            
            try jsonData.write(to: backupURL, options: .atomic)
            Logger.shared.log("Backup created at: \(backupURL.path)", type: "Info")
            
            return backupURL
        } catch {
            Logger.shared.log("Failed to create backup: \(error.localizedDescription)", type: "Error")
            return nil
        }
    }
    
    /// Gathers all user data for backup
    private func gatherBackupData() -> BackupData {
        let userDefaults = UserDefaults.standard
        
        // Get accent color
        var accentColorData: Data?
        if let colorData = userDefaults.data(forKey: "accentColor") {
            accentColorData = colorData
        }
        
        // Get settings
        let selectedAppearance = userDefaults.string(forKey: "selectedAppearance") ?? "system"
        let enableSubtitlesByDefault = userDefaults.bool(forKey: "enableSubtitlesByDefault")
        let defaultSubtitleLanguage = userDefaults.string(forKey: "defaultSubtitleLanguage") ?? "eng"

        let preferredAnimeAudioLanguage = userDefaults.string(forKey: "preferredAnimeAudioLanguage") ?? "jpn"
        let playerChoice = userDefaults.string(forKey: "playerChoice") ?? "mpv"
        let tmdbLanguage = userDefaults.string(forKey: "tmdbLanguage") ?? "en-US"
        let showScheduleTab = userDefaults.bool(forKey: "showScheduleTab")
        let showLocalScheduleTime = userDefaults.bool(forKey: "showLocalScheduleTime")
        
        // Get library collections
        let libraryManager = LibraryManager.shared
        let backupCollections = libraryManager.collections.map { BackupCollection(from: $0) }
        
        // Get progress data - create a snapshot from the published lists
        let progressManager = ProgressManager.shared
        var progressData = ProgressData()
        progressData.movieProgress = progressManager.movieProgressList
        progressData.episodeProgress = progressManager.episodeProgressList
        
        // Get tracker state
        let trackerManager = TrackerManager.shared
        let trackerState = trackerManager.trackerState
        
        // Get catalogs
        let catalogManager = CatalogManager.shared
        let catalogs = catalogManager.catalogs

        // Get services
        let services = ServiceStore.shared.getServices().map { service -> BackupService in
            let metadataData = (try? JSONEncoder().encode(service.metadata)) ?? Data()
            let metadataString = String(data: metadataData, encoding: .utf8) ?? "{}"
            return BackupService(id: service.id, url: service.url, jsonMetadata: metadataString, jsScript: service.jsScript, isActive: service.isActive, sortIndex: service.sortIndex)
        }
        
        let backup = BackupData(
            createdDate: Date(),
            accentColor: accentColorData,
            tmdbLanguage: tmdbLanguage,
            selectedAppearance: selectedAppearance,
            enableSubtitlesByDefault: enableSubtitlesByDefault,
            defaultSubtitleLanguage: defaultSubtitleLanguage,

            preferredAnimeAudioLanguage: preferredAnimeAudioLanguage,
            playerChoice: playerChoice,
            showScheduleTab: showScheduleTab,
            showLocalScheduleTime: showLocalScheduleTime,
            collections: backupCollections,
            progressData: progressData,
            trackerState: trackerState,
            catalogs: catalogs,
            services: services
        )
        
        return backup
    }
    
    // MARK: - Import Backup
    
    /// Restores data from a backup file
    func restoreBackup(from url: URL) -> Bool {
        do {
            let jsonData = try Data(contentsOf: url)
            let decoder = JSONDecoder()
            decoder.dateDecodingStrategy = .iso8601
            
            // Try to decode the backup data
            // If it fails completely, try manual parsing to extract what we can
            let backupData: BackupData
            
            do {
                backupData = try decoder.decode(BackupData.self, from: jsonData)
                Logger.shared.log("Backup decoded successfully", type: "Info")
            } catch {
                Logger.shared.log("Standard decode failed, attempting lenient restore: \(error.localizedDescription)", type: "Info")
                
                // Try to parse as much as we can manually
                guard let backupData = tryLenientDecode(from: jsonData) else {
                    Logger.shared.log("Lenient decode also failed", type: "Error")
                    return false
                }
                
                Logger.shared.log("Lenient decode succeeded with partial data", type: "Info")
                return applyBackupData(backupData)
            }
            
            return applyBackupData(backupData)
        } catch {
            Logger.shared.log("Failed to restore backup: \(error.localizedDescription)", type: "Error")
            return false
        }
    }
    
    /// Attempts to decode backup data leniently, accepting whatever fields are valid
    private func tryLenientDecode(from jsonData: Data) -> BackupData? {
        guard let json = try? JSONSerialization.jsonObject(with: jsonData) as? [String: Any] else {
            return nil
        }
        
        // Parse createdDate - required field
        let createdDate: Date
        if let dateString = json["createdDate"] as? String {
            let formatter = ISO8601DateFormatter()
            createdDate = formatter.date(from: dateString) ?? Date()
        } else {
            createdDate = Date()
        }
        
        // Extract optional fields with defaults
        let version = json["version"] as? String ?? "1.0"
        let accentColor = json["accentColor"] as? Data
        let tmdbLanguage = json["tmdbLanguage"] as? String ?? "en-US"
        let selectedAppearance = json["selectedAppearance"] as? String ?? "system"
        let enableSubtitlesByDefault = json["enableSubtitlesByDefault"] as? Bool ?? false
        let defaultSubtitleLanguage = json["defaultSubtitleLanguage"] as? String ?? "eng"
        let preferredAnimeAudioLanguage = json["preferredAnimeAudioLanguage"] as? String ?? "jpn"
        let playerChoice = json["playerChoice"] as? String ?? "mpv"
        let showScheduleTab = json["showScheduleTab"] as? Bool ?? true
        let showLocalScheduleTime = json["showLocalScheduleTime"] as? Bool ?? true
        
        // Try to decode complex objects individually
        var collections: [BackupCollection] = []
        if let collectionsData = json["collections"] as? [[String: Any]] {
            for collectionDict in collectionsData {
                if let collectionJSON = try? JSONSerialization.data(withJSONObject: collectionDict),
                   let collection = try? JSONDecoder().decode(BackupCollection.self, from: collectionJSON) {
                    collections.append(collection)
                }
            }
        }
        
        var progressData = ProgressData()
        if let progressDict = json["progressData"] as? [String: Any],
           let progressJSON = try? JSONSerialization.data(withJSONObject: progressDict),
           let decoded = try? JSONDecoder().decode(ProgressData.self, from: progressJSON) {
            progressData = decoded
        }
        
        var trackerState = TrackerState()
        if let trackerDict = json["trackerState"] as? [String: Any],
           let trackerJSON = try? JSONSerialization.data(withJSONObject: trackerDict),
           let decoded = try? JSONDecoder().decode(TrackerState.self, from: trackerJSON) {
            trackerState = decoded
        }
        
        var catalogs: [Catalog] = []
        if let catalogsData = json["catalogs"] as? [[String: Any]] {
            for catalogDict in catalogsData {
                if let catalogJSON = try? JSONSerialization.data(withJSONObject: catalogDict),
                   let catalog = try? JSONDecoder().decode(Catalog.self, from: catalogJSON) {
                    catalogs.append(catalog)
                }
            }
        }
        
        var services: [BackupService] = []
        if let servicesData = json["services"] as? [[String: Any]] {
            for serviceDict in servicesData {
                if let serviceJSON = try? JSONSerialization.data(withJSONObject: serviceDict),
                   let service = try? JSONDecoder().decode(BackupService.self, from: serviceJSON) {
                    services.append(service)
                }
            }
        }
        
        return BackupData(
            version: version,
            createdDate: createdDate,
            accentColor: accentColor,
            tmdbLanguage: tmdbLanguage,
            selectedAppearance: selectedAppearance,
            enableSubtitlesByDefault: enableSubtitlesByDefault,
            defaultSubtitleLanguage: defaultSubtitleLanguage,
            preferredAnimeAudioLanguage: preferredAnimeAudioLanguage,
            playerChoice: playerChoice,
            showScheduleTab: showScheduleTab,
            showLocalScheduleTime: showLocalScheduleTime,
            collections: collections,
            progressData: progressData,
            trackerState: trackerState,
            catalogs: catalogs,
            services: services
        )
    }
    
    /// Applies backup data to all managers and UserDefaults
    private func applyBackupData(_ backup: BackupData) -> Bool {
        let userDefaults = UserDefaults.standard
        
        // Restore settings
        if let accentColorData = backup.accentColor {
            userDefaults.set(accentColorData, forKey: "accentColor")
        }
        userDefaults.set(backup.tmdbLanguage, forKey: "tmdbLanguage")
        userDefaults.set(backup.selectedAppearance, forKey: "selectedAppearance")
        userDefaults.set(backup.enableSubtitlesByDefault, forKey: "enableSubtitlesByDefault")
        userDefaults.set(backup.defaultSubtitleLanguage, forKey: "defaultSubtitleLanguage")

        userDefaults.set(backup.preferredAnimeAudioLanguage, forKey: "preferredAnimeAudioLanguage")
        userDefaults.set(backup.playerChoice, forKey: "playerChoice")
        userDefaults.set(backup.showScheduleTab, forKey: "showScheduleTab")
        userDefaults.set(backup.showLocalScheduleTime, forKey: "showLocalScheduleTime")
        
        // Reload Settings singleton to pick up changes
        let settings = Settings.shared
        DispatchQueue.main.async {
            settings.objectWillChange.send()
        }
        
        // Restore collections
        let libraryManager = LibraryManager.shared
        libraryManager.collections = backup.collections.map { $0.toLibraryCollection() }
        // Collections are auto-saved in LibraryManager
        
        // Restore progress data - individual updates will trigger saves
        let progressManager = ProgressManager.shared
        
        // Update all movie progress
        for movieEntry in backup.progressData.movieProgress {
            progressManager.updateMovieProgress(
                movieId: movieEntry.id,
                title: movieEntry.title,
                currentTime: movieEntry.currentTime,
                totalDuration: movieEntry.totalDuration
            )
            if movieEntry.isWatched {
                progressManager.markMovieAsWatched(movieId: movieEntry.id, title: movieEntry.title)
            }
        }
        
        // Update all episode progress
        for episodeEntry in backup.progressData.episodeProgress {
            progressManager.updateEpisodeProgress(
                showId: episodeEntry.showId,
                seasonNumber: episodeEntry.seasonNumber,
                episodeNumber: episodeEntry.episodeNumber,
                currentTime: episodeEntry.currentTime,
                totalDuration: episodeEntry.totalDuration
            )
            if episodeEntry.isWatched {
                progressManager.markEpisodeAsWatched(
                    showId: episodeEntry.showId,
                    seasonNumber: episodeEntry.seasonNumber,
                    episodeNumber: episodeEntry.episodeNumber
                )
            }
        }
        
        // Restore tracker state
        let trackerManager = TrackerManager.shared
        // Update tracker state properties from backup
        DispatchQueue.main.async {
            trackerManager.trackerState = backup.trackerState
            trackerManager.saveTrackerState()
        }
        
        // Restore catalogs
        let catalogManager = CatalogManager.shared
        catalogManager.catalogs = backup.catalogs
        catalogManager.saveCatalogs()

        // Restore services (clear existing, then insert)
        let serviceStore = ServiceStore.shared
        let existingServices = serviceStore.getServices()
        existingServices.forEach { serviceStore.remove($0) }
        for svc in backup.services {
            serviceStore.storeService(id: svc.id, url: svc.url, jsonMetadata: svc.jsonMetadata, jsScript: svc.jsScript, isActive: svc.isActive)
        }
        
        Logger.shared.log("Backup restored successfully", type: "Info")
        return true
    }
}
