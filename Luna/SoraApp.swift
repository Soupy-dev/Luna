//
//  SoraApp.swift
//  Sora
//
//  Created by Francesco on 12/08/25.
//

import SwiftUI
import Kingfisher

@main
struct SoraApp: App {
    @StateObject private var settings = Settings()
    @StateObject private var moduleManager = ModuleManager.shared
    @StateObject private var favouriteManager = FavouriteManager.shared

#if !os(tvOS)
    @AppStorage("showKanzen") private var showKanzen: Bool = false
    let kanzen = KanzenEngine();
#endif

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
        .onOpenURL { url in
            handleDeepLink(url)
        }
    }
    
    private func handleDeepLink(_ url: URL) {
        guard let components = URLComponents(url: url, resolvingAgainstBaseURL: true) else {
            return
        }
        
        if let code = components.queryItems?.first(where: { $0.name == "code" })?.value {
            if url.host == "anilist-callback" {
                TrackerManager.shared.handleAniListCallback(code: code)
            } else if url.host == "trakt-callback" {
                TrackerManager.shared.handleTraktCallback(code: code)
            }
        }
    }
}
