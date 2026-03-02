//
//  MangaDetailView.swift
//  Kanzen
//
//  Created by Luna on 2025.
//

import SwiftUI
import Kingfisher

#if !os(tvOS)
struct MangaDetailView: View {
    let manga: AniListManga
    @EnvironmentObject var moduleManager: ModuleManager
    @State private var expandedDescription: Bool = false

    private let coverWidth: CGFloat = isIPad ? 150 * iPadScaleSmall : 150

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                // Header: cover + metadata
                headerSection

                Divider()

                // Description
                if let description = manga.description, !description.isEmpty {
                    descriptionSection(description)
                }

                Divider()

                // Genres
                if let genres = manga.genres, !genres.isEmpty {
                    genresSection(genres)
                }

                Divider()

                // Read with Module
                modulesSection
            }
            .padding(.horizontal, 16)
            .padding(.top, 8)
        }
        .navigationTitle(manga.displayTitle)
        .navigationBarTitleDisplayMode(.inline)
    }

    // MARK: - Header

    @ViewBuilder
    private var headerSection: some View {
        HStack(alignment: .top, spacing: 14) {
            KFImage(URL(string: manga.coverURL ?? ""))
                .placeholder { ProgressView() }
                .resizable()
                .scaledToFill()
                .frame(width: coverWidth, height: coverWidth * 1.5)
                .clipped()
                .cornerRadius(8)

            VStack(alignment: .leading, spacing: 6) {
                Text(manga.displayTitle)
                    .font(.title2)
                    .fontWeight(.bold)
                    .lineLimit(3)

                if let format = manga.format {
                    Text(formatLabel(format))
                        .font(.caption)
                        .padding(.horizontal, 6)
                        .padding(.vertical, 2)
                        .background(Color.accentColor.opacity(0.2))
                        .cornerRadius(4)
                }

                if let status = manga.status {
                    Label(statusLabel(status), systemImage: statusIcon(status))
                        .font(.subheadline)
                        .foregroundColor(.secondary)
                }

                HStack(spacing: 12) {
                    if let chapters = manga.chapters {
                        Label("\(chapters) ch", systemImage: "book.pages")
                            .font(.caption)
                            .foregroundColor(.secondary)
                    }
                    if let volumes = manga.volumes {
                        Label("\(volumes) vol", systemImage: "books.vertical")
                            .font(.caption)
                            .foregroundColor(.secondary)
                    }
                    if let score = manga.averageScore {
                        Label("\(score)%", systemImage: "star.fill")
                            .font(.caption)
                            .foregroundColor(.secondary)
                    }
                }
            }
            .frame(maxHeight: .infinity, alignment: .top)
        }
    }

    // MARK: - Description

    @ViewBuilder
    private func descriptionSection(_ text: String) -> some View {
        let cleaned = text
            .replacingOccurrences(of: "<br>", with: "\n")
            .replacingOccurrences(of: "<[^>]+>", with: "", options: .regularExpression)

        VStack(alignment: .leading, spacing: 4) {
            Text("Synopsis")
                .font(.headline)

            Text(cleaned)
                .font(.subheadline)
                .foregroundColor(.secondary)
                .lineLimit(expandedDescription ? nil : 4)
                .onTapGesture {
                    withAnimation { expandedDescription.toggle() }
                }

            if !expandedDescription {
                Text("Show more")
                    .font(.caption)
                    .foregroundColor(.accentColor)
                    .onTapGesture {
                        withAnimation { expandedDescription.toggle() }
                    }
            }
        }
    }

    // MARK: - Genres

    @ViewBuilder
    private func genresSection(_ genres: [String]) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Genres")
                .font(.headline)

            FlowLayout(spacing: 6) {
                ForEach(genres, id: \.self) { genre in
                    Text(genre)
                        .font(.caption)
                        .padding(.horizontal, 8)
                        .padding(.vertical, 4)
                        .background(Color.accentColor.opacity(0.15))
                        .cornerRadius(6)
                }
            }
        }
    }

    // MARK: - Modules

    @ViewBuilder
    private var modulesSection: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("Read with Module")
                .font(.headline)

            let availableModules = moduleManager.modules

            if availableModules.isEmpty {
                VStack(spacing: 8) {
                    Image(systemName: "puzzlepiece.extension")
                        .font(.title2)
                        .foregroundColor(.secondary)
                    Text("No modules installed. Add one from the Browse tab.")
                        .font(.caption)
                        .foregroundColor(.secondary)
                        .multilineTextAlignment(.center)
                }
                .frame(maxWidth: .infinity)
                .padding(.vertical, 12)
            } else {
                ForEach(availableModules) { module in
                    NavigationLink(destination: ModuleSearchBridge(module: module, searchQuery: manga.displayTitle)) {
                        HStack(spacing: 12) {
                            if let iconURL = URL(string: module.moduleData.iconURL) {
                                KFImage(iconURL)
                                    .resizable()
                                    .scaledToFit()
                                    .frame(width: 36, height: 36)
                                    .cornerRadius(8)
                            } else {
                                Image(systemName: "puzzlepiece.extension")
                                    .frame(width: 36, height: 36)
                                    .foregroundColor(.accentColor)
                            }

                            VStack(alignment: .leading, spacing: 2) {
                                Text(module.moduleData.sourceName)
                                    .font(.subheadline)
                                    .fontWeight(.medium)
                                Text(module.moduleData.language)
                                    .font(.caption)
                                    .foregroundColor(.secondary)
                            }

                            Spacer()

                            Image(systemName: "chevron.right")
                                .font(.caption)
                                .foregroundColor(.secondary)
                        }
                        .padding(.vertical, 6)
                    }
                    .buttonStyle(.plain)
                    Divider()
                }
            }
        }
    }

    // MARK: - Helpers

    private func formatLabel(_ format: String) -> String {
        switch format {
        case "MANGA": return "Manga"
        case "NOVEL": return "Light Novel"
        case "ONE_SHOT": return "One Shot"
        default: return format.capitalized
        }
    }

    private func statusLabel(_ status: String) -> String {
        switch status {
        case "RELEASING": return "Publishing"
        case "FINISHED": return "Completed"
        case "NOT_YET_RELEASED": return "Upcoming"
        case "CANCELLED": return "Cancelled"
        case "HIATUS": return "Hiatus"
        default: return status.capitalized
        }
    }

    private func statusIcon(_ status: String) -> String {
        switch status {
        case "RELEASING": return "clock.arrow.circlepath"
        case "FINISHED": return "checkmark.circle"
        case "NOT_YET_RELEASED": return "calendar"
        case "CANCELLED": return "xmark.circle"
        case "HIATUS": return "pause.circle"
        default: return "questionmark.circle"
        }
    }
}

// MARK: - Flow Layout

/// Simple horizontal wrapping layout for genre tags.
struct FlowLayout: Layout {
    var spacing: CGFloat = 6

    func sizeThatFits(proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) -> CGSize {
        let maxWidth = proposal.width ?? .infinity
        var x: CGFloat = 0
        var y: CGFloat = 0
        var rowHeight: CGFloat = 0

        for subview in subviews {
            let size = subview.sizeThatFits(.unspecified)
            if x + size.width > maxWidth && x > 0 {
                x = 0
                y += rowHeight + spacing
                rowHeight = 0
            }
            x += size.width + spacing
            rowHeight = max(rowHeight, size.height)
        }

        return CGSize(width: maxWidth, height: y + rowHeight)
    }

    func placeSubviews(in bounds: CGRect, proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) {
        var x: CGFloat = bounds.minX
        var y: CGFloat = bounds.minY
        var rowHeight: CGFloat = 0

        for subview in subviews {
            let size = subview.sizeThatFits(.unspecified)
            if x + size.width > bounds.maxX && x > bounds.minX {
                x = bounds.minX
                y += rowHeight + spacing
                rowHeight = 0
            }
            subview.place(at: CGPoint(x: x, y: y), proposal: .unspecified)
            x += size.width + spacing
            rowHeight = max(rowHeight, size.height)
        }
    }
}

// MARK: - Module Search Bridge

/// Opens a per-module search view pre-filled with the manga title so the user
/// can pick the correct source entry and jump into reading.
struct ModuleSearchBridge: View {
    let module: ModuleDataContainer
    let searchQuery: String
    @StateObject private var kanzen = KanzenEngine()
    @EnvironmentObject var moduleManager: ModuleManager
    @State private var moduleLoaded = false

    var body: some View {
        Group {
            if moduleLoaded {
                KanzenSearchView(module: module, searchText: searchQuery)
                    .environmentObject(kanzen)
                    .environmentObject(moduleManager)
            } else {
                ProgressView("Loading module…")
                    .task { loadModule() }
            }
        }
    }

    private func loadModule() {
        do {
            let content = try ModuleManager.shared.getModuleScript(module: module)
            try kanzen.loadScript(content)
            moduleLoaded = true
        } catch {
            Logger.shared.log("ModuleSearchBridge: Failed to load module: \(error.localizedDescription)", type: "Error")
        }
    }
}
#endif
