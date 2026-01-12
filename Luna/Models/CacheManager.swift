//
//  CacheManager.swift
//  Luna
//
//  Created by Soupy-dev on 01/11/26.
//

import Foundation

final class CacheManager {
    static let shared = CacheManager()
    
    private init() {}
    
    /// Check if auto-clear cache is enabled and clear if threshold is exceeded
    func checkAndAutoClearIfNeeded() {
        let autoClearEnabled = UserDefaults.standard.bool(forKey: "autoClearCacheEnabled")
        guard autoClearEnabled else { return }
        
        let thresholdMB = UserDefaults.standard.double(forKey: "autoClearCacheThresholdMB")
        let thresholdBytes = Int64(thresholdMB * 1_000_000)
        
        let cacheSize = calculateCacheSize()
        
        if cacheSize > thresholdBytes {
            Logger.shared.log("Cache size (\(ByteCountFormatter.string(fromByteCount: cacheSize, countStyle: .file))) exceeds auto-clear threshold (\(formatThreshold(thresholdMB))). Auto-clearing...", type: "Storage")
            clearCache()
        }
    }
    
    private func calculateCacheSize() -> Int64 {
        let cacheDir = FileManager.default.urls(for: .cachesDirectory, in: .userDomainMask)[0]
        let fileManager = FileManager.default
        let keys: [URLResourceKey] = [.isRegularFileKey, .fileSizeKey]
        var total: Int64 = 0
        
        guard let enumerator = fileManager.enumerator(at: cacheDir, includingPropertiesForKeys: keys, options: [.skipsHiddenFiles, .skipsPackageDescendants]) else {
            return 0
        }
        
        for case let fileURL as URL in enumerator {
            do {
                let resourceValues = try fileURL.resourceValues(forKeys: Set(keys))
                if resourceValues.isRegularFile == true, let fileSize = resourceValues.fileSize {
                    total += Int64(fileSize)
                }
            } catch {
                continue
            }
        }
        return total
    }
    
    private func clearCache() {
        let cacheDir = FileManager.default.urls(for: .cachesDirectory, in: .userDomainMask)[0]
        let fileManager = FileManager.default
        
        do {
            let items = try fileManager.contentsOfDirectory(at: cacheDir, includingPropertiesForKeys: nil, options: [])
            for url in items {
                try? fileManager.removeItem(at: url)
            }
            
            URLCache.shared.removeAllCachedResponses()
            
            let newSize = calculateCacheSize()
            Logger.shared.log("Auto-clear completed. New cache size: \(ByteCountFormatter.string(fromByteCount: newSize, countStyle: .file))", type: "Storage")
        } catch {
            Logger.shared.log("Failed to auto-clear cache: \(error.localizedDescription)", type: "Error")
        }
    }
    
    private func formatThreshold(_ mb: Double) -> String {
        if mb >= 1000 {
            return String(format: "%.1f GB", mb / 1000)
        }
        return String(format: "%.0f MB", mb)
    }
}
