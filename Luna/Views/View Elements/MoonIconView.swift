//
//  MoonIconView.swift
//  Luna
//
//  Reusable moon icon component for decorative purposes
//

import SwiftUI

struct MoonIconView: View {
    let size: CGFloat
    let showGlow: Bool
    
    init(size: CGFloat = 40, showGlow: Bool = true) {
        self.size = size
        self.showGlow = showGlow
    }
    
    var body: some View {
        ZStack {
            if showGlow {
                Circle()
                    .fill(
                        RadialGradient(
                            gradient: Gradient(colors: [
                                Color.blue.opacity(0.2),
                                Color.purple.opacity(0.1),
                                Color.clear
                            ]),
                            center: .center,
                            startRadius: size * 0.4,
                            endRadius: size * 1.2
                        )
                    )
                    .frame(width: size * 2, height: size * 2)
                    .blur(radius: 10)
            }
            
            Circle()
                .fill(
                    RadialGradient(
                        gradient: Gradient(colors: [
                            Color(red: 0.95, green: 0.95, blue: 1.0),
                            Color(red: 0.85, green: 0.88, blue: 0.95),
                            Color(red: 0.75, green: 0.78, blue: 0.88)
                        ]),
                        center: .topLeading,
                        startRadius: 0,
                        endRadius: size * 0.8
                    )
                )
                .frame(width: size, height: size)
                .overlay(
                    // Craters
                    ZStack {
                        Circle()
                            .fill(Color.black.opacity(0.1))
                            .frame(width: size * 0.2, height: size * 0.2)
                            .offset(x: -size * 0.15, y: -size * 0.1)
                        
                        Circle()
                            .fill(Color.black.opacity(0.08))
                            .frame(width: size * 0.15, height: size * 0.15)
                            .offset(x: size * 0.2, y: size * 0.15)
                        
                        Circle()
                            .fill(Color.black.opacity(0.06))
                            .frame(width: size * 0.25, height: size * 0.25)
                            .offset(x: size * 0.1, y: -size * 0.2)
                    }
                )
                .shadow(color: Color.black.opacity(0.2), radius: size * 0.1, x: size * 0.05, y: size * 0.05)
        }
    }
}

#Preview {
    ZStack {
        Color.black
        MoonIconView(size: 120)
    }
}
