//
//  TrackerManager.swift
//  Luna
//
//  Created by Soupy-dev
//

import Foundation
import Combine
#if !os(tvOS)
import AuthenticationServices
#endif
import UIKit

final class TrackerManager: NSObject, ObservableObject {
    static let shared = TrackerManager()
    
    @Published var trackerState: TrackerState = TrackerState()
    @Published var isAuthenticating = false
    @Published var authError: String?
    
    private let trackerStateURL: URL
    private var cancellables = Set<AnyCancellable>()
    #if !os(tvOS)
    private var webAuthSession: ASWebAuthenticationSession?
    #endif
    
    // OAuth config
    private let anilistClientId = "33908"
    private let anilistRedirectUri = "luna://anilist-callback"
    
    private let traktClientId = "e92207aaef82a1b0b42d5901efa4756b6c417911b7b031b986d37773c234ccab"
    private let traktClientSecret = "03c457ea5986e900f140243c69d616313533cedcc776e42e07a6ddd3ab699035"
    private let traktRedirectUri = "luna://trakt-callback"
    
    override private init() {
        let documentsDirectory = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)[0]
        self.trackerStateURL = documentsDirectory.appendingPathComponent("TrackerState.json")
        super.init()
        loadTrackerState()
    }
    
    // MARK: - State Management
    
    private func loadTrackerState() {
        if let data = try? Data(contentsOf: trackerStateURL),
           let state = try? JSONDecoder().decode(TrackerState.self, from: data) {
            self.trackerState = state
        }
    }
    
    private func saveTrackerState() {
        DispatchQueue.global(qos: .background).async {
            if let encoded = try? JSONEncoder().encode(self.trackerState) {
                try? encoded.write(to: self.trackerStateURL)
            }
        }
    }
    
    // MARK: - AniList Authentication
    
    func getAniListAuthURL() -> URL? {
        var components = URLComponents(string: "https://anilist.co/api/v2/oauth/authorize")
        components?.queryItems = [
            URLQueryItem(name: "client_id", value: anilistClientId),
            URLQueryItem(name: "redirect_uri", value: anilistRedirectUri),
            URLQueryItem(name: "response_type", value: "code"),
            URLQueryItem(name: "scope", value: "public")
        ]
        return components?.url
    }

    func startAniListAuth() {
        guard let url = getAniListAuthURL() else { return }
        authError = nil
        isAuthenticating = true

        #if os(tvOS)
        UIApplication.shared.open(url) { _ in }
        DispatchQueue.main.async {
            self.isAuthenticating = false
        }
        #else
        let session = ASWebAuthenticationSession(url: url, callbackURLScheme: "luna") { [weak self] callbackURL, error in
            guard let self = self else { return }

            if let error = error {
                DispatchQueue.main.async {
                    self.authError = error.localizedDescription
                    self.isAuthenticating = false
                }
                return
            }

            guard let callbackURL = callbackURL,
                  let components = URLComponents(url: callbackURL, resolvingAgainstBaseURL: true),
                  let code = components.queryItems?.first(where: { $0.name == "code" })?.value else {
                DispatchQueue.main.async {
                    self.authError = "Invalid AniList callback"
                    self.isAuthenticating = false
                }
                return
            }

            self.handleAniListCallback(code: code)
        }

        session.prefersEphemeralWebBrowserSession = true
        session.presentationContextProvider = self
        session.start()
        webAuthSession = session
        #endif
    }
    
    func handleAniListCallback(code: String) {
        isAuthenticating = true
        Task {
            do {
                let token = try await exchangeAniListCode(code)
                let user = try await fetchAniListUser(token: token.accessToken)
                let account = TrackerAccount(
                    service: .anilist,
                    username: user.name,
                    accessToken: token.accessToken,
                    refreshToken: nil,
                    expiresAt: Date().addingTimeInterval(TimeInterval(token.expiresIn)),
                    userId: String(user.id)
                )
                await MainActor.run {
                    self.trackerState.addOrUpdateAccount(account)
                    self.saveTrackerState()
                    self.isAuthenticating = false
                }
            } catch {
                await MainActor.run {
                    self.authError = error.localizedDescription
                    self.isAuthenticating = false
                }
            }
        }
    }
    
    private func exchangeAniListCode(_ code: String) async throws -> AniListAuthResponse {
        let url = URL(string: "https://anilist.co/api/v2/oauth/token")!
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        
        let body: [String: Any] = [
            "grant_type": "authorization_code",
            "client_id": anilistClientId,
            "client_secret": "", // AniList doesn't require client secret for native apps
            "redirect_uri": anilistRedirectUri,
            "code": code
        ]
        request.httpBody = try JSONSerialization.data(withJSONObject: body)
        
        let (data, response) = try await URLSession.shared.data(for: request)
        guard (response as? HTTPURLResponse)?.statusCode == 200 else {
            throw NSError(domain: "AniListAuth", code: -1, userInfo: [NSLocalizedDescriptionKey: "Failed to authenticate with AniList"])
        }
        
        return try JSONDecoder().decode(AniListAuthResponse.self, from: data)
    }
    
    private func fetchAniListUser(token: String) async throws -> AniListUser {
        let query = """
        query {
            Viewer {
                id
                name
            }
        }
        """
        
        let url = URL(string: "https://graphql.anilist.co")!
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        
        let body: [String: Any] = ["query": query]
        request.httpBody = try JSONSerialization.data(withJSONObject: body)
        
        let (data, _) = try await URLSession.shared.data(for: request)
        
        struct Response: Codable {
            let data: DataWrapper
            struct DataWrapper: Codable {
                let Viewer: AniListUser
            }
        }
        
        let response = try JSONDecoder().decode(Response.self, from: data)
        return response.data.Viewer
    }
    
    // MARK: - Trakt Authentication
    
    func getTraktAuthURL() -> URL? {
        var components = URLComponents(string: "https://trakt.tv/oauth/authorize")
        components?.queryItems = [
            URLQueryItem(name: "client_id", value: traktClientId),
            URLQueryItem(name: "redirect_uri", value: traktRedirectUri),
            URLQueryItem(name: "response_type", value: "code")
        ]
        return components?.url
    }

    func startTraktAuth() {
        guard let url = getTraktAuthURL() else { return }
        authError = nil
        isAuthenticating = true

        #if os(tvOS)
        UIApplication.shared.open(url) { _ in }
        DispatchQueue.main.async {
            self.isAuthenticating = false
        }
        #else
        let session = ASWebAuthenticationSession(url: url, callbackURLScheme: "luna") { [weak self] callbackURL, error in
            guard let self = self else { return }

            if let error = error {
                DispatchQueue.main.async {
                    self.authError = error.localizedDescription
                    self.isAuthenticating = false
                }
                return
            }

            guard let callbackURL = callbackURL,
                  let components = URLComponents(url: callbackURL, resolvingAgainstBaseURL: true),
                  let code = components.queryItems?.first(where: { $0.name == "code" })?.value else {
                DispatchQueue.main.async {
                    self.authError = "Invalid Trakt callback"
                    self.isAuthenticating = false
                }
                return
            }

            self.handleTraktCallback(code: code)
        }

        session.prefersEphemeralWebBrowserSession = true
        session.presentationContextProvider = self
        session.start()
        webAuthSession = session
        #endif
    }
    
    func handleTraktCallback(code: String) {
        isAuthenticating = true
        Task {
            do {
                let token = try await exchangeTraktCode(code)
                let user = try await fetchTraktUser(token: token.accessToken)
                let account = TrackerAccount(
                    service: .trakt,
                    username: user.username,
                    accessToken: token.accessToken,
                    refreshToken: token.refreshToken,
                    expiresAt: Date().addingTimeInterval(TimeInterval(token.expiresIn)),
                    userId: String(user.ids.trakt)
                )
                await MainActor.run {
                    self.trackerState.addOrUpdateAccount(account)
                    self.saveTrackerState()
                    self.isAuthenticating = false
                }
            } catch {
                await MainActor.run {
                    self.authError = error.localizedDescription
                    self.isAuthenticating = false
                }
            }
        }
    }
    
    private func exchangeTraktCode(_ code: String) async throws -> TraktAuthResponse {
        let url = URL(string: "https://api.trakt.tv/oauth/token")!
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        
        let body: [String: Any] = [
            "code": code,
            "client_id": traktClientId,
            "client_secret": traktClientSecret,
            "redirect_uri": traktRedirectUri,
            "grant_type": "authorization_code"
        ]
        request.httpBody = try JSONSerialization.data(withJSONObject: body)
        
        let (data, response) = try await URLSession.shared.data(for: request)
        guard (response as? HTTPURLResponse)?.statusCode == 201 else {
            throw NSError(domain: "TraktAuth", code: -1, userInfo: [NSLocalizedDescriptionKey: "Failed to authenticate with Trakt"])
        }
        
        return try JSONDecoder().decode(TraktAuthResponse.self, from: data)
    }
    
    private func fetchTraktUser(token: String) async throws -> TraktUser {
        let url = URL(string: "https://api.trakt.tv/users/me")!
        var request = URLRequest(url: url)
        request.setValue(traktClientId, forHTTPHeaderField: "trakt-api-key")
        request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        request.setValue("2", forHTTPHeaderField: "trakt-api-version")
        
        let (data, _) = try await URLSession.shared.data(for: request)
        return try JSONDecoder().decode(TraktUser.self, from: data)
    }
    
    // MARK: - Sync Methods
    
    func syncWatchProgress(showId: Int, seasonNumber: Int, episodeNumber: Int, progress: Double, isMovie: Bool = false) {
        guard trackerState.syncEnabled else { return }
        
        Task {
            for account in trackerState.accounts where account.isConnected {
                switch account.service {
                case .anilist:
                    // Sync to AniList
                    await syncToAniList(account: account, showId: showId, seasonNumber: seasonNumber, episodeNumber: episodeNumber, progress: progress)
                case .trakt:
                    // Sync to Trakt
                    await syncToTrakt(account: account, showId: showId, seasonNumber: seasonNumber, episodeNumber: episodeNumber, progress: progress)
                }
            }
        }
    }
    
    private func syncToAniList(account: TrackerAccount, showId: Int, seasonNumber: Int, episodeNumber: Int, progress: Double) async {
        guard let anilistId = await getAniListMediaId(tmdbId: showId) else {
            Logger.shared.log("Could not find AniList ID for TMDB ID \(showId)", type: "Tracker")
            return
        }
        
        let mutation = """
        mutation {
            SaveMediaListEntry(mediaId: \(anilistId), progress: \(episodeNumber), status: CURRENT) {
                id
                progress
                status
            }
        }
        """
        
        do {
            let url = URL(string: "https://graphql.anilist.co")!
            var request = URLRequest(url: url)
            request.httpMethod = "POST"
            request.setValue("application/json", forHTTPHeaderField: "Content-Type")
            request.setValue("Bearer \(account.accessToken)", forHTTPHeaderField: "Authorization")
            
            let body: [String: Any] = ["query": mutation]
            request.httpBody = try JSONSerialization.data(withJSONObject: body)
            
            let (_, response) = try await URLSession.shared.data(for: request)
            if (response as? HTTPURLResponse)?.statusCode == 200 {
                Logger.shared.log("Synced to AniList: S\(seasonNumber)E\(episodeNumber)", type: "Tracker")
            }
        } catch {
            Logger.shared.log("Failed to sync to AniList: \(error.localizedDescription)", type: "Error")
        }
    }
    
    private func syncToTrakt(account: TrackerAccount, showId: Int, seasonNumber: Int, episodeNumber: Int, progress: Double) async {
        let payload: [String: Any] = [
            "episodes": [
                [
                    "number": episodeNumber,
                    "season": seasonNumber
                ]
            ]
        ]
        
        do {
            let url = URL(string: "https://api.trakt.tv/sync/history")!
            var request = URLRequest(url: url)
            request.httpMethod = "POST"
            request.setValue("application/json", forHTTPHeaderField: "Content-Type")
            request.setValue(traktClientId, forHTTPHeaderField: "trakt-api-key")
            request.setValue("Bearer \(account.accessToken)", forHTTPHeaderField: "Authorization")
            request.setValue("2", forHTTPHeaderField: "trakt-api-version")
            
            request.httpBody = try JSONSerialization.data(withJSONObject: payload)
            
            let (_, response) = try await URLSession.shared.data(for: request)
            if (response as? HTTPURLResponse)?.statusCode == 201 {
                Logger.shared.log("Synced to Trakt: S\(seasonNumber)E\(episodeNumber)", type: "Tracker")
            }
        } catch {
            Logger.shared.log("Failed to sync to Trakt: \(error.localizedDescription)", type: "Error")
        }
    }
    
    // MARK: - Helper Methods
    
    private func getAniListMediaId(tmdbId: Int) async -> Int? {
        let query = """
        query {
            Media(idMal: \(tmdbId), type: ANIME) {
                id
            }
        }
        """
        
        do {
            let url = URL(string: "https://graphql.anilist.co")!
            var request = URLRequest(url: url)
            request.httpMethod = "POST"
            request.setValue("application/json", forHTTPHeaderField: "Content-Type")
            
            let body: [String: Any] = ["query": query]
            request.httpBody = try JSONSerialization.data(withJSONObject: body)
            
            let (data, _) = try await URLSession.shared.data(for: request)
            
            struct Response: Codable {
                let data: DataWrapper
                struct DataWrapper: Codable {
                    let Media: MediaData?
                    struct MediaData: Codable {
                        let id: Int
                    }
                }
            }
            
            let response = try JSONDecoder().decode(Response.self, from: data)
            return response.data.Media?.id
        } catch {
            return nil
        }
    }
    
    func disconnectTracker(_ service: TrackerService) {
        trackerState.disconnectAccount(for: service)
        saveTrackerState()
    }
}

#if !os(tvOS)
extension TrackerManager: ASWebAuthenticationPresentationContextProviding {
    func presentationAnchor(for session: ASWebAuthenticationSession) -> ASPresentationAnchor {
        UIApplication.shared.connectedScenes
            .compactMap { $0 as? UIWindowScene }
            .flatMap { $0.windows }
            .first(where: { $0.isKeyWindow }) ?? ASPresentationAnchor()
    }
}
#endif
