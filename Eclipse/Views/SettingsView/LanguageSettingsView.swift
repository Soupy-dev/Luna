
import SwiftUI

enum AppLanguageOption: String, CaseIterable, Identifiable {
    static let storageKey = "appLanguageOverride"

    case system
    case en
    case es

    var id: String { rawValue }

    var displayName: String {
        switch self {
        case .system: return "System Default"
        case .en: return "English (US)"
        case .es: return "Español"
        }
    }

    var appleLanguageCode: String? {
        switch self {
        case .system: return nil
        case .en: return "en"
        case .es: return "es"
        }
    }

    static var current: AppLanguageOption {
        let raw = UserDefaults.standard.string(forKey: storageKey)
        return AppLanguageOption(rawValue: raw ?? "") ?? .system
    }
}

struct LanguageSettingsView: View {
    @AppStorage(AppLanguageOption.storageKey) private var selectedRaw = AppLanguageOption.system.rawValue
    @State private var showRestartAlert = false
    @StateObject private var accentColorManager = AccentColorManager.shared

    private var accent: Color { accentColorManager.currentAccentColor }

    private var selected: AppLanguageOption {
        AppLanguageOption(rawValue: selectedRaw) ?? .system
    }

    var body: some View {
        List {
            Section {
                ForEach(AppLanguageOption.allCases) { option in
                    Button {
                        applySelection(option)
                    } label: {
                        HStack {
                            Text(option.displayName)
                                .foregroundColor(.primary)
                            Spacer()
                            if option == selected {
                                Image(systemName: "checkmark")
                                    .foregroundColor(accent)
                            }
                        }
                        .contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)
                }
            } footer: {
                Text("Translations are community-contributed and still a work in progress, so some screens may still show English text. Eclipse applies the interface language the next time it launches.")
            }
        }
        .eclipsePageTitle("Language")
        .accessibilityIdentifier("tv.settings.language.screen")
        .eclipseSettingsStyle()
        .alert("Restart Required", isPresented: $showRestartAlert) {
            Button("OK", role: .cancel) { }
        } message: {
            Text("Restart Eclipse to finish switching the interface language.")
        }
    }

    private func applySelection(_ option: AppLanguageOption) {
        guard option != selected else { return }
        selectedRaw = option.rawValue

        if let code = option.appleLanguageCode {
            UserDefaults.standard.set([code], forKey: "AppleLanguages")
        } else {
            UserDefaults.standard.removeObject(forKey: "AppleLanguages")
        }

        showRestartAlert = true
    }
}
