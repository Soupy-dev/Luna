//
//  CatalogsSettingsView.swift
//  Eclipse
//
//  Created by Soupy-dev
//

import SwiftUI

struct CatalogsSettingsView: View {
    @ObservedObject private var catalogManager = CatalogManager.shared
    @ObservedObject private var trackerManager = TrackerManager.shared
    @StateObject private var accentColorManager = AccentColorManager.shared
    @StateObject private var layoutStore = HomeCatalogLayoutStore.shared
    @State private var editMode = EditMode.active
    @State private var layoutEditorCatalog: Catalog?
    @State private var isLayoutEditorActive = false

    @AppStorage(ExperimentalHomeCardShape.storageKey) private var globalCardShape = ExperimentalHomeCardShape.defaultValue.rawValue
    @AppStorage(HomeCardInfoDisplay.storageKey) private var globalCardInfoDisplay = HomeCardInfoDisplay.defaultValue.rawValue
    @AppStorage(ExperimentalVisualTuning.mediaCardScaleKey) private var globalCardScale = ExperimentalVisualTuning.defaultMediaCardScale
    @AppStorage(BetterPostersSettings.enabledKey) private var betterPostersEnabled = BetterPostersSettings.defaultEnabled
    @AppStorage(BetterPostersSettings.urlPatternKey) private var betterPostersURLPattern = ""
    @AppStorage(BetterPostersSettings.applyToHomeKey) private var betterPostersApplyToHome = BetterPostersSettings.defaultApplyToHome

    var body: some View {
        catalogsContent
            .eclipsePageTitle("Catalogs")
            .accessibilityIdentifier("tv.settings.catalogs.screen")
            .eclipseSettingsStyle()
#if !os(tvOS)
            .environment(\.editMode, $editMode)
#endif
            .onAppear {
                StremioAddonManager.shared.loadAddons()
            }
            .background(layoutEditorNavigationLink)
    }

    @ViewBuilder
    private var layoutEditorNavigationLink: some View {
        NavigationLink(
            destination: Group {
                if let layoutEditorCatalog {
                    CatalogLayoutEditorView(catalog: layoutEditorCatalog)
                } else {
                    EmptyView()
                }
            },
            isActive: $isLayoutEditorActive
        ) {
            EmptyView()
        }
        .opacity(0)
    }

    @ViewBuilder
    private var catalogsContent: some View {
#if os(tvOS)
        ScrollView {
            LazyVStack(alignment: .leading, spacing: 22) {
                homeLayoutSection

                betterPostersSection

                Text("Content Catalogs")
                    .font(.title2.weight(.semibold))

                ForEach(Array(catalogManager.visibleCatalogs.enumerated()), id: \.element.id) { index, catalog in
                    HStack(spacing: 22) {
                        catalogIdentity(catalog)

                        Spacer(minLength: 20)

                        Button {
                            layoutEditorCatalog = catalog
                            isLayoutEditorActive = true
                        } label: {
                            Label("Customize", systemImage: "slider.horizontal.3")
                        }
                        .accessibilityIdentifier("tv.catalog.\(catalog.id).customize")

                        Toggle("Enabled", isOn: Binding(
                            get: { catalogManager.isCatalogEffectivelyEnabled(catalog) },
                            set: { _ in catalogManager.toggleCatalog(id: catalog.id) }
                        ))
                        .labelsHidden()
                        .tint(accentColorManager.currentAccentColor)
                        .accessibilityLabel("Enable \(catalog.name)")

                        Button {
                            moveCatalog(at: index, by: -1)
                        } label: {
                            Label("Move Up", systemImage: "chevron.up")
                        }
                        .disabled(index == 0)
                        .accessibilityIdentifier("tv.catalog.\(catalog.id).moveUp")

                        Button {
                            moveCatalog(at: index, by: 1)
                        } label: {
                            Label("Move Down", systemImage: "chevron.down")
                        }
                        .disabled(index == catalogManager.visibleCatalogs.count - 1)
                        .accessibilityIdentifier("tv.catalog.\(catalog.id).moveDown")
                    }
                    .padding(.horizontal, 30)
                    .padding(.vertical, 22)
                    .background(
                        RoundedRectangle(cornerRadius: 18, style: .continuous)
                            .fill(Color.white.opacity(0.075))
                    )
                    .overlay(
                        RoundedRectangle(cornerRadius: 18, style: .continuous)
                            .strokeBorder(Color.white.opacity(0.10), lineWidth: 1)
                    )
                    .focusSection()
                }

                Text("Enable or disable content catalogs and use the arrow buttons to reorder them. The order here determines the order on your home screen. Use Customize to override orientation, size, and card info per catalog.")
                    .font(.footnote)
                    .foregroundColor(.secondary)
                    .padding(.horizontal, 8)
            }
            .padding(.horizontal, 70)
            .padding(.vertical, 34)
        }
#else
        List {
            homeLayoutSection

            betterPostersSection

            Section {
                ForEach(catalogManager.visibleCatalogs) { catalog in
                    HStack {
                        VStack(alignment: .leading, spacing: 2) {
                            Text(catalog.name)
                                .font(.subheadline)
                                .fontWeight(.medium)

                            HStack(spacing: 6) {
                                Text(sourceText(for: catalog))
                                    .font(.caption)
                                    .foregroundColor(.secondary)

                                if catalogManager.isCatalogLockedByPerformanceMode(catalog) {
                                    Image(systemName: "lock.fill")
                                        .font(.caption2)
                                        .foregroundColor(.secondary)
                                }

                                if catalog.displayStyle != .standard {
                                    Text("\u{00B7} \(displayStyleText(for: catalog.displayStyle))")
                                        .font(.caption)
                                        .foregroundColor(.secondary)
                                }

                                if layoutStore.hasOverride(for: catalog.id) {
                                    Text("\u{00B7} Custom")
                                        .font(.caption)
                                        .foregroundColor(accentColorManager.currentAccentColor)
                                }
                            }
                        }

                        Spacer()

                        Button {
                            layoutEditorCatalog = catalog
                            isLayoutEditorActive = true
                        } label: {
                            Image(systemName: "slider.horizontal.3")
                                .foregroundColor(.secondary)
                        }
                        .buttonStyle(.plain)
                        .accessibilityLabel("Customize \(catalog.name)")

                        Toggle("", isOn: Binding(
                            get: { catalogManager.isCatalogEffectivelyEnabled(catalog) },
                            set: { _ in catalogManager.toggleCatalog(id: catalog.id) }
                        ))
                        .tint(accentColorManager.currentAccentColor)

                    }
                }
                .onMove(perform: catalogManager.moveVisibleCatalog)
            } header: {
                Text("Content Catalogs")
            } footer: {
                Text("Enable/disable content catalogs and drag to reorder them. The order here determines the order on your home screen. Tap the slider icon to customize orientation, size, and card info for a single catalog. Stremio catalog addons may reduce performance or have visual inconsistencies. Trakt catalogs appear after Trakt is connected.")
            }
            .eclipseExperimentalSettingsRows()
            .background(EclipseScrollTracker())
        }
#endif
    }

    private var betterPostersSection: some View {
        Section {
            Toggle("Enable Better Posters", isOn: $betterPostersEnabled)
                .tint(accentColorManager.currentAccentColor)

            if betterPostersEnabled {
                TextField("Poster URL Pattern", text: $betterPostersURLPattern)
#if !os(tvOS)
                    .textInputAutocapitalization(.never)
#endif
                    .autocorrectionDisabled()

                Toggle("Apply to Home Screen", isOn: $betterPostersApplyToHome)
                    .tint(accentColorManager.currentAccentColor)
            }
        } header: {
            Text("Poster Artwork")
        } footer: {
            if betterPostersEnabled {
                Text("Paste the URL from btttr.cc/configure (\"AIOMetadata / Other Addon\" \u{2192} \"I already have catalogs, just give me the poster URL\"). It should contain \(BetterPostersSettings.placeholderToken). Applying to the Home Screen looks up each title's IMDb id the first time it's shown and may use more data; it's off by default. Detail pages are unaffected for now.")
            } else {
                Text("Replace poster artwork with images from Better Posters (btttr.cc), a community poster service.")
            }
        }
        .eclipseExperimentalSettingsRows()
    }

    private var homeLayoutSection: some View {        Section {
            Picker("Orientation", selection: $globalCardShape) {
                ForEach(ExperimentalHomeCardShape.allCases) { option in
                    Text(option.displayName).tag(option.rawValue)
                }
            }
            .pickerStyle(.menu)

            Picker("Card Info", selection: $globalCardInfoDisplay) {
                ForEach(HomeCardInfoDisplay.allCases) { option in
                    Text(option.displayName).tag(option.rawValue)
                }
            }
            .pickerStyle(.menu)

#if !os(tvOS)
            VStack(alignment: .leading, spacing: 8) {
                HStack {
                    Text("Size")
                    Spacer()
                    Text(String(format: "%.2fx", globalCardScale))
                        .font(.caption)
                        .foregroundColor(.secondary)
                        .monospacedDigit()
                }
                Slider(value: $globalCardScale, in: HomeCatalogLayoutStore.sizeRange, step: 0.05)
                    .tint(accentColorManager.currentAccentColor)
            }
#endif

            Button(role: .destructive) {
                layoutStore.resetAll()
            } label: {
                HStack {
                    Text("Reset All Catalogs")
                        .font(.subheadline)
                        .fontWeight(.medium)
                    Spacer()
                    Image(systemName: "arrow.counterclockwise")
                        .foregroundColor(accentColorManager.currentAccentColor)
                }
            }
        } header: {
            Text("Home Layout")
        } footer: {
            Text("Orientation, size, and card info (title, year, rating) apply to every catalog on the home screen by default. Use the slider icon on a catalog below to override any of these just for that catalog.")
        }
        .eclipseExperimentalSettingsRows()
    }

    private func catalogIdentity(_ catalog: Catalog) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(catalog.name)
                .font(.headline)

            HStack(spacing: 6) {
                Text(sourceText(for: catalog))
                    .font(.caption)
                    .foregroundColor(.secondary)

                if catalogManager.isCatalogLockedByPerformanceMode(catalog) {
                    Image(systemName: "lock.fill")
                        .font(.caption2)
                        .foregroundColor(.secondary)
                }

                if catalog.displayStyle != .standard {
                    Text("\u{00B7} \(displayStyleText(for: catalog.displayStyle))")
                        .font(.caption)
                        .foregroundColor(.secondary)
                }

                if layoutStore.hasOverride(for: catalog.id) {
                    Text("\u{00B7} Custom")
                        .font(.caption)
                        .foregroundColor(accentColorManager.currentAccentColor)
                }
            }
        }
    }

    private func moveCatalog(at index: Int, by offset: Int) {
        let destination = index + offset
        let catalogs = catalogManager.visibleCatalogs
        guard catalogs.indices.contains(index), catalogs.indices.contains(destination) else { return }
        catalogManager.moveVisibleCatalog(
            from: IndexSet(integer: index),
            to: offset < 0 ? destination : destination + 1
        )
    }

    private func sourceText(for catalog: Catalog) -> String {
        if catalogManager.isCatalogLockedByPerformanceMode(catalog) {
            return "Source: Performance Mode - AniList locked"
        }
        if catalog.source == .stremio,
           let addonName = catalog.stremioAddonName,
           !addonName.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            return "Source: Stremio · \(addonName)"
        }
        if catalog.source == .trakt,
           let listIdentifier = catalog.traktListDisplayIdentifier {
            let mediaType = Catalog.normalizedTraktListMediaType(catalog.traktListMediaType) == "movies" ? "Movies" : "Shows"
            return "Source: Trakt - List \(listIdentifier) - \(mediaType)"
        }
        if catalog.id == Catalog.traktContinueWatchingCatalogId {
            return "Source: Trakt - Continue Watching"
        }
        return "Source: \(catalog.source.rawValue)"
    }

    private func displayStyleText(for style: Catalog.CatalogDisplayStyle) -> String {
        switch style {
        case .continueWatching:
            return "Playback"
        default:
            return style.rawValue.capitalized
        }
    }
}

struct CatalogLayoutEditorView: View {
    let catalog: Catalog

    @StateObject private var layoutStore = HomeCatalogLayoutStore.shared
    @StateObject private var accentColorManager = AccentColorManager.shared
    @AppStorage(ExperimentalVisualTuning.mediaCardScaleKey) private var globalCardScale = ExperimentalVisualTuning.defaultMediaCardScale

    private var accent: Color { accentColorManager.currentAccentColor }
    private var supportsOrientation: Bool { catalog.displayStyle == .standard }
    private var effectiveGlobalCardScale: Double {
#if os(tvOS)
        ExperimentalVisualTuning.current.mediaCardScale
#else
        globalCardScale
#endif
    }

    var body: some View {
        List {
            if supportsOrientation {
                Section {
                    Picker("Orientation", selection: orientationBinding) {
                        ForEach(CatalogOrientationOverride.allCases) { option in
                            Text(option.displayName).tag(option)
                        }
                    }
                    .pickerStyle(.menu)
                } header: {
                    Text("Orientation")
                } footer: {
#if os(tvOS)
                    Text("Global follows the Catalogs orientation. Automatic chooses one orientation per shelf, using posters for anime or missing backdrop artwork.")
#else
                    Text("Global follows the Catalogs orientation. Automatic picks poster or landscape per item.")
#endif
                }
                .eclipseExperimentalSettingsRows()
            }

            Section {
                Picker("Card Info", selection: cardInfoBinding) {
                    Text("Global").tag(Optional<HomeCardInfoDisplay>.none)
                    ForEach(HomeCardInfoDisplay.allCases) { option in
                        Text(option.displayName).tag(Optional(option))
                    }
                }
                .pickerStyle(.menu)
            } header: {
                Text("Card Info")
            } footer: {
                Text("Global follows the Catalogs card info setting. Choose title, year, rating, any combination, or poster only, just for this catalog.")
            }
            .eclipseExperimentalSettingsRows()

            Section {
                Toggle("Custom size", isOn: customSizeBinding)
                    .tint(accent)

                if let _ = layoutStore.override(for: catalog.id).sizeScale {
                    HStack {
                        Text("Size")
                            .font(.subheadline)
                        Spacer()
                        Text(String(format: "%.2fx", sizeValueBinding.wrappedValue))
                            .font(.caption)
                            .foregroundColor(.secondary)
                            .monospacedDigit()
                    }
#if os(tvOS)
                    HStack(spacing: 18) {
                        Button {
                            sizeValueBinding.wrappedValue = max(
                                HomeCatalogLayoutStore.sizeRange.lowerBound,
                                sizeValueBinding.wrappedValue - 0.05
                            )
                        } label: {
                            Label("Decrease Size", systemImage: "minus")
                        }
                        .disabled(sizeValueBinding.wrappedValue <= HomeCatalogLayoutStore.sizeRange.lowerBound)

                        Button {
                            sizeValueBinding.wrappedValue = min(
                                HomeCatalogLayoutStore.sizeRange.upperBound,
                                sizeValueBinding.wrappedValue + 0.05
                            )
                        } label: {
                            Label("Increase Size", systemImage: "plus")
                        }
                        .disabled(sizeValueBinding.wrappedValue >= HomeCatalogLayoutStore.sizeRange.upperBound)
                    }
#else
                    Slider(value: sizeValueBinding, in: HomeCatalogLayoutStore.sizeRange, step: 0.05)
                        .tint(accent)
#endif
                }
            } header: {
                Text("Size")
            } footer: {
                Text("Off follows the global size. Widget rows support size only.")
            }
            .eclipseExperimentalSettingsRows()

            Section {
                Button(role: .destructive) {
                    layoutStore.reset(id: catalog.id)
                } label: {
                    HStack {
                        Text("Reset to Global")
                            .font(.subheadline)
                            .fontWeight(.medium)
                        Spacer()
                        Image(systemName: "arrow.counterclockwise")
                            .foregroundColor(accent)
                    }
                }
            }
            .eclipseExperimentalSettingsRows()
        }
        .eclipsePageTitle(catalog.name)
        .eclipseSettingsStyle()
    }

    private var orientationBinding: Binding<CatalogOrientationOverride> {
        Binding(
            get: { layoutStore.override(for: catalog.id).orientation },
            set: { layoutStore.setOrientation($0, for: catalog.id) }
        )
    }

    private var cardInfoBinding: Binding<HomeCardInfoDisplay?> {
        Binding(
            get: { layoutStore.override(for: catalog.id).cardInfoDisplay },
            set: { layoutStore.setCardInfoDisplay($0, for: catalog.id) }
        )
    }

    private var customSizeBinding: Binding<Bool> {
        Binding(
            get: { layoutStore.override(for: catalog.id).sizeScale != nil },
            set: { isOn in
                layoutStore.setSizeScale(isOn ? effectiveGlobalCardScale : nil, for: catalog.id)
            }
        )
    }

    private var sizeValueBinding: Binding<Double> {
        Binding(
            get: { layoutStore.override(for: catalog.id).sizeScale ?? effectiveGlobalCardScale },
            set: { layoutStore.setSizeScale($0, for: catalog.id) }
        )
    }
}
