//
//  TrackersSettingsView.swift
//  Luna
//
//  Created by Soupy-dev
//

import SwiftUI

struct TrackersSettingsView: View {
    @StateObject private var trackerManager = TrackerManager.shared
    @State private var selectedTracker: TrackerService?
    @State private var showAniListPinInput = false
    @State private var anilistTokenInput: String = ""
    @State private var showTraktPinInput = false
    @State private var traktTokenInput: String = ""
    
    var body: some View {
        NavigationView {
            ZStack {
                Color.black.ignoresSafeArea()
                
                ScrollView {
                    VStack(alignment: .leading, spacing: 16) {
                        Text("Trackers")
                            .font(.title2)
                            .fontWeight(.bold)
                            .foregroundColor(.white)
                            .padding(.horizontal)
                        
                        VStack(spacing: 12) {
                            // Sync Toggle
                            Toggle("Enable Sync", isOn: $trackerManager.trackerState.syncEnabled)
                                .foregroundColor(.white)
                                .padding()
                                .background(Color.gray.opacity(0.2))
                                .cornerRadius(12)
                            
                            // AniList Section
                            trackerRow(
                                service: .anilist,
                                isConnected: trackerManager.trackerState.getAccount(for: .anilist) != nil,
                                username: trackerManager.trackerState.getAccount(for: .anilist)?.username,
                                onConnect: { showAniListPinInput = true },
                                onDisconnect: { trackerManager.disconnectTracker(.anilist) }
                            )
                            
                            // Trakt Section
                            trackerRow(
                                service: .trakt,
                                isConnected: trackerManager.trackerState.getAccount(for: .trakt) != nil,
                                username: trackerManager.trackerState.getAccount(for: .trakt)?.username,
                                onConnect: { showTraktPinInput = true },
                                onDisconnect: { trackerManager.disconnectTracker(.trakt) }
                            )
                        }
                        .padding(.horizontal)
                        
                        if let error = trackerManager.authError {
                            VStack {
                                HStack {
                                    Image(systemName: "exclamationmark.circle")
                                        .foregroundColor(.orange)
                                    Text(error)
                                        .font(.caption)
                                        .foregroundColor(.orange)
                                }
                            }
                            .padding()
                            .background(Color.orange.opacity(0.1))
                            .cornerRadius(8)
                            .padding(.horizontal)
                        }
                        
                        Spacer()
                    }
                    .padding(.vertical)
                }
            }
            #if !os(tvOS)
            .navigationBarTitleDisplayMode(.inline)
            #endif
        }
        .alert("AniList Auth Token", isPresented: $showAniListPinInput) {
            TextField("Paste token", text: $anilistTokenInput)
            Button("Cancel", role: .cancel) {
                anilistTokenInput = ""
            }
            Button("Open Pin Page in Safari") {
                // client_id for Luna app
                if let url = URL(string: "https://anilist.co/api/v2/oauth/pin?client_id=33908") {
                    UIApplication.shared.open(url)
                }
            }
            Button("Authenticate") {
                if !anilistTokenInput.isEmpty {
                    trackerManager.handleAniListPinAuth(token: anilistTokenInput)
                    anilistTokenInput = ""
                }
            }
        } message: {
            Text("1. Tap 'Open Pin Page in Safari'\n2. Authorize the app\n3. Copy the access token shown on the page\n4. Paste it above and tap 'Authenticate'")
        }
        .alert("Trakt Auth Token", isPresented: $showTraktPinInput) {
            TextField("Paste token", text: $traktTokenInput)
            Button("Cancel", role: .cancel) {
                traktTokenInput = ""
            }
            Button("Open Pin Page in Safari") {
                // client_id for Luna app
                if let url = URL(string: "https://trakt.tv/oauth/authorize?client_id=e92207aaef82a1b0b42d5901efa4756b6c417911b7b031b986d37773c234ccab&response_type=code&redirect_uri=urn:ietf:wg:oauth:2.0:oob") {
                    UIApplication.shared.open(url)
                }
            }
            Button("Authenticate") {
                if !traktTokenInput.isEmpty {
                    trackerManager.handleTraktPinAuth(token: traktTokenInput)
                    traktTokenInput = ""
                }
            }
        } message: {
            Text("1. Tap 'Open Pin Page in Safari'\n2. Authorize the app\n3. Copy the PIN/token shown on the page\n4. Paste it above and tap 'Authenticate'")
        }
    }
    
    @ViewBuilder
    private func trackerRow(
        service: TrackerService,
        isConnected: Bool,
        username: String?,
        onConnect: @escaping () -> Void,
        onDisconnect: @escaping () -> Void
    ) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                VStack(alignment: .leading, spacing: 4) {
                    Text(service.displayName)
                        .font(.headline)
                        .foregroundColor(.white)
                    
                    if let username = username {
                        Text(username)
                            .font(.caption)
                            .foregroundColor(.secondary)
                    }
                }
                
                Spacer()
                
                if isConnected {
                    HStack(spacing: 8) {
                        Image(systemName: "checkmark.circle.fill")
                            .foregroundColor(.green)
                        
                        Button(action: onDisconnect) {
                            Text("Disconnect")
                                .font(.caption)
                                .foregroundColor(.red)
                        }
                    }
                } else {
                    Button(action: onConnect) {
                        Text("Connect")
                            .font(.caption)
                            .foregroundColor(.blue)
                            .padding(.horizontal, 12)
                            .padding(.vertical, 6)
                            .background(Color.blue.opacity(0.2))
                            .cornerRadius(6)
                    }
                }
            }
        }
        .padding()
        .background(Color.gray.opacity(0.1))
        .cornerRadius(12)
    }
}
