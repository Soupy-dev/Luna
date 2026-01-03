//
//  SettingsView.swift
//  Sora
//
//  Created by Francesco on 07/08/25.
//

import SwiftUI

struct SettingsView: View {
    @AppStorage("tmdbLanguage") private var selectedLanguage = "en-US"
    @StateObject private var algorithmManager = AlgorithmManager.shared
    @AppStorage("showKanzen") private var showKanzen: Bool = false
    @AppStorage("showScheduleTab") private var showScheduleTab = false
    @AppStorage("showLocalScheduleTime") private var showLocalScheduleTime = true
    
    let languages = [
        ("en-US", "English (US)"),
        ("en-GB", "English (UK)"),
        ("es-ES", "Spanish (Spain)"),
        ("es-MX", "Spanish (Mexico)"),
        ("fr-FR", "French"),
        ("de-DE", "German"),
        ("it-IT", "Italian"),
        ("pt-BR", "Portuguese (Brazil)"),
        ("ja-JP", "Japanese"),
        ("ko-KR", "Korean"),
        ("zh-CN", "Chinese (Simplified)"),
        ("zh-TW", "Chinese (Traditional)"),
        ("ru-RU", "Russian"),
        ("ar-SA", "Arabic"),
        ("hi-IN", "Hindi"),
        ("th-TH", "Thai"),
        ("tr-TR", "Turkish"),
        ("pl-PL", "Polish"),
        ("nl-NL", "Dutch"),
        ("sv-SE", "Swedish"),
        ("da-DK", "Danish"),
        ("no-NO", "Norwegian"),
        ("fi-FI", "Finnish")
    ]
    
    var body: some View {
        #if os(tvOS)
            HStack(spacing: 0) {
                VStack(spacing: 30) {
                    Image("Luna")
                        .resizable()
                        .aspectRatio(contentMode: .fit)
                        .frame(width: 500, height: 500)
                        .clipShape(RoundedRectangle(cornerRadius: 100, style: .continuous))
                        .shadow(radius: 10)

                    VStack(spacing: 15) {
                        Text("Version \(Bundle.main.appVersion) (\(Bundle.main.buildNumber))")
                            .font(.footnote)
                            .fontWeight(.regular)
                            .foregroundColor(.secondary)

                        Text("Copyright © \(String(Calendar.current.component(.year, from: Date()))) Luna by Cranci")
                            .font(.footnote)
                            .fontWeight(.semibold)
                            .foregroundColor(.white)
                    }
                }
                    .frame(maxWidth: .infinity, maxHeight: .infinity)

                NavigationStack {
                    settingsContent
                        // prevent row clipping
                        .padding(.horizontal, 20)
                }
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            }
        #else
            if #available(iOS 16.0, *) {
                NavigationStack {
                    settingsContent
                }
            } else {
                NavigationView {
                    settingsContent
                }
                .navigationViewStyle(StackNavigationViewStyle())
            }
        #endif
    }

    private var settingsContent: some View {
        List {
            Section {
                NavigationLink(destination: LanguageSelectionView(selectedLanguage: $selectedLanguage, languages: languages)) {
                    HStack {
                        VStack(alignment: .leading, spacing: 2) {
                            Text("Informations Language")
                        }
                        
                        Spacer()
                        
                        Text(languages.first { $0.0 == selectedLanguage }?.1 ?? "English (US)")
                            .foregroundColor(.secondary)
                    }
                }

                NavigationLink(destination: TMDBFiltersView()) {
                    Text("Content Filters")
                }
            } header: {
                Text("TMDB Settings")
            } footer: {
                Text("Configure language preferences and content filtering options for TMDB data.")
            }
            
            Section {
                NavigationLink(destination: AlgorithmSelectionView()) {
                    HStack {
                        VStack(alignment: .leading, spacing: 2) {
                            Text("Matching Algorithm")
                        }
                        
                        Spacer()
                        
                        Text(algorithmManager.selectedAlgorithm.displayName)
                            .foregroundColor(.secondary)
                    }
                }
            } header: {
                Text("SEARCH SETTINGS")
            } footer: {
                Text("Choose the algorithm used to match and rank search results.")
            }
            
            Section {
                NavigationLink(destination: PlayerSettingsView()) {
                    Text("Media Player")
                }
                
                NavigationLink(destination: SubtitleSettingsView()) {
                    Text("Subtitles")
                }
                
                NavigationLink(destination: AlternativeUIView()) {
                    Text("Appearance")
                }
                
                NavigationLink(destination: CatalogsSettingsView()) {
                    Text("Catalogs")
                }
                
                NavigationLink(destination: ServicesView()) {
                    Text("Services")
                }
                
                NavigationLink(destination: TrackersSettingsView()) {
                    Text("Trackers")
                }
            }

            Section {
                NavigationLink(destination: StorageView()) {
                    Text("Storage")
                }
                
                NavigationLink(destination: LoggerView()) {
                    Text("Logger")
                }
            } header: {
                Text("MICS")
            }

            Section {
                Toggle("Show Schedule tab", isOn: $showScheduleTab)
                Toggle("Use local time for schedule", isOn: $showLocalScheduleTime)
                    .disabled(!showScheduleTab)
                    .opacity(showScheduleTab ? 1 : 0.5)
            } header: {
                Text("Schedule")
            }
            
            Section{
                Text("Switch to Kanzen")
                    .onTapGesture {
                        showKanzen = true
                    }
            }
            header:{
                Text("Others")
            }
        }
        #if !os(tvOS)
            .navigationTitle("Settings")
        #else
            .listStyle(.grouped)
            .scrollClipDisabled()
        #endif
    }
}

struct LanguageSelectionView: View {
    @StateObject private var accentColorManager = AccentColorManager.shared
    @Binding var selectedLanguage: String
    let languages: [(String, String)]
    
    var body: some View {
        List {
            ForEach(languages, id: \.0) { language in
                HStack {
                    Text(language.1)
                    Spacer()
                    if selectedLanguage == language.0 {
                        Image(systemName: "checkmark")
                            .foregroundColor(accentColorManager.currentAccentColor)
                    }
                }
                .contentShape(Rectangle())
                .onTapGesture {
                    selectedLanguage = language.0
                }
            }
        }
        .navigationTitle("Language")
    }
}

struct SubtitleSettingsView: View {
    @ObservedObject var settings = Settings.shared
    @StateObject private var accentColorManager = AccentColorManager.shared
    
    let subtitleLanguages = [
        ("eng", "English"),
        ("spa", "Spanish"),
        ("fre", "French"),
        ("ger", "German"),
        ("ita", "Italian"),
        ("por", "Portuguese"),
        ("rus", "Russian"),
        ("jpn", "Japanese"),
        ("kor", "Korean"),
        ("chi", "Chinese"),
        ("ara", "Arabic"),
        ("hin", "Hindi"),
        ("tur", "Turkish"),
        ("pol", "Polish"),
        ("dut", "Dutch"),
        ("swe", "Swedish"),
        ("dan", "Danish"),
        ("nor", "Norwegian"),
        ("fin", "Finnish")
    ]
    
    var body: some View {
        List {
            Section {
                Toggle("Enable Subtitles by Default", isOn: $settings.enableSubtitlesByDefault)
            } footer: {
                Text("When enabled, subtitles will be automatically activated when playing a video.")
            }
            
            Section {
                NavigationLink(destination: SubtitleLanguageSelectionView(
                    selectedLanguage: $settings.defaultSubtitleLanguage,
                    languages: subtitleLanguages
                )) {
                    HStack {
                        Text("Default Language")
                        Spacer()
                        Text(subtitleLanguages.first { $0.0 == settings.defaultSubtitleLanguage }?.1 ?? "English")
                            .foregroundColor(.secondary)
                    }
                }
                .disabled(!settings.enableSubtitlesByDefault)
                .opacity(settings.enableSubtitlesByDefault ? 1 : 0.5)
            } header: {
                Text("Language")
            } footer: {
                Text("Select the preferred subtitle language to use when available.")
            }
            
            Section {
                ForEach(SubtitleSize.allCases) { size in
                    HStack {
                        Text(size.rawValue)
                        Spacer()
                        if settings.subtitleSize == size {
                            Image(systemName: "checkmark")
                                .foregroundColor(accentColorManager.currentAccentColor)
                        }
                    }
                    .contentShape(Rectangle())
                    .onTapGesture {
                        settings.subtitleSize = size
                    }
                }
            } header: {
                Text("Size")
            } footer: {
                Text("Choose the subtitle text size. Current: \(settings.subtitleSize.rawValue)")
            }
        }
        .navigationTitle("Subtitles")
    }
}

struct SubtitleLanguageSelectionView: View {
    @StateObject private var accentColorManager = AccentColorManager.shared
    @Binding var selectedLanguage: String
    let languages: [(String, String)]
    
    var body: some View {
        List {
            ForEach(languages, id: \.0) { language in
                HStack {
                    Text(language.1)
                    Spacer()
                    if selectedLanguage == language.0 {
                        Image(systemName: "checkmark")
                            .foregroundColor(accentColorManager.currentAccentColor)
                    }
                }
                .contentShape(Rectangle())
                .onTapGesture {
                    selectedLanguage = language.0
                }
            }
        }
        .navigationTitle("Subtitle Language")
    }
}
