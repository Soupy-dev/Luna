//
//  TrackerModels.swift
//  Luna
//
//  Created by Soupy-dev
//

import Foundation

enum TrackerService: String, Codable, CaseIterable {
    case anilist
    case trakt

    var displayName: String {
        switch self {
        case .anilist:
            return "AniList"
        case .trakt:
            return "Trakt"
        }
    }

    var baseURL: String {
        switch self {
        case .anilist:
            return "https://anilist.co"
        case .trakt:
            return "https://trakt.tv"
        }
    }
}

struct TrackerAccount: Codable {
    let service: TrackerService
    let username: String
    var accessToken: String
    var refreshToken: String?
    var expiresAt: Date?
    let userId: String
    var isConnected: Bool = true

    mutating func updateTokens(access: String, refresh: String?, expiresAt: Date?) {
        self.accessToken = access
        self.refreshToken = refresh
        self.expiresAt = expiresAt
    }
}

struct TrackerState: Codable {
    var accounts: [TrackerAccount] = []
    var syncEnabled: Bool = true
    var lastSyncDate: Date?

    mutating func addOrUpdateAccount(_ account: TrackerAccount) {
        if let index = accounts.firstIndex(where: { $0.service == account.service }) {
            accounts[index] = account
        } else {
            accounts.append(account)
        }
    }

    func getAccount(for service: TrackerService) -> TrackerAccount? {
        accounts.first { $0.service == service && $0.isConnected }
    }

    mutating func disconnectAccount(for service: TrackerService) {
        if let index = accounts.firstIndex(where: { $0.service == service }) {
            accounts[index].isConnected = false
        }
    }
}

// AniList Models
struct AniListAuthResponse: Codable {
    let accessToken: String
    let tokenType: String
    let expiresIn: Int

    enum CodingKeys: String, CodingKey {
        case accessToken = "access_token"
        case tokenType = "token_type"
        case expiresIn = "expires_in"
    }
}

struct AniListUser: Codable {
    let id: Int
    let name: String
}

struct AniListMediaListEntry: Codable {
    let id: Int
    let mediaId: Int
    let status: String  // CURRENT, PLANNING, COMPLETED, DROPPED, PAUSED, REPEATING
    let progress: Int
    let progressVolumes: Int?
    let score: Int?
    let startedAt: AniListDate?
    let completedAt: AniListDate?

    enum CodingKeys: String, CodingKey {
        case id, status, progress, score
        case mediaId = "mediaId"
        case progressVolumes = "progressVolumes"
        case startedAt, completedAt
    }
}

struct AniListDate: Codable {
    let year: Int?
    let month: Int?
    let day: Int?
}

struct AniListMediaEntry: Codable {
    let id: Int
    let title: AniListTitle
    let episodes: Int?
    let status: String?
    let seasonYear: Int?
    let season: String?
    let format: String?
    let coverImage: AniListCoverImage?
    let nextAiringEpisode: AniListAiringSchedule?
    let relations: AniListRelations?
    let type: String?

    struct AniListTitle: Codable {
        let romaji: String?
        let english: String?
        let native: String?
    }
}

struct AniListCoverImage: Codable {
    let large: String?
    let medium: String?
}

struct AniListRelations: Codable {
    let edges: [AniListRelationEdge]
}

struct AniListRelationEdge: Codable {
    let relationType: String
    let node: AniListRelatedAnime
}

struct AniListRelatedAnime: Codable {
    let id: Int
    let title: AniListTitle
    
    struct AniListTitle: Codable {
        let romaji: String?
        let english: String?
        let native: String?
    }
}

struct AniListAiringSchedule: Codable {
    let episode: Int
    let airingAt: Int
}

// Trakt Models
struct TraktAuthResponse: Codable {
    let accessToken: String
    let tokenType: String
    let expiresIn: Int
    let refreshToken: String

    enum CodingKeys: String, CodingKey {
        case accessToken = "access_token"
        case tokenType = "token_type"
        case expiresIn = "expires_in"
        case refreshToken = "refresh_token"
    }
}

struct TraktUser: Codable {
    let username: String
    let ids: TraktIds
}

struct TraktIds: Codable {
    let trakt: Int?
    let slug: String
    let imdb: String?
    let tmdb: Int?
}

struct TraktSyncProgress: Codable {
    let progress: Double
    let lastUpdated: String
}
