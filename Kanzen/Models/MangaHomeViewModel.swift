//
//  MangaHomeViewModel.swift
//  Kanzen
//
//  Created by Luna on 2025.
//

import Foundation
import SwiftUI

final class MangaHomeViewModel: ObservableObject {
    @Published var catalogResults: [String: [AniListManga]] = [:]
    @Published var isLoading = true
    @Published var errorMessage: String?
    @Published var hasLoadedContent = false

    func loadContent(catalogManager: MangaCatalogManager) {
        guard !hasLoadedContent else { return }

        isLoading = true
        errorMessage = nil

        Task {
            do {
                let allCatalogs = try await AniListMangaService.shared.fetchAllMangaCatalogs()

                await MainActor.run {
                    self.catalogResults = allCatalogs
                    self.isLoading = false
                    self.hasLoadedContent = true
                }
            } catch {
                await MainActor.run {
                    self.errorMessage = error.localizedDescription
                    self.isLoading = false
                }
            }
        }
    }

    func resetContent() {
        catalogResults = [:]
        isLoading = true
        errorMessage = nil
        hasLoadedContent = false
    }
}
