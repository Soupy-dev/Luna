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

enum SubtitleSize: String, CaseIterable, Identifiable {
    case small = "Small"
    case medium = "Medium"
    case large = "Large"
    case extraLarge = "Extra Large"
    
    var id: String { self.rawValue }
    
    var fontSize: CGFloat {
        switch self {
        case .small: return 32.0
        case .medium: return 42.0
        case .large: return 52.0
        case .extraLarge: return 64.0
        }
    }
    
    var strokeWidth: CGFloat {
        switch self {
        case .small: return 2.5
        case .medium: return 3.0
        case .large: return 3.5
        case .extraLarge: return 4.0
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
