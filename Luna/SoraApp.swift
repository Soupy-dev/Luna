//
//  SoraApp.swift
//  Sora
//
//  Created by Francesco on 12/08/25.
//

import SwiftUI
import Kingfisher

class CacheManager {
    static let shared = CacheManager()
    
    func checkAndAutoClearIfNeeded() {
        let defaults = UserDefaults.standard
        guard defaults.bool(forKey: "autoClearCacheEnabled") else { return }
        
        let thresholdMB = defaults.integer(forKey: "autoClearCacheThresholdMB")
        let thresholdBytes = Int64(thresholdMB) * 1024 * 1024
        
        if let cacheSize = getCacheSize(), cacheSize > thresholdBytes {
            clearCache()
        }
    }
    
    private func getCacheSize() -> Int64? {
        let fileManager = FileManager.default
        guard let cacheURL = fileManager.urls(for: .cachesDirectory, in: .userDomainMask).first else { return nil }
        
        var totalSize: Int64 = 0
        let resourceKeys = Set<URLResourceKey>([.fileSizeKey, .isDirectoryKey])
        
        if let enumerator = fileManager.enumerator(at: cacheURL, includingPropertiesForKeys: Array(resourceKeys)) {
            for case let file as URL in enumerator {
                if let resourceValues = try? file.resourceValues(forKeys: resourceKeys),
                   let fileSize = resourceValues.fileSize {
                    totalSize += Int64(fileSize)
                }
            }
        }
        
        return totalSize
    }
    
    private func clearCache() {
        let fileManager = FileManager.default
        guard let cacheURL = fileManager.urls(for: .cachesDirectory, in: .userDomainMask).first else { return }
        
        do {
            let files = try fileManager.contentsOfDirectory(at: cacheURL, includingPropertiesForKeys: nil)
            for file in files {
                try fileManager.removeItem(at: file)
            }
            Logger.shared.log("Cache cleared successfully", type: "Cache")
        } catch {
            Logger.shared.log("Failed to clear cache: \(error)", type: "Error")
        }
    }
}

@main
struct SoraApp: App {
    @StateObject private var settings = Settings()
    @StateObject private var moduleManager = ModuleManager.shared
    @StateObject private var favouriteManager = FavouriteManager.shared

#if !os(tvOS)
    @AppStorage("showKanzen") private var showKanzen: Bool = false
    let kanzen = KanzenEngine();
#endif

    init() {
        // Check and auto-clear cache on app startup if threshold exceeded
        DispatchQueue.global(qos: .background).async {
            CacheManager.shared.checkAndAutoClearIfNeeded()
        }
    }

    var body: some Scene {
        WindowGroup {
#if os(tvOS)
            ContentView()
#else
            if showKanzen {
                    KanzenMenu().environmentObject(settings).environmentObject(moduleManager).environmentObject(favouriteManager)
                    .environment(\.managedObjectContext, favouriteManager.container.viewContext)
                    .accentColor(settings.accentColor)
            }
            else{
                ContentView()
            }
#endif
        }
    }
}
