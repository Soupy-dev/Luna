//
//  FloatingSearchButton.swift
//  Luna
//
//  Created on 27/02/26.
//

import SwiftUI

struct FloatingSearchButton: View {
    @Binding var isPresented: Bool
    
    var body: some View {
        Button(action: {
            isPresented = true
        }) {
            Image(systemName: "magnifyingglass")
                .font(.system(size: 18, weight: .semibold))
                .foregroundColor(.white)
                .frame(width: 44, height: 44)
                .applyLiquidGlassBackground(cornerRadius: 22)
        }
        .shadow(color: .black.opacity(0.3), radius: 8, x: 0, y: 4)
    }
}

struct FloatingSearchOverlay: View {
    @State private var showingSearch = false
    
    var body: some View {
        ZStack(alignment: .topTrailing) {
            Color.clear
            
            FloatingSearchButton(isPresented: $showingSearch)
                .padding(.trailing, 16)
                .padding(.top, 8)
        }
        .allowsHitTesting(true)
        .sheet(isPresented: $showingSearch) {
            NavigationStack {
                SearchView()
                    .navigationBarTitleDisplayMode(.inline)
                    .toolbar {
                        ToolbarItem(placement: .cancellationAction) {
                            Button("Done") {
                                showingSearch = false
                            }
                        }
                    }
            }
        }
    }
}
