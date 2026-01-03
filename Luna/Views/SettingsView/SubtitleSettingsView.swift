//
//  SubtitleSettingsView.swift
//  Luna
//
//  Created by GitHub Copilot on 02/01/2026.
//

import SwiftUI

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
