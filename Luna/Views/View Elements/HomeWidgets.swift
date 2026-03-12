//
//  HomeWidgets.swift
//  Luna
//
//  Forward-style discover widgets for the home page.
//

import SwiftUI
import Kingfisher

// MARK: - Network Section Widget

struct NetworkSectionWidget: View {
    let widgetData: [String: [TMDBSearchResult]]
    let tmdbService: TMDBService
    
    private let networks = WidgetNetwork.curated
    
    var body: some View {
        let availableNetworks = networks.filter { network in
            let items = widgetData["network_\(network.id)"] ?? []
            return !items.isEmpty
        }
        
        if !availableNetworks.isEmpty {
            VStack(alignment: .leading, spacing: 16) {
                Text("Network")
                    .font(.title2)
                    .fontWeight(.bold)
                    .foregroundColor(.white)
                    .padding(.horizontal, 16)
                
                ScrollView(.horizontal, showsIndicators: false) {
                    LazyHStack(spacing: 16) {
                        ForEach(availableNetworks) { network in
                            let items = widgetData["network_\(network.id)"] ?? []
                            NavigationLink(destination: DiscoverDetailView(
                                title: network.name,
                                initialItems: items,
                                loadMore: { page in
                                    (try? await tmdbService.discoverByNetwork(networkId: network.id, page: page)) ?? []
                                }
                            )) {
                                networkCard(network: network, items: items)
                            }
                            .buttonStyle(PlainButtonStyle())
                        }
                    }
                    .padding(.horizontal, 16)
                }
                .modifier(ScrollClipModifier())
            }
            .padding(.top, 24)
        }
    }
    
    @ViewBuilder
    private func networkCard(network: WidgetNetwork, items: [TMDBSearchResult]) -> some View {
        ZStack(alignment: .leading) {
            // Poster collage on the right
            HStack(spacing: -20) {
                Spacer()
                ForEach(Array(items.prefix(3).enumerated()), id: \.element.id) { index, item in
                    KFImage(URL(string: item.fullPosterURL ?? ""))
                        .placeholder { Color.gray.opacity(0.3) }
                        .resizable()
                        .aspectRatio(2/3, contentMode: .fill)
                        .frame(width: 80, height: 120)
                        .clipShape(RoundedRectangle(cornerRadius: 10))
                        .rotationEffect(.degrees(Double(index - 1) * 5))
                        .offset(y: index == 1 ? -5 : 5)
                }
            }
            .padding(.trailing, 12)
            .padding(.vertical, 12)
            
            // Network name on the left
            VStack(alignment: .leading, spacing: 6) {
                Text(network.name)
                    .font(.title2)
                    .fontWeight(.heavy)
                    .foregroundColor(.white)
                    .shadow(color: .black.opacity(0.5), radius: 4, x: 0, y: 2)
            }
            .padding(.leading, 16)
        }
        .frame(width: isIPad ? 320 : 260, height: 160)
        .background(
            LinearGradient(
                colors: [Color.white.opacity(0.12), Color.white.opacity(0.04)],
                startPoint: .topLeading,
                endPoint: .bottomTrailing
            )
        )
        .clipShape(RoundedRectangle(cornerRadius: 16))
        .overlay(
            RoundedRectangle(cornerRadius: 16)
                .stroke(Color.white.opacity(0.1), lineWidth: 0.5)
        )
    }
}

// MARK: - Genre/Category Section Widget

struct GenreSectionWidget: View {
    let widgetData: [String: [TMDBSearchResult]]
    let tmdbService: TMDBService
    
    private let genres = WidgetGenre.curated
    private let columns = [
        GridItem(.flexible(), spacing: 12),
        GridItem(.flexible(), spacing: 12)
    ]
    
    var body: some View {
        let availableGenres = genres.filter { genre in
            let items = widgetData["genre_\(genre.id)"] ?? []
            return !items.isEmpty
        }
        
        if !availableGenres.isEmpty {
            VStack(alignment: .leading, spacing: 16) {
                Text("Category")
                    .font(.title2)
                    .fontWeight(.bold)
                    .foregroundColor(.white)
                    .padding(.horizontal, 16)
                
                LazyVGrid(columns: columns, spacing: 12) {
                    ForEach(Array(availableGenres.prefix(6))) { genre in
                        let items = widgetData["genre_\(genre.id)"] ?? []
                        NavigationLink(destination: DiscoverDetailView(
                            title: genre.name,
                            initialItems: items,
                            loadMore: { page in
                                (try? await tmdbService.discoverByGenre(genreId: genre.id, page: page)) ?? []
                            }
                        )) {
                            genreCard(genre: genre, items: items)
                        }
                        .buttonStyle(PlainButtonStyle())
                    }
                }
                .padding(.horizontal, 16)
            }
            .padding(.top, 24)
        }
    }
    
    @ViewBuilder
    private func genreCard(genre: WidgetGenre, items: [TMDBSearchResult]) -> some View {
        HStack(spacing: 0) {
            // Poster thumbnail
            if let posterURL = items.first?.fullPosterURL {
                KFImage(URL(string: posterURL))
                    .placeholder { Color.gray.opacity(0.3) }
                    .resizable()
                    .aspectRatio(2/3, contentMode: .fill)
                    .frame(width: 60, height: 80)
                    .clipShape(RoundedRectangle(cornerRadius: 8))
                    .padding(.leading, 10)
                    .padding(.vertical, 10)
            }
            
            Spacer()
            
            Text(genre.name)
                .font(.subheadline)
                .fontWeight(.bold)
                .foregroundColor(.white)
                .lineLimit(1)
                .padding(.trailing, 14)
        }
        .frame(maxWidth: .infinity)
        .frame(height: 80)
        .background(
            LinearGradient(
                colors: [Color.yellow.opacity(0.15), Color.orange.opacity(0.08)],
                startPoint: .topLeading,
                endPoint: .bottomTrailing
            )
        )
        .clipShape(RoundedRectangle(cornerRadius: 14))
        .overlay(
            RoundedRectangle(cornerRadius: 14)
                .stroke(Color.white.opacity(0.08), lineWidth: 0.5)
        )
    }
}

// MARK: - Company Section Widget

struct CompanySectionWidget: View {
    let widgetData: [String: [TMDBSearchResult]]
    let tmdbService: TMDBService
    
    private let companies = WidgetCompany.curated
    private let columns = [
        GridItem(.flexible(), spacing: 12),
        GridItem(.flexible(), spacing: 12)
    ]
    
    var body: some View {
        let availableCompanies = companies.filter { company in
            let items = widgetData["company_\(company.id)"] ?? []
            return !items.isEmpty
        }
        
        if !availableCompanies.isEmpty {
            VStack(alignment: .leading, spacing: 16) {
                Text("Company")
                    .font(.title2)
                    .fontWeight(.bold)
                    .foregroundColor(.white)
                    .padding(.horizontal, 16)
                
                LazyVGrid(columns: columns, spacing: 12) {
                    ForEach(Array(availableCompanies.prefix(4))) { company in
                        let items = widgetData["company_\(company.id)"] ?? []
                        NavigationLink(destination: DiscoverDetailView(
                            title: company.name,
                            initialItems: items,
                            loadMore: { page in
                                (try? await tmdbService.discoverByCompany(companyId: company.id, page: page)) ?? []
                            }
                        )) {
                            companyCard(company: company, items: items)
                        }
                        .buttonStyle(PlainButtonStyle())
                    }
                }
                .padding(.horizontal, 16)
            }
            .padding(.top, 24)
        }
    }
    
    @ViewBuilder
    private func companyCard(company: WidgetCompany, items: [TMDBSearchResult]) -> some View {
        ZStack {
            // Backdrop from first item
            if let backdropURL = items.first?.fullBackdropURL {
                KFImage(URL(string: backdropURL))
                    .placeholder { Color.gray.opacity(0.15) }
                    .resizable()
                    .aspectRatio(contentMode: .fill)
                    .frame(height: 100)
                    .clipped()
                    .overlay(Color.black.opacity(0.55))
            } else {
                Color.white.opacity(0.06)
            }
            
            Text(company.name)
                .font(.headline)
                .fontWeight(.heavy)
                .foregroundColor(.white)
                .shadow(color: .black.opacity(0.6), radius: 4, x: 0, y: 2)
        }
        .frame(maxWidth: .infinity)
        .frame(height: 100)
        .clipShape(RoundedRectangle(cornerRadius: 14))
        .overlay(
            RoundedRectangle(cornerRadius: 14)
                .stroke(Color.white.opacity(0.08), lineWidth: 0.5)
        )
    }
}

// MARK: - Ranked List Widget

struct RankedListWidget: View {
    let catalogId: String
    let title: String
    let items: [TMDBSearchResult]
    let tmdbService: TMDBService
    
    var body: some View {
        if !items.isEmpty {
            ScrollView(.horizontal, showsIndicators: false) {
                LazyHStack(spacing: 16) {
                    NavigationLink(destination: DiscoverDetailView(
                        title: title,
                        initialItems: items
                    )) {
                        rankedCard(title: title, items: items)
                    }
                    .buttonStyle(PlainButtonStyle())
                }
                .padding(.horizontal, 16)
            }
            .modifier(ScrollClipModifier())
            .padding(.top, 24)
        }
    }
    
    @ViewBuilder
    private func rankedCard(title: String, items: [TMDBSearchResult]) -> some View {
        VStack(alignment: .leading, spacing: 0) {
            // Top: poster collage
            HStack(spacing: 4) {
                ForEach(Array(items.prefix(3).enumerated()), id: \.element.id) { _, item in
                    KFImage(URL(string: item.fullPosterURL ?? ""))
                        .placeholder { Color.gray.opacity(0.3) }
                        .resizable()
                        .aspectRatio(2/3, contentMode: .fill)
                        .frame(maxWidth: .infinity)
                        .frame(height: 140)
                        .clipped()
                }
            }
            .clipShape(RoundedRectangle(cornerRadius: 10))
            .padding(.horizontal, 12)
            .padding(.top, 12)
            
            // Laurel-decorated title
            HStack(spacing: 6) {
                Image(systemName: "laurel.leading")
                    .font(.caption)
                    .foregroundColor(.yellow.opacity(0.7))
                
                Text(title)
                    .font(.headline)
                    .fontWeight(.bold)
                    .foregroundColor(.white)
                    .lineLimit(1)
                
                Image(systemName: "laurel.trailing")
                    .font(.caption)
                    .foregroundColor(.yellow.opacity(0.7))
            }
            .padding(.top, 12)
            .padding(.horizontal, 12)
            
            // Numbered list (top 3)
            VStack(alignment: .leading, spacing: 6) {
                ForEach(Array(items.prefix(3).enumerated()), id: \.element.id) { index, item in
                    HStack(spacing: 8) {
                        Text("\(index + 1)")
                            .font(.subheadline)
                            .fontWeight(.heavy)
                            .foregroundColor(.yellow.opacity(0.8))
                            .frame(width: 20)
                        
                        Text(item.displayTitle)
                            .font(.subheadline)
                            .foregroundColor(.white.opacity(0.9))
                            .lineLimit(1)
                    }
                }
            }
            .padding(.horizontal, 16)
            .padding(.top, 10)
            .padding(.bottom, 14)
        }
        .frame(width: isIPad ? 320 : 280)
        .background(
            LinearGradient(
                colors: [Color.white.opacity(0.1), Color.white.opacity(0.04)],
                startPoint: .top,
                endPoint: .bottom
            )
        )
        .clipShape(RoundedRectangle(cornerRadius: 16))
        .overlay(
            RoundedRectangle(cornerRadius: 16)
                .stroke(Color.white.opacity(0.1), lineWidth: 0.5)
        )
    }
}

// MARK: - Featured Spotlight Widget

struct FeaturedSpotlightWidget: View {
    let widgetData: [String: [TMDBSearchResult]]
    let genreName: String
    let tmdbService: TMDBService
    
    var body: some View {
        let items = widgetData["featured"] ?? []
        
        if !items.isEmpty {
            VStack(alignment: .leading, spacing: 16) {
                // Main spotlight banner
                if let spotlight = items.first {
                    NavigationLink(destination: DiscoverDetailView(
                        title: "Popular \u{00B7} \(genreName)",
                        initialItems: items,
                        heroItem: spotlight,
                        loadMore: { page in
                            guard let genre = WidgetGenre.curated.first(where: { $0.name == genreName }) else { return [] }
                            return (try? await tmdbService.discoverByGenre(genreId: genre.id, mediaType: "tv", page: page)) ?? []
                        }
                    )) {
                        spotlightBanner(spotlight: spotlight)
                    }
                    .buttonStyle(PlainButtonStyle())
                }
                
                // Small cards row below
                ScrollView(.horizontal, showsIndicators: false) {
                    LazyHStack(spacing: 14) {
                        ForEach(Array(items.dropFirst().prefix(8))) { item in
                            NavigationLink(destination: MediaDetailView(searchResult: item)) {
                                spotlightSmallCard(item: item)
                            }
                            .buttonStyle(PlainButtonStyle())
                        }
                    }
                    .padding(.horizontal, 16)
                }
                .modifier(ScrollClipModifier())
            }
            .padding(.top, 24)
        }
    }
    
    @ViewBuilder
    private func spotlightBanner(spotlight: TMDBSearchResult) -> some View {
        ZStack(alignment: .bottomLeading) {
            // Large backdrop
            KFImage(URL(string: spotlight.fullBackdropURL ?? spotlight.fullPosterURL ?? ""))
                .placeholder {
                    Rectangle().fill(Color.gray.opacity(0.2))
                }
                .resizable()
                .aspectRatio(16/9, contentMode: .fill)
                .frame(height: 200)
                .clipped()
            
            // Gradient overlay
            LinearGradient(
                colors: [.clear, .black.opacity(0.7), .black.opacity(0.9)],
                startPoint: .top,
                endPoint: .bottom
            )
            
            // Content overlay
            VStack(alignment: .leading, spacing: 6) {
                // Laurel-decorated genre title
                HStack(spacing: 6) {
                    Image(systemName: "laurel.leading")
                        .font(.caption)
                        .foregroundColor(.yellow.opacity(0.8))
                    
                    Text("Popular \u{00B7} \(genreName)")
                        .font(.headline)
                        .fontWeight(.bold)
                        .foregroundColor(.white)
                    
                    Image(systemName: "laurel.trailing")
                        .font(.caption)
                        .foregroundColor(.yellow.opacity(0.8))
                }
                
                Text(spotlight.displayTitle)
                    .font(.caption)
                    .foregroundColor(.white.opacity(0.7))
            }
            .padding(16)
        }
        .frame(maxWidth: .infinity)
        .frame(height: 200)
        .clipShape(RoundedRectangle(cornerRadius: 16))
        .overlay(
            RoundedRectangle(cornerRadius: 16)
                .stroke(Color.white.opacity(0.1), lineWidth: 0.5)
        )
        .padding(.horizontal, 16)
    }
    
    @ViewBuilder
    private func spotlightSmallCard(item: TMDBSearchResult) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            KFImage(URL(string: item.fullPosterURL ?? ""))
                .placeholder {
                    FallbackImageView(
                        isMovie: item.isMovie,
                        size: CGSize(width: 120, height: 180)
                    )
                }
                .resizable()
                .aspectRatio(2/3, contentMode: .fill)
                .frame(width: 120 * iPadScale, height: 180 * iPadScale)
                .clipShape(RoundedRectangle(cornerRadius: 12))
                .shadow(color: .black.opacity(0.25), radius: 6, x: 0, y: 3)
            
            Text(item.displayTitle)
                .font(.caption)
                .fontWeight(.medium)
                .foregroundColor(.white)
                .lineLimit(1)
                .frame(width: 120 * iPadScale, alignment: .leading)
            
            HStack(spacing: 4) {
                if !item.displayDate.isEmpty {
                    let date = item.displayDate
                    Text(String(date.prefix(10)))
                        .font(.caption2)
                        .foregroundColor(.white.opacity(0.6))
                }
            }
            .frame(width: 120 * iPadScale, alignment: .leading)
        }
    }
}
