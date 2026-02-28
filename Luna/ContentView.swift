//
//  ContentView.swift
//  Sora
//
//  Created by Francesco on 07/08/25.
//

import SwiftUI

struct ContentView: View {
    private enum AppTab: Hashable {
        case home, schedule, downloads, library, search
    }
    
    @StateObject private var accentColorManager = AccentColorManager.shared
    @ObservedObject private var downloadManager = DownloadManager.shared
    @State private var selectedTab: AppTab = .home
    
    var body: some View {
#if compiler(>=6.0)
        if #available(iOS 26.0, tvOS 26.0, *) {
            modernTabView
                .accentColor(accentColorManager.currentAccentColor)
                .overlay(alignment: .topTrailing) {
                    if selectedTab == .home || selectedTab == .schedule {
                        FloatingSettingsOverlay()
                    }
                }
        } else {
            olderTabView
                .overlay {
                    if selectedTab == .home || selectedTab == .schedule {
                        FloatingSettingsOverlay()
                    }
                }
        }
#else
        olderTabView
            .overlay {
                if selectedTab == .home || selectedTab == .schedule {
                    FloatingSettingsOverlay()
                }
            }
#endif
    }
    
#if compiler(>=6.0)
    @available(iOS 26.0, tvOS 26.0, *)
    private var modernTabView: some View {
        TabView(selection: $selectedTab) {
            Tab("Home", systemImage: "house.fill", value: AppTab.home) {
                HomeView()
            }
            
            Tab("Schedule", systemImage: "calendar", value: AppTab.schedule) {
                ScheduleView()
            }
            
            Tab("Downloads", systemImage: "arrow.down.circle.fill", value: AppTab.downloads) {
                DownloadsView()
            }
#if !os(tvOS)
            .badge(downloadManager.activeDownloadCount > 0 ? downloadManager.activeDownloadCount : 0)
#endif
            
            Tab("Library", systemImage: "books.vertical.fill", value: AppTab.library) {
                LibraryView()
            }
            
            Tab("Search", systemImage: "magnifyingglass", value: AppTab.search, role: .search) {
                SearchView()
            }
        }
#if !os(tvOS)
        .tabBarMinimizeBehavior(.never)
#endif
    }
#endif
    
    private var olderTabView: some View {
        TabView(selection: $selectedTab) {
            HomeView()
                .tabItem {
                    Image(systemName: "house.fill")
                    Text("Home")
                }
                .tag(AppTab.home)
            
            ScheduleView()
                .tabItem {
                    Image(systemName: "calendar")
                    Text("Schedule")
                }
                .tag(AppTab.schedule)
            
            DownloadsView()
                .tabItem {
                    Image(systemName: "arrow.down.circle.fill")
                    Text("Downloads")
                }
                .tag(AppTab.downloads)
#if !os(tvOS)
                .badge(downloadManager.activeDownloadCount > 0 ? downloadManager.activeDownloadCount : 0)
#endif
            
            LibraryView()
                .tabItem {
                    Image(systemName: "books.vertical.fill")
                    Text("Library")
                }
                .tag(AppTab.library)
            
            SearchView()
                .tabItem {
                    Image(systemName: "magnifyingglass")
                    Text("Search")
                }
                .tag(AppTab.search)
        }
        .accentColor(accentColorManager.currentAccentColor)
    }
}

#Preview {
    ContentView()
}
