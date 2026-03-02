//
//  MainMenu.swift
//  Luna
//
//  Created by Dawud Osman on 17/11/2025.
//

import SwiftUI

#if !os(tvOS)
struct KanzenMenu: View {
    let kanzen = KanzenEngine()
    @Environment(\.scenePhase) private var scenePhase
    @EnvironmentObject var moduleManager: ModuleManager

    var body: some View {
        TabView {
            KanzenHomeView()
                .tabItem {
                    Label("Home", systemImage: "house")
                }

            KanzenLibraryView()
                .tabItem {
                    Label("Library", systemImage: "books.vertical")
                }

            KanzenGlobalSearchView()
                .tabItem {
                    Label("Search", systemImage: "magnifyingglass")
                }

            BrowseView()
                .tabItem {
                    Label("Browse", systemImage: "list.bullet")
                }

            KanzenSettingsView()
                .tabItem {
                    Label("Settings", systemImage: "gear")
                }
        }
        .task {
            await moduleManager.autoUpdateModulesIfNeeded()
        }
        .onChange(of: scenePhase) { newPhase in
            if newPhase == .active {
                Task {
                    await moduleManager.autoUpdateModulesIfNeeded()
                }
            }
        }
    }
}
#endif
