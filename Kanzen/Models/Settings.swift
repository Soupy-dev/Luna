//
//  Settings.swift
//  Luna
//
//  Created by Dawud Osman on 17/11/2025.
//
import SwiftUI
// helper Class & Enums
enum Appearance: String, CaseIterable, Identifiable {
    case system, light, dark
    
    var id: String { self.rawValue }
}

enum PlayerChoice: String, CaseIterable, Identifiable {
    case mpv = "MPV"
    case vlc = "VLC"
    
    var id: String { self.rawValue }
}

enum SubtitleSize: String, CaseIterable, Identifiable {
    case small = "Small"
    case medium = "Medium"
    case large = "Large"
    case extraLarge = "Extra Large"
    
    var id: String { self.rawValue }
    
    var fontSize: CGFloat {
        switch self {
        case .small: return 38.0   // trimmed slightly for compact default
        case .medium: return 48.0  // modest reduction from prior large
        case .large: return 60.0   // reduced for less screen coverage
        case .extraLarge: return 72.0 // keep a big option but slightly smaller
        }
    }
    
    var strokeWidth: CGFloat {
        switch self {
        case .small: return 1.3
        case .medium: return 1.6
        case .large: return 1.9
        case .extraLarge: return 2.3
        }
    }
}
class Settings: ObservableObject {
    static let shared = Settings()
    
    @Published var accentColor: Color {
        didSet {
            saveAccentColor(accentColor)
        }
    }
    @Published var selectedAppearance: Appearance {
        didSet {
            UserDefaults.standard.set(selectedAppearance.rawValue, forKey: "selectedAppearance")
            updateAppearance()
        }
    }
    
    // Subtitle Settings
    @Published var enableSubtitlesByDefault: Bool {
        didSet {
            UserDefaults.standard.set(enableSubtitlesByDefault, forKey: "enableSubtitlesByDefault")
        }
    }
    
    @Published var defaultSubtitleLanguage: String {
        didSet {
            UserDefaults.standard.set(defaultSubtitleLanguage, forKey: "defaultSubtitleLanguage")
        }
    }
    
    @Published var subtitleSize: SubtitleSize {
        didSet {
            UserDefaults.standard.set(subtitleSize.rawValue, forKey: "subtitleSize")
        }
    }

    @Published var preferredAnimeAudioLanguage: String {
        didSet {
            UserDefaults.standard.set(preferredAnimeAudioLanguage, forKey: "preferredAnimeAudioLanguage")
        }
    }
    
    @Published var playerChoice: PlayerChoice {
        didSet {
            UserDefaults.standard.set(playerChoice.rawValue, forKey: "playerChoice")
        }
    }
    
    init() {
        if let colorData = UserDefaults.standard.data(forKey: "accentColor"),
           let uiColor = try? NSKeyedUnarchiver.unarchivedObject(ofClass: UIColor.self, from: colorData) {
            self.accentColor = Color(uiColor)
        } else {
            self.accentColor = .accentColor
        }
        if let appearanceRawValue = UserDefaults.standard.string(forKey: "selectedAppearance"),
           let appearance = Appearance(rawValue: appearanceRawValue) {
            self.selectedAppearance = appearance
        } else {
            self.selectedAppearance = .system
        }
        
        // Load subtitle settings
        self.enableSubtitlesByDefault = UserDefaults.standard.bool(forKey: "enableSubtitlesByDefault")
        self.defaultSubtitleLanguage = UserDefaults.standard.string(forKey: "defaultSubtitleLanguage") ?? "eng"
        if let sizeRawValue = UserDefaults.standard.string(forKey: "subtitleSize"),
           let size = SubtitleSize(rawValue: sizeRawValue) {
            self.subtitleSize = size
        } else {
            self.subtitleSize = .large
        }

        self.preferredAnimeAudioLanguage = UserDefaults.standard.string(forKey: "preferredAnimeAudioLanguage") ?? "jpn"
        
        // Load player choice
        if let choiceRawValue = UserDefaults.standard.string(forKey: "playerChoice"),
           let choice = PlayerChoice(rawValue: choiceRawValue) {
            self.playerChoice = choice
        } else {
            self.playerChoice = .mpv  // Default to mpv for backward compatibility
        }
        
        updateAppearance()
    }
    
    private func saveAccentColor(_ color: Color) {
        
        let uiColor = UIColor(color)
        do {
            let colorData = try NSKeyedArchiver.archivedData(withRootObject: uiColor, requiringSecureCoding: false)
            UserDefaults.standard.set(colorData, forKey: "accentColor")
        } catch {
            Logger.shared.log("Failed to save accent color: \(error.localizedDescription)")
        }
    }
    
    func updateAppearance() {
        guard let windowScene = UIApplication.shared.connectedScenes.first as? UIWindowScene else { return }
        switch selectedAppearance {
        case .system:
            windowScene.windows.first?.overrideUserInterfaceStyle = .unspecified
        case .light:
            windowScene.windows.first?.overrideUserInterfaceStyle = .light
        case .dark:
            windowScene.windows.first?.overrideUserInterfaceStyle = .dark
        }
    }
}
