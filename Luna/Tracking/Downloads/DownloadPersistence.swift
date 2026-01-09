//
//  DownloadPersistence.swift
//  Luna
//
//  Created by Soupy-dev on 1/8/26.
//

import Foundation

private var downloadsDirectory: URL {
    FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first!
        .appendingPathComponent("LunaDownloads")
}

private let jsonFileName = "downloads.json"

private struct DiskStore: Codable {
    var assets: [DownloadedAsset] = []
}

enum DownloadPersistence {
    static func load() -> [DownloadedAsset] {
        return readStore().assets
    }
    
    static func save(_ assets: [DownloadedAsset]) {
        writeStore(DiskStore(assets: assets))
    }
    
    static func upsert(_ asset: DownloadedAsset) {
        var assets = load()
        assets.removeAll { $0.id == asset.id }
        assets.append(asset)
        save(assets)
    }
    
    static func delete(id: UUID) {
        var assets = load()
        assets.removeAll { $0.id == id }
        save(assets)
    }
    
    static func orphanedFiles() -> [URL] {
        let fileManager = FileManager.default
        let downloadsDir = downloadsDirectory
        let jsonFile = downloadsDir.appendingPathComponent(jsonFileName)
        let persistedAssets = load()
        let referencedPaths = Set(
            persistedAssets.compactMap { asset in
                var paths: [String] = [asset.localURL.lastPathComponent]
                if let subtitlePath = asset.localSubtitleURL?.lastPathComponent {
                    paths.append(subtitlePath)
                }
                return paths
            }.flatMap { $0 }
        )
        
        var orphaned: [URL] = []
        do {
            let files = try fileManager.contentsOfDirectory(
                at: downloadsDir,
                includingPropertiesForKeys: nil,
                options: .skipsHiddenFiles
            )
            for file in files {
                let name = file.lastPathComponent
                if name == jsonFileName { continue }
                if !referencedPaths.contains(name) {
                    orphaned.append(file)
                }
            }
        } catch {}
        return orphaned
    }
    
    private static func readStore() -> DiskStore {
        let url = downloadsDirectory.appendingPathComponent(jsonFileName)
        guard FileManager.default.fileExists(atPath: url.path),
              let data = try? Data(contentsOf: url),
              let decoded = try? JSONDecoder().decode(DiskStore.self, from: data)
        else { return DiskStore() }
        return decoded
    }
    
    private static func writeStore(_ store: DiskStore) {
        try? FileManager.default.createDirectory(
            at: downloadsDirectory,
            withIntermediateDirectories: true
        )
        let url = downloadsDirectory.appendingPathComponent(jsonFileName)
        guard let data = try? JSONEncoder().encode(store) else { return }
        try? data.write(to: url)
    }
}
