//
//  FloatingSettingsButton.swift
//  Luna
//
//  Created on 27/02/26.
//

import SwiftUI

struct FloatingSettingsButton: View {
    @Binding var isPresented: Bool
    
    var body: some View {
        Button(action: {
            isPresented = true
        }) {
            Image(systemName: "gear")
                .font(.system(size: 18, weight: .semibold))
                .foregroundColor(.white)
                .frame(width: 44, height: 44)
                .applyLiquidGlassBackground(cornerRadius: 22)
        }
        .shadow(color: .black.opacity(0.3), radius: 8, x: 0, y: 4)
    }
}

struct FloatingSettingsOverlay: View {
    @State private var showingSettings = false
    
    private var settingsSheetContent: some View {
        SettingsView()
#if os(iOS)
            .navigationBarTitleDisplayMode(.inline)
#endif
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Done") {
                        showingSettings = false
                    }
                }
            }
    }
    
    var body: some View {
        ZStack(alignment: .topTrailing) {
            Color.clear
                .allowsHitTesting(false)
            
            FloatingSettingsButton(isPresented: $showingSettings)
                .padding(.trailing, 16)
                .padding(.top, 8)
        }
        .sheet(isPresented: $showingSettings) {
            if #available(iOS 16.0, *) {
                NavigationStack {
                    settingsSheetContent
                }
            } else {
                NavigationView {
                    settingsSheetContent
                }
                .navigationViewStyle(StackNavigationViewStyle())
            }
        }
    }
}
