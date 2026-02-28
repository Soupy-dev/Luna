//
//  ContentView.swift
//  Sora
//
//  Created by Francesco on 07/08/25.
//

import SwiftUI

struct ContentView: View {
    @StateObject private var accentColorManager = AccentColorManager.shared
    @ObservedObject private var downloadManager = DownloadManager.shared
    @State private var showingSearch = false
    
    var body: some View {
#if compiler(>=6.0)
        if #available(iOS 26.0, tvOS 26.0, *) {
            modernTabView
                .accentColor(accentColorManager.currentAccentColor)
        } else {
            olderTabView
        }
#else
        olderTabView
#endif
    }
    
#if compiler(>=6.0)
    @available(iOS 26.0, tvOS 26.0, *)
    private var modernTabView: some View {
        TabView {
            Tab("Home", systemImage: "house.fill") {
                HomeView()
            }
            
            Tab("Schedule", systemImage: "calendar") {
                ScheduleView()
            }
            
            Tab("Downloads", systemImage: "arrow.down.circle.fill") {
                DownloadsView()
            }
            .badge(downloadManager.activeDownloadCount > 0 ? downloadManager.activeDownloadCount : 0)
            
            Tab("Library", systemImage: "books.vertical.fill") {
                LibraryView()
            }
            
            Tab("Search", systemImage: "magnifyingglass", role: .search) {
                SearchView()
            }
            
            Tab("Settings", systemImage: "gear") {
                SettingsView()
            }
        }
#if !os(tvOS)
        .tabBarMinimizeBehavior(.never)
#endif
    }
#endif
    
    private var olderTabView: some View {
        TabView {
            HomeView()
                .tabItem {
                    Image(systemName: "house.fill")
                    Text("Home")
                }
            
            ScheduleView()
                .tabItem {
                    Image(systemName: "calendar")
                    Text("Schedule")
                }
            
            DownloadsView()
                .tabItem {
                    Image(systemName: "arrow.down.circle.fill")
                    Text("Downloads")
                }
                .badge(downloadManager.activeDownloadCount > 0 ? downloadManager.activeDownloadCount : 0)
            
            LibraryView()
                .tabItem {
                    Image(systemName: "books.vertical.fill")
                    Text("Library")
                }
            
            SearchView()
                .tabItem {
                    Image(systemName: "magnifyingglass")
                    Text("Search")
                }
            
            SettingsView()
                .tabItem {
                    Image(systemName: "gear")
                    Text("Settings")
                }
        }
        .accentColor(accentColorManager.currentAccentColor)
    }
}

#Preview {
    ContentView()
}
