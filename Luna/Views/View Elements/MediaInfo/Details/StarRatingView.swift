//
//  StarRatingView.swift
//  Luna
//
//  Interactive 5-star rating component for media detail views.
//

import SwiftUI

struct StarRatingView: View {
    let mediaId: Int
    @State private var currentRating: Int = 0
    @State private var highlightedRating: Int = 0

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Your Rating")
                .font(.subheadline)
                .fontWeight(.semibold)
                .foregroundColor(.white.opacity(0.7))

            HStack(spacing: 8) {
                ForEach(1...5, id: \.self) { star in
                    Image(systemName: star <= displayRating ? "star.fill" : "star")
                        .font(.title2)
                        .foregroundColor(star <= displayRating ? .yellow : .white.opacity(0.3))
                        .contentTransition(.symbolEffect(.replace))
                        .onTapGesture {
                            withAnimation(.easeInOut(duration: 0.15)) {
                                if currentRating == star {
                                    currentRating = 0
                                    UserRatingManager.shared.removeRating(for: mediaId)
                                } else {
                                    currentRating = star
                                    UserRatingManager.shared.setRating(star, for: mediaId)
                                }
                            }
                        }
                }

                if currentRating > 0 {
                    Text("\(currentRating)/5")
                        .font(.caption)
                        .foregroundColor(.white.opacity(0.5))
                        .padding(.leading, 4)
                }
            }
        }
        .padding(.horizontal)
        .padding(.top, 8)
        .onAppear {
            currentRating = UserRatingManager.shared.rating(for: mediaId) ?? 0
        }
    }

    private var displayRating: Int {
        highlightedRating > 0 ? highlightedRating : currentRating
    }
}
