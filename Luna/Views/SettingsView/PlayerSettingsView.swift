//
//  PlayerSettingsView.swift
//  Sora
//
//  Created by Francesco on 19/09/25.
//

import SwiftUI

enum ExternalPlayer: String, CaseIterable, Identifiable {
    case none = "Default"
    case infuse = "Infuse"
    case vlc = "VLC"
    case outPlayer = "OutPlayer"
    case nPlayer = "nPlayer"
    case senPlayer = "SenPlayer"
    case tracy = "TracyPlayer"
    case vidHub = "VidHub"
    
    var id: String { rawValue }
    
    func schemeURL(for urlString: String) -> URL? {
        let url = urlString.addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed) ?? urlString
        switch self {
        case .infuse:
            return URL(string: "infuse://x-callback-url/play?url=\(url)")
        case .vlc:
            return URL(string: "vlc://\(url)")
        case .outPlayer:
            return URL(string: "outplayer://\(url)")
        case .nPlayer:
            return URL(string: "nplayer-\(url)")
        case .senPlayer:
            return URL(string: "senplayer://x-callback-url/play?url=\(url)")
        case .tracy:
            return URL(string: "tracy://open?url=\(url)")
        case .vidHub:
            return URL(string: "open-vidhub://x-callback-url/open?url=\(url)")
        case .none:
            return nil
        }
    }
}

enum InAppPlayer: String, CaseIterable, Identifiable {
    case normal = "Normal"
    case mpv = "mpv"
    case vlc = "VLC"
    
    var id: String { rawValue }
}

final class PlayerSettingsStore: ObservableObject {
    @Published var holdSpeed: Double {
        didSet { UserDefaults.standard.set(holdSpeed, forKey: "holdSpeedPlayer") }
    }
    
    @Published var externalPlayer: ExternalPlayer {
        didSet { UserDefaults.standard.set(externalPlayer.rawValue, forKey: "externalPlayer") }
    }
    
    @Published var landscapeOnly: Bool {
        didSet { UserDefaults.standard.set(landscapeOnly, forKey: "alwaysLandscape") }
    }
    
    @Published var inAppPlayer: InAppPlayer {
        didSet { UserDefaults.standard.set(inAppPlayer.rawValue, forKey: "inAppPlayer") }
    }

    @Published var vlcSubtitleEditMenuEnabled: Bool {
        didSet { UserDefaults.standard.set(vlcSubtitleEditMenuEnabled, forKey: "enableVLCSubtitleEditMenu") }
    }

    @Published var vlcPictureInPictureEnabled: Bool {
        didSet { UserDefaults.standard.set(vlcPictureInPictureEnabled, forKey: "enableVLCPictureInPicture") }
    }
    
    init() {
        let savedSpeed = UserDefaults.standard.double(forKey: "holdSpeedPlayer")
        self.holdSpeed = savedSpeed > 0 ? savedSpeed : 2.0
        
        let raw = UserDefaults.standard.string(forKey: "externalPlayer") ?? ExternalPlayer.none.rawValue
        self.externalPlayer = ExternalPlayer(rawValue: raw) ?? .none
        
        self.landscapeOnly = UserDefaults.standard.bool(forKey: "alwaysLandscape")
        
        let inAppRaw = UserDefaults.standard.string(forKey: "inAppPlayer") ?? InAppPlayer.normal.rawValue
        self.inAppPlayer = InAppPlayer(rawValue: inAppRaw) ?? .normal

        self.vlcSubtitleEditMenuEnabled = UserDefaults.standard.bool(forKey: "enableVLCSubtitleEditMenu")
        self.vlcPictureInPictureEnabled = UserDefaults.standard.bool(forKey: "enableVLCPictureInPicture")
    }
}

struct PlayerSettingsView: View {
    @StateObject private var accentColorManager = AccentColorManager.shared
    @StateObject private var store = PlayerSettingsStore()
    @Environment(\.dismiss) private var dismiss
    
    var body: some View {
        List {
            Section(header: Text("Default Player"), footer: Text("This settings work exclusively with the Default media player.")) {
#if !os(tvOS)
                HStack {
                    VStack(alignment: .leading, spacing: 2) {
                        Text(String(format: "Hold Speed: %.1fx", store.holdSpeed))
                            .font(.subheadline)
                            .fontWeight(.medium)
                        
                        Text("Value of long-press speed playback in the player.")
                            .font(.caption)
                            .foregroundColor(.secondary)
                            .multilineTextAlignment(.leading)
                    }
                    
                    Spacer()
                    
                    Stepper(value: $store.holdSpeed, in: 0.1...3, step: 0.1) {}
                }
#endif
                
                HStack {
                    VStack(alignment: .leading, spacing: 2) {
                        Text("Force Landscape")
                            .font(.subheadline)
                            .fontWeight(.medium)
                        
                        Text("Force landscape orientation in the video player.")
                            .font(.caption)
                            .foregroundColor(.secondary)
                            .multilineTextAlignment(.leading)
                    }
                    
                    Spacer()
                    
                    Toggle("", isOn: $store.landscapeOnly)
                        .tint(accentColorManager.currentAccentColor)
                }
            }
            .disabled(store.externalPlayer != .none)
            
            Section(header: Text("Media Player")) {
                HStack {
                    VStack(alignment: .leading, spacing: 2) {
                        Text("Media Player")
                            .font(.subheadline)
                            .fontWeight(.medium)
                        
                        Text("The app must be installed and accept the provided scheme.")
                            .font(.caption)
                            .foregroundColor(.secondary)
                            .multilineTextAlignment(.leading)
                    }
                    
                    Picker("", selection: $store.externalPlayer) {
                        ForEach(ExternalPlayer.allCases) { player in
                            Text(player.rawValue).tag(player)
                        }
                    }
                    .pickerStyle(.menu)
                }
                
                HStack {
                    VStack(alignment: .leading, spacing: 2) {
                        Text("In-App Player")
                            .font(.subheadline)
                            .fontWeight(.medium)
                        
                        Text("Select the internal player software.")
                            .font(.caption)
                            .foregroundColor(.secondary)
                            .multilineTextAlignment(.leading)
                    }
                    
                    Picker("", selection: $store.inAppPlayer) {
                        ForEach(InAppPlayer.allCases) { p in
                            Text(p.rawValue).tag(p)
                        }
                    }
                    .pickerStyle(.menu)
                }
            }
            
            if store.inAppPlayer == .vlc {
                Section(header: Text("VLC Player"), footer: Text("Configure default subtitle and audio settings.")) {
                    HStack {
                        VStack(alignment: .leading, spacing: 2) {
                            Text("Enable Subtitles by Default")
                                .font(.subheadline)
                                .fontWeight(.medium)
                            
                            Text("Automatically load and display subtitles when available.")
                                .font(.caption)
                                .foregroundColor(.secondary)
                                .multilineTextAlignment(.leading)
                        }
                        
                        Spacer()
                        
                        Toggle("", isOn: Binding(
                            get: { UserDefaults.standard.bool(forKey: "enableSubtitlesByDefault") },
                            set: { UserDefaults.standard.set($0, forKey: "enableSubtitlesByDefault") }
                        ))
                        .tint(accentColorManager.currentAccentColor)
                    }

                #if !os(tvOS)
                    if store.inAppPlayer == .vlc {
                        HStack {
                            VStack(alignment: .leading, spacing: 2) {
                                Text("VLC Header Proxy")
                                    .font(.subheadline)
                                    .fontWeight(.medium)

                                Text("Route VLC streams through a local proxy to apply all headers.")
                                    .font(.caption)
                                    .foregroundColor(.secondary)
                                    .multilineTextAlignment(.leading)
                            }

                            Spacer()

                            Toggle("", isOn: Binding(
                                get: {
                                    UserDefaults.standard.object(forKey: "vlcHeaderProxyEnabled") as? Bool ?? true
                                },
                                set: { UserDefaults.standard.set($0, forKey: "vlcHeaderProxyEnabled") }
                            ))
                            .tint(accentColorManager.currentAccentColor)
                        }
                    }
                #endif
                    
                    NavigationLink(destination: VLCLanguageSelectionView(
                        title: "Default Subtitle Language",
                        selectedLanguage: Binding(
                            get: { UserDefaults.standard.string(forKey: "defaultSubtitleLanguage") ?? "eng" },
                            set: { UserDefaults.standard.set($0, forKey: "defaultSubtitleLanguage") }
                        )
                    )) {
                        HStack {
                            VStack(alignment: .leading, spacing: 2) {
                                Text("Default Subtitle Language")
                                    .font(.subheadline)
                                    .fontWeight(.medium)
                                
                                Text("Language preference for subtitles.")
                                    .font(.caption)
                                    .foregroundColor(.secondary)
                            }
                            
                            Spacer()
                            
                            Text(getLanguageName(UserDefaults.standard.string(forKey: "defaultSubtitleLanguage") ?? "eng"))
                                .foregroundColor(.secondary)
                                .font(.caption)
                        }
                    }
                    
                    NavigationLink(destination: VLCLanguageSelectionView(
                        title: "Preferred Anime Audio",
                        selectedLanguage: Binding(
                            get: { UserDefaults.standard.string(forKey: "preferredAnimeAudioLanguage") ?? "jpn" },
                            set: { UserDefaults.standard.set($0, forKey: "preferredAnimeAudioLanguage") }
                        )
                    )) {
                        HStack {
                            VStack(alignment: .leading, spacing: 2) {
                                Text("Preferred Anime Audio")
                                    .font(.subheadline)
                                    .fontWeight(.medium)
                                
                                Text("Audio language for anime content.")
                                    .font(.caption)
                                    .foregroundColor(.secondary)
                            }
                            
                            Spacer()
                            
                            Text(getLanguageName(UserDefaults.standard.string(forKey: "preferredAnimeAudioLanguage") ?? "jpn"))
                                .foregroundColor(.secondary)
                                .font(.caption)
                        }
                    }

                    HStack {
                        VStack(alignment: .leading, spacing: 2) {
                            Text("Subtitle Edit Menu")
                                .font(.subheadline)
                                .fontWeight(.medium)

                            Text("Show subtitle appearance options in VLC player UI. May reduce performance; native VLC subtitle rendering is generally cleaner.")
                                .font(.caption)
                                .foregroundColor(.secondary)
                                .multilineTextAlignment(.leading)
                        }

                        Spacer()

                        Toggle("", isOn: $store.vlcSubtitleEditMenuEnabled)
                            .tint(accentColorManager.currentAccentColor)
                    }

                    if store.vlcSubtitleEditMenuEnabled {
                        HStack {
                            VStack(alignment: .leading, spacing: 2) {
                                Text("Subtitle Text Color")
                                    .font(.subheadline)
                                    .fontWeight(.medium)

                                Text("Default color for custom subtitle rendering.")
                                    .font(.caption)
                                    .foregroundColor(.secondary)
                            }

                            Spacer()

                            Picker("", selection: subtitleTextColorBinding) {
                                ForEach(subtitleTextColorOptions.map(\.name), id: \.self) { name in
                                    Text(name).tag(name)
                                }
                            }
                            .pickerStyle(.menu)
                        }

                        HStack {
                            VStack(alignment: .leading, spacing: 2) {
                                Text("Subtitle Stroke Color")
                                    .font(.subheadline)
                                    .fontWeight(.medium)

                                Text("Outline color for custom subtitle rendering.")
                                    .font(.caption)
                                    .foregroundColor(.secondary)
                            }

                            Spacer()

                            Picker("", selection: subtitleStrokeColorBinding) {
                                ForEach(subtitleStrokeColorOptions.map(\.name), id: \.self) { name in
                                    Text(name).tag(name)
                                }
                            }
                            .pickerStyle(.menu)
                        }

                        HStack {
                            VStack(alignment: .leading, spacing: 2) {
                                Text(String(format: "Subtitle Stroke Width: %.1f", subtitleStrokeWidthBinding.wrappedValue))
                                    .font(.subheadline)
                                    .fontWeight(.medium)

                                Text("Outline thickness for custom subtitle rendering.")
                                    .font(.caption)
                                    .foregroundColor(.secondary)
                            }

                            Spacer()

                            Stepper("", value: subtitleStrokeWidthBinding, in: 0.0...2.0, step: 0.5)
                        }

                        HStack {
                            VStack(alignment: .leading, spacing: 2) {
                                Text("Subtitle Font Size")
                                    .font(.subheadline)
                                    .fontWeight(.medium)

                                Text("Named size presets for custom subtitle rendering.")
                                    .font(.caption)
                                    .foregroundColor(.secondary)
                            }

                            Spacer()

                            Picker("", selection: subtitleFontSizePresetBinding) {
                                ForEach(subtitleFontSizeOptions.map(\.name), id: \.self) { name in
                                    Text(name).tag(name)
                                }
                            }
                            .pickerStyle(.menu)
                        }

                        Button(action: resetVLCSubtitleStyleDefaults) {
                            HStack {
                                VStack(alignment: .leading, spacing: 2) {
                                    Text("Reset Subtitle Style")
                                        .font(.subheadline)
                                        .fontWeight(.medium)

                                    Text("Restore default subtitle text color, stroke, width, and font size.")
                                        .font(.caption)
                                        .foregroundColor(.secondary)
                                        .multilineTextAlignment(.leading)
                                }

                                Spacer()

                                Image(systemName: "arrow.counterclockwise")
                                    .foregroundColor(accentColorManager.currentAccentColor)
                            }
                        }
                    }

                    HStack {
                        VStack(alignment: .leading, spacing: 2) {
                            Text("Picture in Picture")
                                .font(.subheadline)
                                .fontWeight(.medium)

                            Text("Show PiP button in VLC player. May reduce performance because VLC does not natively handle PiP.")
                                .font(.caption)
                                .foregroundColor(.secondary)
                                .multilineTextAlignment(.leading)
                        }

                        Spacer()

                        Toggle("", isOn: $store.vlcPictureInPictureEnabled)
                            .tint(accentColorManager.currentAccentColor)
                    }
                }
            }
        }
        .navigationTitle("Media Player")
    }
    
    private func getLanguageName(_ code: String) -> String {
        let languages: [String: String] = [
            "eng": "English",
            "jpn": "Japanese",
            "zho": "Chinese",
            "kor": "Korean",
            "spa": "Spanish",
            "fra": "French",
            "deu": "German",
            "ita": "Italian",
            "por": "Portuguese",
            "rus": "Russian"
        ]
        return languages[code] ?? code.uppercased()
    }

    private var subtitleTextColorOptions: [(name: String, color: UIColor)] {
        [("White", .white), ("Yellow", .yellow), ("Cyan", .cyan), ("Green", .green), ("Magenta", .magenta)]
    }

    private var subtitleStrokeColorOptions: [(name: String, color: UIColor)] {
        [("Black", .black), ("Dark Gray", .darkGray), ("White", .white), ("None", .clear)]
    }

    private var subtitleTextColorBinding: Binding<String> {
        Binding(
            get: {
                let current = loadSubtitleColor(forKey: "subtitles_foregroundColor", defaultColor: .white)
                return subtitleTextColorOptions.first(where: { $0.color.isEqual(current) })?.name ?? "White"
            },
            set: { selectedName in
                if let selected = subtitleTextColorOptions.first(where: { $0.name == selectedName })?.color {
                    saveSubtitleColor(selected, forKey: "subtitles_foregroundColor")
                }
            }
        )
    }

    private var subtitleStrokeColorBinding: Binding<String> {
        Binding(
            get: {
                let current = loadSubtitleColor(forKey: "subtitles_strokeColor", defaultColor: .black)
                return subtitleStrokeColorOptions.first(where: { $0.color.isEqual(current) })?.name ?? "Black"
            },
            set: { selectedName in
                if let selected = subtitleStrokeColorOptions.first(where: { $0.name == selectedName })?.color {
                    saveSubtitleColor(selected, forKey: "subtitles_strokeColor")
                }
            }
        )
    }

    private var subtitleStrokeWidthBinding: Binding<Double> {
        Binding(
            get: {
                let saved = UserDefaults.standard.double(forKey: "subtitles_strokeWidth")
                return saved >= 0 ? saved : 1.0
            },
            set: { UserDefaults.standard.set($0, forKey: "subtitles_strokeWidth") }
        )
    }

    private var subtitleFontSizeOptions: [(name: String, size: Double)] {
        [
            ("Very Small", 24.0),
            ("Small", 30.0),
            ("Medium", 34.0),
            ("Large", 38.0),
            ("Extra Large", 42.0),
            ("Huge", 46.0),
            ("Extra Huge", 56.0)
        ]
    }

    private var subtitleFontSizePresetBinding: Binding<String> {
        Binding(
            get: {
                let saved = UserDefaults.standard.double(forKey: "subtitles_fontSize")
                let resolved = saved > 0 ? saved : 34.0
                if let exact = subtitleFontSizeOptions.first(where: { abs($0.size - resolved) < 0.01 }) {
                    return exact.name
                }
                let nearest = subtitleFontSizeOptions.min(by: { abs($0.size - resolved) < abs($1.size - resolved) })
                return nearest?.name ?? "Medium"
            },
            set: { selectedName in
                if let selected = subtitleFontSizeOptions.first(where: { $0.name == selectedName }) {
                    UserDefaults.standard.set(selected.size, forKey: "subtitles_fontSize")
                }
            }
        )
    }

    private func loadSubtitleColor(forKey key: String, defaultColor: UIColor) -> UIColor {
        guard let data = UserDefaults.standard.data(forKey: key),
              let color = try? NSKeyedUnarchiver.unarchivedObject(ofClass: UIColor.self, from: data) else {
            return defaultColor
        }
        return color
    }

    private func saveSubtitleColor(_ color: UIColor, forKey key: String) {
        if let data = try? NSKeyedArchiver.archivedData(withRootObject: color, requiringSecureCoding: false) {
            UserDefaults.standard.set(data, forKey: key)
        }
    }

    private func resetVLCSubtitleStyleDefaults() {
        saveSubtitleColor(.white, forKey: "subtitles_foregroundColor")
        saveSubtitleColor(.black, forKey: "subtitles_strokeColor")
        UserDefaults.standard.set(1.0, forKey: "subtitles_strokeWidth")
        UserDefaults.standard.set(34.0, forKey: "subtitles_fontSize")
    }
}