//
//  KanzenGlobalSearchView.swift
//  Kanzen
//
//  Created by Luna on 2025.
//

import SwiftUI
import Kingfisher

#if !os(tvOS)
struct KanzenGlobalSearchView: View {
    @State private var searchText: String = ""
    @State private var searchResults: [AniListManga] = []
    @State private var isSearching: Bool = false
    @State private var hasSearched: Bool = false

    private let cellWidth: CGFloat = isIPad ? 150 * iPadScaleSmall : 150
    private var columnCount: Int {
        let screenWidth = UIScreen.main.bounds.width
        return Int(screenWidth / (cellWidth + 10))
    }

    var body: some View {
        NavigationView {
            VStack(spacing: 0) {
                // Search bar
                HStack {
                    HStack {
                        Image(systemName: "magnifyingglass")
                            .foregroundColor(.secondary)
                        TextField("Search manga…", text: $searchText, onCommit: performSearch)
                            .autocapitalization(.none)
                            .disableAutocorrection(true)
                        if !searchText.isEmpty {
                            Button(action: {
                                searchText = ""
                                searchResults = []
                                hasSearched = false
                            }) {
                                Image(systemName: "multiply.circle.fill")
                                    .foregroundColor(.secondary)
                            }
                        }
                    }
                    .padding(8)
                    .background(Color(.systemGray6))
                    .cornerRadius(10)
                }
                .padding(.horizontal, 16)
                .padding(.top, 8)

                if isSearching {
                    Spacer()
                    ProgressView("Searching…")
                    Spacer()
                } else if hasSearched && searchResults.isEmpty {
                    Spacer()
                    VStack(spacing: 8) {
                        Image(systemName: "magnifyingglass")
                            .font(.largeTitle)
                            .foregroundColor(.secondary)
                        Text("No results found")
                            .foregroundColor(.secondary)
                    }
                    Spacer()
                } else if !searchResults.isEmpty {
                    ScrollView {
                        LazyVGrid(
                            columns: Array(repeating: GridItem(.fixed(cellWidth), spacing: 10), count: columnCount),
                            spacing: 10
                        ) {
                            ForEach(searchResults) { manga in
                                NavigationLink(destination: MangaDetailView(manga: manga)) {
                                    contentCell(
                                        title: manga.displayTitle,
                                        urlString: manga.coverURL ?? "",
                                        width: cellWidth
                                    )
                                }
                                .buttonStyle(.plain)
                            }
                        }
                        .padding(.horizontal, 16)
                        .padding(.top, 12)
                    }
                } else {
                    Spacer()
                    VStack(spacing: 8) {
                        Image(systemName: "text.magnifyingglass")
                            .font(.system(size: 48))
                            .foregroundColor(.secondary)
                        Text("Search for manga on AniList")
                            .foregroundColor(.secondary)
                    }
                    Spacer()
                }
            }
            .navigationTitle("Search")
            .navigationBarTitleDisplayMode(.large)
        }
    }

    private func performSearch() {
        let query = searchText.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !query.isEmpty else { return }

        isSearching = true
        hasSearched = true

        Task {
            do {
                let results = try await AniListMangaService.shared.searchManga(query: query)
                await MainActor.run {
                    self.searchResults = results
                    self.isSearching = false
                }
            } catch {
                await MainActor.run {
                    self.searchResults = []
                    self.isSearching = false
                }
                Logger.shared.log("Manga search error: \(error.localizedDescription)", type: "Error")
            }
        }
    }
}
#endif
