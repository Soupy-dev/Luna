//
//  MoonSplashScreen.swift
//  Luna
//
//  Moon-themed animated splash screen
//

import SwiftUI

struct MoonSplashScreen: View {
    @State private var moonScale: CGFloat = 0.5
    @State private var moonOpacity: Double = 0.0
    @State private var starsOpacity: Double = 0.0
    @State private var glowIntensity: Double = 0.0
    @State private var rotationAngle: Double = 0.0
    
    var body: some View {
        ZStack {
            // Deep space background with gradient
            LinearGradient(
                gradient: Gradient(colors: [
                    Color(red: 0.05, green: 0.05, blue: 0.15),
                    Color(red: 0.1, green: 0.05, blue: 0.2),
                    Color(red: 0.15, green: 0.1, blue: 0.25)
                ]),
                startPoint: .top,
                endPoint: .bottom
            )
            .ignoresSafeArea()
            
            // Animated stars
            ForEach(0..<20, id: \.self) { index in
                Circle()
                    .fill(Color.white.opacity(0.6))
                    .frame(width: CGFloat.random(in: 1...3), height: CGFloat.random(in: 1...3))
                    .position(
                        x: CGFloat.random(in: 0...UIScreen.main.bounds.width),
                        y: CGFloat.random(in: 0...UIScreen.main.bounds.height)
                    )
                    .opacity(starsOpacity)
                    .animation(
                        Animation.easeInOut(duration: Double.random(in: 1.5...3.0))
                            .repeatForever(autoreverses: true)
                            .delay(Double.random(in: 0...1.0)),
                        value: starsOpacity
                    )
            }
            
            // Main moon
            VStack(spacing: 20) {
                ZStack {
                    // Outer glow
                    Circle()
                        .fill(
                            RadialGradient(
                                gradient: Gradient(colors: [
                                    Color.blue.opacity(0.3 * glowIntensity),
                                    Color.purple.opacity(0.2 * glowIntensity),
                                    Color.clear
                                ]),
                                center: .center,
                                startRadius: 50,
                                endRadius: 120
                            )
                        )
                        .frame(width: 240, height: 240)
                        .blur(radius: 20)
                    
                    // Moon body
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
                                endRadius: 80
                            )
                        )
                        .frame(width: 120, height: 120)
                        .overlay(
                            // Moon craters
                            ZStack {
                                Circle()
                                    .fill(Color.black.opacity(0.1))
                                    .frame(width: 20, height: 20)
                                    .offset(x: -15, y: -10)
                                
                                Circle()
                                    .fill(Color.black.opacity(0.08))
                                    .frame(width: 15, height: 15)
                                    .offset(x: 20, y: 15)
                                
                                Circle()
                                    .fill(Color.black.opacity(0.06))
                                    .frame(width: 25, height: 25)
                                    .offset(x: 10, y: -20)
                            }
                        )
                        .shadow(color: Color.black.opacity(0.3), radius: 10, x: 5, y: 5)
                        .rotationEffect(.degrees(rotationAngle))
                    
                    // Shimmer effect
                    Circle()
                        .fill(
                            LinearGradient(
                                gradient: Gradient(colors: [
                                    Color.white.opacity(0.3),
                                    Color.clear
                                ]),
                                startPoint: .topLeading,
                                endPoint: .bottomTrailing
                            )
                        )
                        .frame(width: 120, height: 120)
                        .opacity(glowIntensity * 0.5)
                }
                .scaleEffect(moonScale)
                .opacity(moonOpacity)
                
                // App name
                Text("Luna")
                    .font(.system(size: 36, weight: .light, design: .rounded))
                    .foregroundColor(.white.opacity(0.9))
                    .opacity(moonOpacity)
            }
        }
        .onAppear {
            // Animate stars
            withAnimation(.easeIn(duration: 0.8)) {
                starsOpacity = 1.0
            }
            
            // Animate moon appearance
            withAnimation(.spring(response: 1.2, dampingFraction: 0.6, blendDuration: 0)) {
                moonScale = 1.0
                moonOpacity = 1.0
            }
            
            // Pulse glow
            withAnimation(.easeInOut(duration: 2.0).repeatForever(autoreverses: true)) {
                glowIntensity = 1.0
            }
            
            // Gentle rotation
            withAnimation(.linear(duration: 120).repeatForever(autoreverses: false)) {
                rotationAngle = 360
            }
        }
    }
}

#Preview {
    MoonSplashScreen()
}
