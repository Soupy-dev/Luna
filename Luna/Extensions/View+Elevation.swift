//
//  View+Elevation.swift
//  Luna
//
//  Elevation and shadow system for depth and hierarchy
//

import SwiftUI

enum ElevationLevel {
    case none
    case low
    case medium
    case high
    case veryHigh
    
    var shadowRadius: CGFloat {
        switch self {
        case .none: return 0
        case .low: return 4
        case .medium: return 8
        case .high: return 16
        case .veryHigh: return 24
        }
    }
    
    var shadowOpacity: Double {
        switch self {
        case .none: return 0
        case .low: return 0.1
        case .medium: return 0.15
        case .high: return 0.2
        case .veryHigh: return 0.25
        }
    }
    
    var yOffset: CGFloat {
        switch self {
        case .none: return 0
        case .low: return 2
        case .medium: return 4
        case .high: return 8
        case .veryHigh: return 12
        }
    }
}

extension View {
    /// Apply elevation shadow for depth and hierarchy
    func elevation(_ level: ElevationLevel, color: Color = .black) -> some View {
        self.shadow(
            color: color.opacity(level.shadowOpacity),
            radius: level.shadowRadius,
            x: 0,
            y: level.yOffset
        )
    }
    
    /// Apply multiple layered shadows for richer depth (moon-themed)
    func moonShadow(intensity: Double = 1.0) -> some View {
        self
            .shadow(color: Color.black.opacity(0.1 * intensity), radius: 2, x: 0, y: 1)
            .shadow(color: Color.black.opacity(0.1 * intensity), radius: 8, x: 0, y: 4)
            .shadow(color: Color.blue.opacity(0.05 * intensity), radius: 16, x: 0, y: 8)
    }
    
    /// Card style with glass effect and elevation
    func moonCard(
        cornerRadius: CGFloat = 16,
        elevation: ElevationLevel = .medium,
        glassTint: Color? = nil
    ) -> some View {
        self
            .applyLiquidGlassBackground(
                cornerRadius: cornerRadius,
                fallbackFill: Color.black.opacity(0.2),
                fallbackMaterial: .ultraThinMaterial,
                glassTint: glassTint
            )
            .moonShadow(intensity: elevation == .high || elevation == .veryHigh ? 1.2 : 1.0)
    }
    
    /// Button style with press animation
    func moonButton(isPressed: Bool = false) -> some View {
        self
            .scaleEffect(isPressed ? 0.96 : 1.0)
            .animation(.spring(response: 0.3, dampingFraction: 0.6), value: isPressed)
    }
    
    /// Animated card appearance
    func animatedCard(delay: Double = 0) -> some View {
        self
            .transition(.asymmetric(
                insertion: .scale(scale: 0.9).combined(with: .opacity),
                removal: .scale(scale: 0.9).combined(with: .opacity)
            ))
            .animation(.spring(response: 0.6, dampingFraction: 0.8).delay(delay), value: true)
    }
}

/// Background gradient modifier for moon theme
struct MoonGradientBackground: ViewModifier {
    let opacity: Double
    
    func body(content: Content) -> some View {
        content
            .background(
                LinearGradient(
                    gradient: Gradient(colors: [
                        Color(red: 0.05, green: 0.05, blue: 0.15).opacity(opacity),
                        Color(red: 0.1, green: 0.05, blue: 0.2).opacity(opacity),
                        Color(red: 0.12, green: 0.08, blue: 0.22).opacity(opacity)
                    ]),
                    startPoint: .topLeading,
                    endPoint: .bottomTrailing
                )
            )
    }
}

extension View {
    func moonGradient(opacity: Double = 0.3) -> some View {
        modifier(MoonGradientBackground(opacity: opacity))
    }
}
