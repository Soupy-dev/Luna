//
//  StremioModels.swift
//  Luna
//
//  Created by Soupy on 2026.
//

import Foundation
import CoreData

// MARK: - Stremio Manifest

struct StremioManifest: Codable {
    let id: String
    let name: String
    let description: String?
    let version: String?
    let logo: String?
    let types: [String]?
    let resources: [StremioResource]?
    let idPrefixes: [String]?
    let behaviorHints: StremioManifestBehaviorHints?

    enum CodingKeys: String, CodingKey {
        case id, name, description, version, logo, types, resources, idPrefixes, behaviorHints
    }

    /// Whether this addon supports a given ID prefix (e.g. "tt", "tmdb:", "kitsu:")
    func supportsPrefix(_ prefix: String) -> Bool {
        guard let prefixes = idPrefixes, !prefixes.isEmpty else { return true }
        return prefixes.contains(where: { prefix.hasPrefix($0) })
    }

    /// Whether this addon supports the "stream" resource
    var supportsStreams: Bool {
        guard let resources = resources else { return false }
        return resources.contains { $0.isStream }
    }
}

struct StremioManifestBehaviorHints: Codable {
    let configurable: Bool?
    let configurationRequired: Bool?
}

// MARK: - Resource (can be a string or an object)

enum StremioResource: Codable {
    case simple(String)
    case detailed(StremioResourceDetail)

    var isStream: Bool {
        switch self {
        case .simple(let name): return name == "stream"
        case .detailed(let detail): return detail.name == "stream"
        }
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.singleValueContainer()
        if let string = try? container.decode(String.self) {
            self = .simple(string)
        } else {
            let detail = try container.decode(StremioResourceDetail.self)
            self = .detailed(detail)
        }
    }

    func encode(to encoder: Encoder) throws {
        var container = encoder.singleValueContainer()
        switch self {
        case .simple(let name):
            try container.encode(name)
        case .detailed(let detail):
            try container.encode(detail)
        }
    }
}

struct StremioResourceDetail: Codable {
    let name: String
    let types: [String]?
    let idPrefixes: [String]?
}

// MARK: - Stream Response

struct StremioStreamResponse: Codable {
    let streams: [StremioStream]?
}

struct StremioStream: Codable, Identifiable {
    let id: String

    let url: String?
    let infoHash: String?
    let title: String?
    let name: String?
    let description: String?
    let behaviorHints: StremioStreamBehaviorHints?
    let subtitles: [StremioSubtitle]?

    enum CodingKeys: String, CodingKey {
        case url, infoHash, title, name, description, behaviorHints, subtitles
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        url = try container.decodeIfPresent(String.self, forKey: .url)
        infoHash = try container.decodeIfPresent(String.self, forKey: .infoHash)
        title = try container.decodeIfPresent(String.self, forKey: .title)
        name = try container.decodeIfPresent(String.self, forKey: .name)
        description = try container.decodeIfPresent(String.self, forKey: .description)
        behaviorHints = try container.decodeIfPresent(StremioStreamBehaviorHints.self, forKey: .behaviorHints)
        subtitles = try container.decodeIfPresent([StremioSubtitle].self, forKey: .subtitles)
        id = url ?? infoHash ?? UUID().uuidString
    }

    /// Whether this stream is a direct HTTP(S) link (safe, no torrent)
    var isDirectHTTP: Bool {
        guard let url = url, !url.isEmpty else { return false }
        let lower = url.lowercased()
        return lower.hasPrefix("http://") || lower.hasPrefix("https://")
    }

    /// Display name for the stream (prefers name, falls back to title)
    var displayName: String {
        if let name = name, !name.isEmpty { return name }
        if let title = title, !title.isEmpty { return title }
        return "Stream"
    }

    /// Extracts proxy headers from behaviorHints if available
    var proxyHeaders: [String: String]? {
        behaviorHints?.proxyHeaders?.request
    }
}

struct StremioStreamBehaviorHints: Codable {
    let notWebReady: Bool?
    let bingeGroup: String?
    let proxyHeaders: StremioProxyHeaders?
    let filename: String?
}

struct StremioProxyHeaders: Codable {
    let request: [String: String]?
}

struct StremioSubtitle: Codable {
    let id: String?
    let url: String?
    let lang: String?
}

// MARK: - Stremio Addon Model (persisted)

struct StremioAddon: Identifiable, Hashable {
    let id: UUID
    let configuredURL: String
    let manifest: StremioManifest
    let isActive: Bool
    let sortIndex: Int64

    static func == (lhs: StremioAddon, rhs: StremioAddon) -> Bool {
        lhs.id == rhs.id
    }

    func hash(into hasher: inout Hasher) {
        hasher.combine(id)
    }
}

// MARK: - StremioAddonEntity (CoreData)

@objc(StremioAddonEntity)
public class StremioAddonEntity: NSManagedObject { }

extension StremioAddonEntity {
    @nonobjc public class func fetchRequest() -> NSFetchRequest<StremioAddonEntity> {
        return NSFetchRequest<StremioAddonEntity>(entityName: "StremioAddonEntity")
    }

    @NSManaged public var id: UUID?
    @NSManaged public var configuredURL: String?
    @NSManaged public var manifestJSON: String?
    @NSManaged public var isActive: Bool
    @NSManaged public var sortIndex: Int64

    override public func awakeFromInsert() {
        super.awakeFromInsert()
        if id == nil {
            let temp = UUID()
            id = temp
            Logger.shared.log("Added empty StremioAddonEntity: \(temp)", type: "Stremio")
        }
    }
}

extension StremioAddonEntity: Identifiable { }

extension StremioAddonEntity {
    var asModel: StremioAddon? {
        guard
            let id = self.id,
            let configuredURL = self.configuredURL,
            let manifestJSON = self.manifestJSON,
            let data = manifestJSON.data(using: .utf8)
        else {
            return nil
        }

        do {
            let manifest = try JSONDecoder().decode(StremioManifest.self, from: data)
            return StremioAddon(
                id: id,
                configuredURL: configuredURL,
                manifest: manifest,
                isActive: isActive,
                sortIndex: sortIndex
            )
        } catch {
            Logger.shared.log("Failed to decode StremioManifest for \(id.uuidString): \(error.localizedDescription)", type: "Stremio")
            return nil
        }
    }
}
