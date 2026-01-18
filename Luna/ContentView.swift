//
//  ContentView.swift
//  Sora
//
//  Created by Francesco on 07/08/25.
//

import SwiftUI

struct ContentView: View {
    @StateObject private var accentColorManager = AccentColorManager.shared
    @State private var showSplash = true
    
    var body: some View {
        ZStack {
            if showSplash {
                MoonSplashScreen()
                    .transition(.opacity)
                    .zIndex(2)
            } else {
                mainContent
                    .transition(.opacity)
                    .zIndex(1)
            }
        }
        .onAppear {
            // Show splash for 2.5 seconds
            DispatchQueue.main.asyncAfter(deadline: .now() + 2.5) {
                withAnimation(.easeInOut(duration: 0.6)) {
                    showSplash = false
                }
            }
        }
    }
    
    @ViewBuilder
    private var mainContent: some View {
#if compiler(>=6.0)
        if #available(iOS 18.0, tvOS 18.0, *) {
            TabView {
                Tab("Home", systemImage: "house.fill") {
                    HomeView()
                }
                
                Tab("Schedule", systemImage: "calendar") {
                    ScheduleView()
                }
                
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
        } else {
            fallbackTabView
        }
#else
        fallbackTabView
#endif
    }
    
    private var fallbackTabView: some View {
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
