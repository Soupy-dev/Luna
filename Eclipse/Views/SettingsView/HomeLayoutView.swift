import SwiftUI

#if os(tvOS)
private enum TVCardDensity: String, CaseIterable, Identifiable {
    case spacious
    case standard
    case compact

    var id: String { rawValue }

    var displayName: String {
        switch self {
        case .spacious: return "Spacious"
        case .standard: return "Standard"
        case .compact: return "Compact"
        }
    }

}
#endif

struct HomeLayoutView: View {

    @AppStorage(ExperimentalMediaDesignPreset.storageKey) private var designPreset = ExperimentalMediaDesignPreset.defaultValue.rawValue
    @AppStorage(ExperimentalVisualTuning.cardRadiusScaleKey) private var cardRadiusScale = ExperimentalVisualTuning.defaultCardRadiusScale
    @AppStorage(ExperimentalVisualTuning.sectionSpacingScaleKey) private var sectionSpacingScale = ExperimentalVisualTuning.defaultSectionSpacingScale
    @AppStorage(ExperimentalVisualTuning.heroHeightScaleKey) private var heroHeightScale = ExperimentalVisualTuning.defaultHeroHeightScale
    @AppStorage(HomeAnimatedBackgroundSettings.enabledKey) private var animatedBackgroundEnabled = HomeAnimatedBackgroundSettings.defaultEnabled
    @AppStorage(HomeAnimatedBackgroundQuality.storageKey) private var animatedBackgroundQuality = HomeAnimatedBackgroundQuality.defaultValue.rawValue
    @AppStorage(HomeAnimatedBackgroundFrameRate.storageKey) private var animatedBackgroundFrameRate = HomeAnimatedBackgroundFrameRate.defaultValue.rawValue
#if os(tvOS)
    @AppStorage("tvCardDensity") private var tvCardDensityRaw = TVCardDensity.standard.rawValue
#endif

    @AppStorage("heroBannerCatalogId") private var heroBannerCatalogId = "trending"
    @AppStorage("heroBannerBehavior") private var heroBannerBehavior = HeroBannerBehavior.defaultValue.rawValue

    @StateObject private var catalogManager = CatalogManager.shared
    @StateObject private var accentColorManager = AccentColorManager.shared

    private var accent: Color { accentColorManager.currentAccentColor }

    private var sortedCatalogs: [Catalog] {
        catalogManager.catalogs.sorted { $0.order < $1.order }
    }

    var body: some View {
        List {
            globalSection
                .eclipseExperimentalSettingsRows()
            heroSection
                .eclipseExperimentalSettingsRows()
        }
        .eclipsePageTitle("Home Layout")
        .accessibilityIdentifier("tv.appearance.homeLayout.screen")
        .eclipseSettingsStyle()
#if os(tvOS)
        .onAppear {
            let density = TVCardDensity(rawValue: tvCardDensityRaw) ?? .standard
            tvCardDensityRaw = density.rawValue
        }
#endif
    }

    private var globalSection: some View {
        Section {
#if os(tvOS)
            pickerRow(
                title: "Card Density",
                description: "Choose comfortable ten-foot spacing without using phone column counts.",
                selection: Binding(
                    get: { (TVCardDensity(rawValue: tvCardDensityRaw) ?? .standard).rawValue },
                    set: { newValue in
                        let density = TVCardDensity(rawValue: newValue) ?? .standard
                        tvCardDensityRaw = density.rawValue
                    }
                ),
                values: TVCardDensity.allCases.map { ($0.rawValue, $0.displayName) }
            )
#endif

            pickerRow(
                title: "Layout Density",
                description: "Controls hero scale, spacing and base card sizing.",
                selection: $designPreset,
                values: ExperimentalMediaDesignPreset.allCases.map { ($0.rawValue, $0.displayName) }
            )

            sliderRow(
                title: "Card Roundness",
                description: "Corner radius of cards.",
                value: $cardRadiusScale,
                range: 0.7...1.4,
                step: 0.05
            )

            sliderRow(
                title: "Section Spacing",
                description: "Vertical rhythm between shelves.",
                value: $sectionSpacingScale,
                range: 0.75...1.35,
                step: 0.05
            )

            settingRow(
                title: "Animated Background",
                description: "Subtle Eclipse-style motion behind broad app surfaces."
            ) {
                Toggle("", isOn: $animatedBackgroundEnabled)
                    .labelsHidden()
#if os(tvOS)
                    .accessibilityLabel("Animated Background")
                    .accessibilityIdentifier("tv.appearance.animatedBackground")
#endif
                    .tint(accent)
            }

            pickerRow(
                title: "Animation Quality",
                description: "Low keeps the core eclipse rings and particles. Medium and High progressively add richer motion layers.",
                selection: $animatedBackgroundQuality,
                values: HomeAnimatedBackgroundQuality.allCases.map { ($0.rawValue, $0.displayName) }
            )

            pickerRow(
                title: "Animation Frame Rate",
                description: "Use the battery-friendly 20 FPS default, or choose smoother 30 FPS motion across Eclipse.",
                selection: $animatedBackgroundFrameRate,
                values: HomeAnimatedBackgroundFrameRate.allCases.map { ($0.rawValue, $0.displayName) }
            )
        } header: {
            Text("Global")
        } footer: {
            Text("Orientation, card size and card info (title, year, rating) moved to Settings > Catalogs, where they can also be customized per catalog.")
        }
    }

    private var heroSection: some View {
        Section {
            sliderRow(
                title: "Hero Size",
                description: "Scale the large banner artwork.",
                value: $heroHeightScale,
                range: 0.75...1.15,
                step: 0.05
            )

            pickerRow(
                title: "Hero Banner",
                description: "The home catalogue used for the large banner.",
                selection: $heroBannerCatalogId,
                values: sortedCatalogs.map { ($0.id, $0.name) }
            )

            settingRow(title: "Hero Behavior", description: "When the banner changes.") {
                Picker("", selection: heroBehaviorBinding) {
                    ForEach(HeroBannerBehavior.selectableCases) { behavior in
                        Text(behavior.displayName).tag(behavior.rawValue)
                    }
                }
                .pickerStyle(.menu)
            }
        } header: {
            Text("Hero")
        }
    }

    private var heroBehaviorBinding: Binding<String> {
        Binding(
            get: {
                let resolved = HeroBannerBehavior(rawValue: heroBannerBehavior) ?? .defaultValue
                return HeroBannerBehavior.selectableCases.contains(resolved) ? resolved.rawValue : HeroBannerBehavior.defaultValue.rawValue
            },
            set: { heroBannerBehavior = $0 }
        )
    }

    private func settingRow<Trailing: View>(
        title: String,
        description: String,
        @ViewBuilder trailing: () -> Trailing
    ) -> some View {
        HStack {
            VStack(alignment: .leading, spacing: 2) {
                Text(title).font(.subheadline).fontWeight(.medium)
                Text(description)
                    .font(.caption)
                    .foregroundColor(.secondary)
                    .multilineTextAlignment(.leading)
            }
            Spacer()
            trailing()
        }
    }

    private func pickerRow(
        title: String,
        description: String,
        selection: Binding<String>,
        values: [(String, String)]
    ) -> some View {
        settingRow(title: title, description: description) {
            Picker("", selection: selection) {
                ForEach(values, id: \.0) { option in
                    Text(option.1).tag(option.0)
                }
            }
            .pickerStyle(.menu)
        }
    }

    private func sliderRow(
        title: String,
        description: String,
        value: Binding<Double>,
        range: ClosedRange<Double>,
        step: Double,
        format: String = "%.2f"
    ) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(alignment: .firstTextBaseline) {
                VStack(alignment: .leading, spacing: 2) {
                    Text(title).font(.subheadline).fontWeight(.medium)
                    Text(description)
                        .font(.caption)
                        .foregroundColor(.secondary)
                        .multilineTextAlignment(.leading)
                }
                Spacer()
                Text(String(format: format, value.wrappedValue))
                    .font(.caption)
                    .foregroundColor(.secondary)
                    .monospacedDigit()
            }
#if os(tvOS)
            HStack(spacing: 18) {
                Button {
                    value.wrappedValue = max(range.lowerBound, value.wrappedValue - step)
                } label: {
                    Label("Decrease", systemImage: "minus")
                }
                .disabled(value.wrappedValue <= range.lowerBound)

                Button {
                    value.wrappedValue = min(range.upperBound, value.wrappedValue + step)
                } label: {
                    Label("Increase", systemImage: "plus")
                }
                .disabled(value.wrappedValue >= range.upperBound)
            }
#else
            Slider(value: value, in: range, step: step)
                .tint(accent)
#endif
        }
        .padding(.vertical, 2)
    }
}
