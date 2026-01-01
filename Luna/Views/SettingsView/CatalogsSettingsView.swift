//
//  CatalogsSettingsView.swift
//  Luna
//
//  Created by Soupy-dev
//

import SwiftUI

struct CatalogsSettingsView: View {
    @ObservedObject var catalogManager = CatalogManager.shared
    @Environment(\.dismiss) var dismiss
    
    var body: some View {
        List {
            Section {
                ForEach(catalogManager.catalogs.indices, id: \.self) { index in
                    HStack {
                        VStack(alignment: .leading, spacing: 4) {
                            Text(catalogManager.catalogs[index].name)
                                .fontWeight(.semibold)
                            
                            HStack(spacing: 8) {
                                Image(systemName: catalogManager.catalogs[index].source == .tmdb ? "film" : "list.star")
                                    .font(.caption)
                                    .foregroundColor(.secondary)
                                
                                Text(catalogManager.catalogs[index].source.rawValue)
                                    .font(.caption)
                                    .foregroundColor(.secondary)
                            }
                        }
                        
                        Spacer()
                        
                        Toggle("", isOn: Binding(
                            get: { catalogManager.catalogs[index].isEnabled },
                            set: { newValue in
                                catalogManager.catalogs[index].isEnabled = newValue
                                catalogManager.saveCatalogs()
                            }
                        ))
                    }
                }
                .onMove { fromOffsets, toOffset in
                    catalogManager.moveCatalog(from: fromOffsets, to: toOffset)
                }
            } header: {
                Text("AVAILABLE CATALOGS")
            } footer: {
                Text("Enable or disable catalogs that appear on the home screen. Drag to reorder.")
            }
            
            Section {
                Text("TMDB catalogs use The Movie Database for trending, popular, and top-rated movies and TV shows.")
                    .font(.caption)
                    .foregroundColor(.secondary)
                
                Text("AniList catalogs use AniList for anime-specific content and recommendations.")
                    .font(.caption)
                    .foregroundColor(.secondary)
            } header: {
                Text("ABOUT SOURCES")
            }
        }
        .navigationTitle("Catalogs")
        .environment(\.editMode, .constant(.active))
    }
}

#Preview {
    NavigationView {
        CatalogsSettingsView()
    }
}
