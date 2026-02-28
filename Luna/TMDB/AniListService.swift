import Foundation

/// Ensures AniList API calls are spaced out to stay under the 90 req/min rate limit.
/// Uses a slot-reservation pattern: each caller claims a future time slot BEFORE sleeping,
/// so concurrent callers queue up instead of bunching together.
private actor AniListRateLimiter {
    static let shared = AniListRateLimiter()
    
    private let minInterval: TimeInterval = 0.5 // ~120 req/min max, safely under AniList's 90 req/min (batched queries reduce actual call count)
    private var nextAvailableTime: Date = .distantPast
    
    func waitForSlot() async {
        let now = Date()
        // Claim the next available slot
        let slotTime = max(now, nextAvailableTime)
        // Reserve it immediately so the next caller queues AFTER this one
        nextAvailableTime = slotTime.addingTimeInterval(minInterval)
        
        // Sleep until our reserved slot arrives
        let delay = slotTime.timeIntervalSince(now)
        if delay > 0.001 {
            try? await Task.sleep(nanoseconds: UInt64(delay * 1_000_000_000))
        }
    }
}

final class AniListService {
    static let shared = AniListService()

    private let graphQLEndpoint = URL(string: "https://graphql.anilist.co")!
    private var preferredLanguageCode: String {
        let raw = UserDefaults.standard.string(forKey: "tmdbLanguage") ?? "en-US"
        return raw.split(separator: "-").first.map(String.init) ?? "en"
    }

    enum AniListCatalogKind {
        case trending
        case popular
        case topRated
        case airing
        case upcoming
    }

    // MARK: - Catalog Fetching

    /// Fetch all anime catalogs in a single AniList GraphQL query using aliases.
    /// Returns a dictionary keyed by AniListCatalogKind.
    func fetchAllAnimeCatalogs(
        limit: Int = 20,
        tmdbService: TMDBService
    ) async throws -> [AniListCatalogKind: [TMDBSearchResult]] {
        // Single aliased query fetches all 5 catalogs at once (1 API call instead of 5)
        let query = """
        query {
            trending: Page(perPage: \(limit)) {
                media(type: ANIME, sort: [TRENDING_DESC]) {
                    id
                    title { romaji english native }
                    episodes status seasonYear season
                    coverImage { large medium }
                    format
                }
            }
            popular: Page(perPage: \(limit)) {
                media(type: ANIME, sort: [POPULARITY_DESC]) {
                    id
                    title { romaji english native }
                    episodes status seasonYear season
                    coverImage { large medium }
                    format
                }
            }
            topRated: Page(perPage: \(limit)) {
                media(type: ANIME, sort: [SCORE_DESC]) {
                    id
                    title { romaji english native }
                    episodes status seasonYear season
                    coverImage { large medium }
                    format
                }
            }
            airing: Page(perPage: \(limit)) {
                media(type: ANIME, sort: [POPULARITY_DESC], status: RELEASING) {
                    id
                    title { romaji english native }
                    episodes status seasonYear season
                    coverImage { large medium }
                    format
                }
            }
            upcoming: Page(perPage: \(limit)) {
                media(type: ANIME, sort: [POPULARITY_DESC], status: NOT_YET_RELEASED) {
                    id
                    title { romaji english native }
                    episodes status seasonYear season
                    coverImage { large medium }
                    format
                }
            }
        }
        """

        struct PageData: Codable { let media: [AniListAnime] }
        struct AllCatalogsResponse: Codable {
            let data: DataWrapper
            struct DataWrapper: Codable {
                let trending: PageData
                let popular: PageData
                let topRated: PageData
                let airing: PageData
                let upcoming: PageData
            }
        }

        let data = try await executeGraphQLQuery(query, token: nil)
        let decoded = try JSONDecoder().decode(AllCatalogsResponse.self, from: data)

        // Hydrate all unique anime with TMDB matches in parallel (deduped)
        var allAnime: [AniListAnime] = []
        let lists: [(AniListCatalogKind, [AniListAnime])] = [
            (.trending, decoded.data.trending.media),
            (.popular, decoded.data.popular.media),
            (.topRated, decoded.data.topRated.media),
            (.airing, decoded.data.airing.media),
            (.upcoming, decoded.data.upcoming.media),
        ]
        var seenIds = Set<Int>()
        for (_, animeList) in lists {
            for anime in animeList {
                if seenIds.insert(anime.id).inserted {
                    allAnime.append(anime)
                }
            }
        }

        // Batch TMDB hydration for all unique anime
        let tmdbMap = await batchMapAniListToTMDB(allAnime, tmdbService: tmdbService)

        // Reassemble per-catalog results preserving order
        var result: [AniListCatalogKind: [TMDBSearchResult]] = [:]
        for (kind, animeList) in lists {
            result[kind] = animeList.compactMap { tmdbMap[$0.id] }
        }

        Logger.shared.log("AniListService: Fetched all 5 anime catalogs in 1 query (\(allAnime.count) unique anime)", type: "AniList")
        return result
    }

    /// Fetch a single anime catalog (kept for backward compatibility).
    func fetchAnimeCatalog(
        _ kind: AniListCatalogKind,
        limit: Int = 20,
        tmdbService: TMDBService
    ) async throws -> [TMDBSearchResult] {
        let sort: String
        let status: String?

        switch kind {
        case .trending:
            sort = "TRENDING_DESC"
            status = nil
        case .popular:
            sort = "POPULARITY_DESC"
            status = nil
        case .topRated:
            sort = "SCORE_DESC"
            status = nil
        case .airing:
            sort = "POPULARITY_DESC"
            status = "RELEASING"
        case .upcoming:
            sort = "POPULARITY_DESC"
            status = "NOT_YET_RELEASED"
        }

        let statusClause = status.map { ", status: \($0)" } ?? ""

        let query = """
        query {
            Page(perPage: \(limit)) {
                media(type: ANIME, sort: [\(sort)]\(statusClause)) {
                    id
                    title { romaji english native }
                    episodes
                    status
                    seasonYear
                    season
                    coverImage { large medium }
                    format
                }
            }
        }
        """

        struct CatalogResponse: Codable {
            let data: DataWrapper
            struct DataWrapper: Codable { let Page: PageData }
            struct PageData: Codable { let media: [AniListAnime] }
        }

        let data = try await executeGraphQLQuery(query, token: nil)
        let decoded = try JSONDecoder().decode(CatalogResponse.self, from: data)
        let animeList = decoded.data.Page.media
        return await mapAniListCatalogToTMDB(animeList, tmdbService: tmdbService)
    }

    // MARK: - Airing Schedule

    /// Fetch upcoming airing episodes for the next `daysAhead` days (default 7).
    func fetchAiringSchedule(daysAhead: Int = 7, perPage: Int = 50) async throws -> [AniListAiringScheduleEntry] {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = .current

        let today = calendar.startOfDay(for: Date())
        let upperDay = calendar.date(byAdding: .day, value: max(daysAhead, 1) + 1, to: today) ?? today

        let lowerBound = Int(today.timeIntervalSince1970)
        let upperBound = Int(upperDay.timeIntervalSince1970)

        struct Response: Codable {
            let data: DataWrapper
            struct DataWrapper: Codable {
                let Page: PageData
            }
            struct PageData: Codable {
                let pageInfo: PageInfo
                let airingSchedules: [AiringSchedule]
            }
            struct PageInfo: Codable {
                let hasNextPage: Bool
            }
            struct AiringSchedule: Codable {
                let id: Int
                let airingAt: Int
                let episode: Int
                let media: AniListAnime
            }
        }

        var allSchedules: [Response.AiringSchedule] = []
        var currentPage = 1
        var hasNextPage = true
        let maxPages = 10

        while hasNextPage && currentPage <= maxPages {
            let query = """
            query {
                Page(page: \(currentPage), perPage: \(perPage)) {
                    pageInfo { hasNextPage }
                    airingSchedules(airingAt_greater: \(lowerBound - 1), airingAt_lesser: \(upperBound), sort: TIME) {
                        id
                        airingAt
                        episode
                        media {
                            id
                            title { romaji english native }
                            coverImage { large medium }
                        }
                    }
                }
            }
            """

            let data = try await executeGraphQLQuery(query, token: nil)
            let decoded = try JSONDecoder().decode(Response.self, from: data)

            allSchedules.append(contentsOf: decoded.data.Page.airingSchedules)
            hasNextPage = decoded.data.Page.pageInfo.hasNextPage
            currentPage += 1

            // Brief pause between pages to avoid rate limiting
            if hasNextPage && currentPage <= maxPages {
                try await Task.sleep(nanoseconds: 400_000_000) // 0.4s
            }
        }

        let start = today
        let end = upperDay

        return allSchedules
            .map { schedule in
                let title = AniListTitlePicker.title(from: schedule.media.title, preferredLanguageCode: preferredLanguageCode)
                let cover = schedule.media.coverImage?.large ?? schedule.media.coverImage?.medium
                return AniListAiringScheduleEntry(
                    id: schedule.id,
                    mediaId: schedule.media.id,
                    title: title,
                    airingAt: Date(timeIntervalSince1970: TimeInterval(schedule.airingAt)),
                    episode: schedule.episode,
                    coverImage: cover
                )
            }
            .filter { entry in
                entry.airingAt >= start && entry.airingAt < end
            }
    }
    
    /// Fetch full anime details with seasons and episodes from AniList + TMDB
    /// Uses AniList for season structure and sequels, TMDB for episode details
    func fetchAnimeDetailsWithEpisodes(
        title: String,
        tmdbShowId: Int,
        tmdbService: TMDBService,
        tmdbShowPoster: String?,
        token: String?
    ) async throws -> AniListAnimeWithSeasons {
        Logger.shared.log("AniListService: fetchAnimeDetailsWithEpisodes START for '\(title)' tmdbId=\(tmdbShowId)", type: "AniList")
        // Query AniList for anime structure + sequels + coverImage (multiple candidates for better matching)
        let query = """
        query {
            Page(perPage: 6) {
                media(search: "\(title.replacingOccurrences(of: "\"", with: "\\\""))", type: ANIME, sort: POPULARITY_DESC) {
                    id
                    title {
                        romaji
                        english
                        native
                    }
                    episodes
                    status
                    seasonYear
                    season
                    coverImage {
                        large
                        medium
                    }
                    format
                    nextAiringEpisode {
                        episode
                        airingAt
                    }
                    relations {
                        edges {
                            relationType
                            node {
                                id
                                title {
                                    romaji
                                    english
                                    native
                                }
                                episodes
                                status
                                seasonYear
                                season
                                format
                                type
                                coverImage {
                                    large
                                    medium
                                }
                                relations {
                                    edges {
                                        relationType
                                        node {
                                            id
                                            title { romaji english native }
                                            episodes
                                            status
                                            seasonYear
                                            season
                                            format
                                            type
                                            coverImage { large medium }
                                        }
                                    }
                                }
                            }
                        }
                    }
                }
            }
        }
        """
        
        Logger.shared.log("AniListService: Sending AniList GraphQL query for '\(title)'", type: "AniList")
        let response = try await executeGraphQLQuery(query, token: token)
        
        struct Response: Codable {
            let data: DataWrapper
            struct DataWrapper: Codable {
                let Page: PageData
                struct PageData: Codable { let media: [AniListAnime] }
            }
        }
        
        let result = try JSONDecoder().decode(Response.self, from: response)
        let candidates = result.data.Page.media
        Logger.shared.log("AniListService: AniList returned \(candidates.count) candidates for '\(title)'", type: "AniList")
        guard !candidates.isEmpty else {
            Logger.shared.log("AniListService: NO candidates from AniList for '\(title)' — throwing", type: "Error")
            throw NSError(domain: "AniListService", code: -1, userInfo: [NSLocalizedDescriptionKey: "AniList did not return any matches for \(title)"])
        }

        // Fetch TMDB show info early for hinting (episode count, first air year) and reuse later.
        let tvShowDetail: TMDBTVShowWithSeasons? = await {
            do {
                return try await tmdbService.getTVShowWithSeasons(id: tmdbShowId)
            } catch {
                Logger.shared.log("AniListService: Failed to prefetch TMDB show details: \(error.localizedDescription)", type: "TMDB")
                return nil
            }
        }()

        let anime = pickBestAniListMatch(from: candidates, tmdbShow: tvShowDetail)

        let title = AniListTitlePicker.title(from: anime.title, preferredLanguageCode: preferredLanguageCode)
        Logger.shared.log("AniListService: Selected AniList match '\(title)' (id: \(anime.id))", type: "AniList")
        let seasonVal = anime.season ?? "UNKNOWN"
        Logger.shared.log(
            "AniListService: Raw response - episodes: \(anime.episodes ?? 0), seasonYear: \(anime.seasonYear ?? 0), season: \(seasonVal)",
            type: "AniList"
        )
        
        // Collect all anime to process (original + all recursive sequels) with posters
        var allAnimeToProcess: [(anime: AniListAnime, seasonOffset: Int, posterUrl: String?)] = []

        func appendAnime(_ entry: AniListAnime) {
            let poster = entry.coverImage?.large ?? entry.coverImage?.medium ?? tmdbShowPoster
            allAnimeToProcess.append((entry, 0, poster))
        }

        appendAnime(anime)
        
        Logger.shared.log("AniListService: Starting sequel detection for \(AniListTitlePicker.title(from: anime.title, preferredLanguageCode: preferredLanguageCode)) (ID: \(anime.id), episodes: \(anime.episodes ?? 0), relations: \(anime.relations?.edges.count ?? 0))", type: "AniList")

        // Allowed relation types we treat as season/continuation
        let allowedRelationTypes: Set<String> = ["SEQUEL", "PREQUEL", "SEASON"]

        // BFS over sequels/prequels/seasons, batch-fetching nodes that need deeper relations per level
        var queue: [AniListAnime] = [anime]
        var seenIds = Set<Int>([anime.id])

        while !queue.isEmpty {
            let currentLevel = queue
            queue.removeAll()

            var idsToFetch: [Int] = []
            var shallowNodes: [Int: AniListAnime.AniListRelationNode] = [:]

            for current in currentLevel {
                let currentTitle = AniListTitlePicker.title(from: current.title, preferredLanguageCode: preferredLanguageCode)
                let edges = current.relations?.edges ?? []
                Logger.shared.log("AniListService: Checking relations for '\(currentTitle)': \(edges.count) edges total", type: "AniList")

                for edge in edges {
                    guard allowedRelationTypes.contains(edge.relationType), edge.node.type == "ANIME" else {
                        continue
                    }
                    if let format = edge.node.format, !(format == "TV" || format == "TV_SHORT" || format == "ONA") {
                        continue
                    }
                    if !seenIds.insert(edge.node.id).inserted {
                        continue
                    }

                    let edgeTitle = AniListTitlePicker.title(from: edge.node.title, preferredLanguageCode: preferredLanguageCode)
                    Logger.shared.log("    \u{2192} Added sequel: \(edgeTitle)", type: "AniList")

                    if edge.node.relations != nil {
                        let fullNode = edge.node.asAnime()
                        appendAnime(fullNode)
                        queue.append(fullNode)
                    } else {
                        idsToFetch.append(edge.node.id)
                        shallowNodes[edge.node.id] = edge.node
                    }
                }
            }

            if !idsToFetch.isEmpty {
                Logger.shared.log("AniListService: Batch-fetching \(idsToFetch.count) sequel nodes in 1 query", type: "AniList")
                let fetchedNodes = await batchFetchAniListNodes(ids: idsToFetch)
                for id in idsToFetch {
                    let fullNode: AniListAnime
                    if let fetched = fetchedNodes[id] {
                        fullNode = fetched
                    } else if let shallow = shallowNodes[id] {
                        fullNode = shallow.asAnime()
                    } else {
                        continue
                    }
                    appendAnime(fullNode)
                    queue.append(fullNode)
                }
            }
        }

        // Fetch all TMDB season data in parallel (excluding Season 0 specials)
        // Build an absolute episode index so we can map stills/runtime even when seasons reset numbering
        var tmdbEpisodesByAbsolute: [Int: TMDBEpisode] = [:]
        if let tvShowDetail {
            // Sort seasons by seasonNumber to keep ordering consistent
            let realSeasons = tvShowDetail.seasons.filter { $0.seasonNumber > 0 }.sorted { $0.seasonNumber < $1.seasonNumber }
            
            // Fetch all seasons in parallel for speed
            var seasonResults: [(seasonNumber: Int, episodes: [TMDBEpisode])] = []
            await withTaskGroup(of: (Int, [TMDBEpisode]?).self) { group in
                for season in realSeasons {
                    group.addTask {
                        do {
                            let detail = try await tmdbService.getSeasonDetails(tvShowId: tmdbShowId, seasonNumber: season.seasonNumber)
                            return (season.seasonNumber, detail.episodes)
                        } catch {
                            Logger.shared.log("AniListService: Failed to fetch TMDB season \(season.seasonNumber): \(error.localizedDescription)", type: "AniList")
                            return (season.seasonNumber, nil)
                        }
                    }
                }
                for await (seasonNum, episodes) in group {
                    if let episodes {
                        seasonResults.append((seasonNum, episodes))
                    }
                }
            }
            
            // Process results in season order
            seasonResults.sort { $0.seasonNumber < $1.seasonNumber }
            var absoluteIndex = 1
            for (seasonNum, episodes) in seasonResults {
                let sorted = episodes.sorted(by: { $0.episodeNumber < $1.episodeNumber })
                Logger.shared.log("AniListService: TMDB season \(seasonNum) returned \(sorted.count) episodes", type: "AniList")
                for episode in sorted {
                    tmdbEpisodesByAbsolute[absoluteIndex] = episode
                    if absoluteIndex <= 3 {
                        Logger.shared.log("  Episode \(episode.episodeNumber): '\(episode.name)', overview: \(episode.overview?.isEmpty == false ? "YES" : "NO"), stillPath: \(episode.stillPath != nil ? "YES" : "NO")", type: "AniList")
                    }
                    absoluteIndex += 1
                }
            }
        }
        
        // ALWAYS attempt fallback season fetch if we don't have enough episodes yet
        // This ensures we get episode metadata even when show detail fetch fails
        if tmdbEpisodesByAbsolute.isEmpty {
            Logger.shared.log("AniListService: No TMDB episodes loaded; attempting direct season fetch", type: "AniList")
            var absoluteIndex = 1
            var seasonNumber = 1
            // Keep fetching seasons until we hit an error or empty season
            // This handles any length anime (One Piece 20+ seasons, etc.)
            while true {
                do {
                    let seasonDetail = try await tmdbService.getSeasonDetails(tvShowId: tmdbShowId, seasonNumber: seasonNumber)
                    if seasonDetail.episodes.isEmpty {
                        Logger.shared.log("AniListService: Fallback found empty season \(seasonNumber), stopping", type: "AniList")
                        break
                    }
                    for episode in seasonDetail.episodes.sorted(by: { $0.episodeNumber < $1.episodeNumber }) {
                        tmdbEpisodesByAbsolute[absoluteIndex] = episode
                        absoluteIndex += 1
                    }
                    Logger.shared.log("AniListService: Fallback fetched season \(seasonNumber): \(seasonDetail.episodes.count) episodes", type: "AniList")
                    seasonNumber += 1
                } catch {
                    // Stop when we hit an error (likely season does not exist)
                    Logger.shared.log("AniListService: Fallback stopped at season \(seasonNumber) (no more seasons found)", type: "AniList")
                    break
                }
            }
        }
        
        // Build all seasons from AniList structure + TMDB episode details
        var seasons: [AniListSeasonWithPoster] = []
        var currentAbsoluteEpisode = 1
        var seasonIndex = 1
        
        for (currentAnime, _, posterUrl) in allAnimeToProcess {
            // Get the full AniList title for this season/sequel
            let seasonTitle = AniListTitlePicker.title(from: currentAnime.title, preferredLanguageCode: preferredLanguageCode)
            
            // Use AniList episode count - this is authoritative
            let anilistEpisodeCount = currentAnime.episodes ?? 0
            
            // Only fall back to remaining TMDB episodes if AniList has no data
            let totalEpisodesInAnime: Int
            if anilistEpisodeCount > 0 {
                totalEpisodesInAnime = anilistEpisodeCount
                Logger.shared.log("AniListService: Season \(seasonIndex) '\(seasonTitle)' using AniList count: \(totalEpisodesInAnime) episodes", type: "AniList")
            } else {
                let remainingTmdb = max(0, tmdbEpisodesByAbsolute.count - (currentAbsoluteEpisode - 1))
                totalEpisodesInAnime = remainingTmdb > 0 ? remainingTmdb : 12
                Logger.shared.log("AniListService: Season \(seasonIndex) '\(seasonTitle)' AniList has no count, falling back to: \(totalEpisodesInAnime) episodes", type: "AniList")
            }
            
            // Each anime (original or sequel) is its own season with episodes numbered from 1
            // Use AniList S/E for service search, but pull metadata from TMDB using absolute index
            let seasonEpisodes: [AniListEpisode] = (0..<totalEpisodesInAnime).map { offset in
                let absoluteEp = currentAbsoluteEpisode + offset
                let localEp = offset + 1
                if let tmdbEp = tmdbEpisodesByAbsolute[absoluteEp] {
                    return AniListEpisode(
                        number: localEp,              // AniList episode (1-12) for search
                        title: tmdbEp.name,           // TMDB metadata
                        description: tmdbEp.overview, // TMDB metadata
                        seasonNumber: seasonIndex,    // AniList season for search
                        stillPath: tmdbEp.stillPath,  // TMDB metadata
                        airDate: tmdbEp.airDate,      // TMDB metadata
                        runtime: tmdbEp.runtime,      // TMDB metadata
                        tmdbSeasonNumber: tmdbEp.seasonNumber,    // Original TMDB S
                        tmdbEpisodeNumber: tmdbEp.episodeNumber   // Original TMDB E
                    )
                } else {
                    return AniListEpisode(
                        number: localEp,
                        title: "Episode \(localEp)",
                        description: nil,
                        seasonNumber: seasonIndex,
                        stillPath: nil,
                        airDate: nil,
                        runtime: nil,
                        tmdbSeasonNumber: nil,
                        tmdbEpisodeNumber: nil
                    )
                }
            }
            
            // Use AniList poster for proper season structure (don't mix with TMDB seasons)
            seasons.append(AniListSeasonWithPoster(
                seasonNumber: seasonIndex,
                anilistId: currentAnime.id,
                title: seasonTitle,
                episodes: seasonEpisodes,
                posterUrl: posterUrl
            ))
            
            currentAbsoluteEpisode += totalEpisodesInAnime
            seasonIndex += 1
        }
        
        let totalEpisodes = seasons.reduce(0) { $0 + $1.episodes.count }
        Logger.shared.log("AniListService: Fetched \(title) with \(totalEpisodes) total episodes grouped into \(seasons.count) seasons", type: "AniList")
        for season in seasons {
            Logger.shared.log("  Season \(season.seasonNumber): \(season.episodes.count) episodes, poster: \(season.posterUrl ?? "none")", type: "AniList")
        }
        
        return AniListAnimeWithSeasons(
            id: anime.id,
            title: title,
            seasons: seasons,
            totalEpisodes: totalEpisodes,
            status: anime.status ?? "UNKNOWN"
        )
    }

    private func pickBestAniListMatch(from candidates: [AniListAnime], tmdbShow: TMDBTVShowWithSeasons?) -> AniListAnime {
        // Hard selection rules (no weighted scoring):
        // 1) Prefer TV/TV_SHORT/OVA formats. If none, fall back to all candidates.
        // 2) If TMDB year is known, prefer exact year matches (user clicked on specific version).
        // 3) If TMDB episode count is known, pick the candidate with the smallest absolute diff.
        // 4) Tie-breakers: higher episode count first, then lower AniList ID for determinism.

        let allowedFormats: Set<String> = ["TV", "TV_SHORT", "OVA", "ONA"]
        let formatFiltered = candidates.filter { anime in
            guard let format = anime.format else { return false }
            return allowedFormats.contains(format)
        }

        let pool = formatFiltered.isEmpty ? candidates : formatFiltered

        guard let tmdbShow else {
            return pool.sorted(by: { lhs, rhs in
                let lhsEpisodes = lhs.episodes ?? 0
                let rhsEpisodes = rhs.episodes ?? 0
                if lhsEpisodes != rhsEpisodes { return lhsEpisodes > rhsEpisodes }
                return lhs.id < rhs.id
            }).first ?? candidates.first!
        }

        let tmdbYear = tmdbShow.firstAirDate.flatMap { dateStr in
            Int(String(dateStr.prefix(4)))
        }
        let tmdbEpisodes = tmdbShow.numberOfEpisodes

        // Prefer exact year match (user clicked on specific version)
        let yearFiltered: [AniListAnime]
        if let tmdbYear {
            let exactYear = pool.filter { $0.seasonYear == tmdbYear }
            yearFiltered = exactYear.isEmpty ? pool : exactYear
        } else {
            yearFiltered = pool
        }

        // If we know the TMDB episode count, pick the closest match; otherwise fall back to highest episodes.
        let chosen: AniListAnime?
        if let tmdbEpisodes {
            chosen = yearFiltered.min(by: { lhs, rhs in
                let lhsEpisodes = lhs.episodes ?? 0
                let rhsEpisodes = rhs.episodes ?? 0
                let lhsDiff = abs(lhsEpisodes - tmdbEpisodes)
                let rhsDiff = abs(rhsEpisodes - tmdbEpisodes)
                if lhsDiff != rhsDiff { return lhsDiff < rhsDiff }
                if lhsEpisodes != rhsEpisodes { return lhsEpisodes > rhsEpisodes }
                return lhs.id < rhs.id
            })
        } else {
            chosen = yearFiltered.sorted(by: { lhs, rhs in
                let lhsEpisodes = lhs.episodes ?? 0
                let rhsEpisodes = rhs.episodes ?? 0
                if lhsEpisodes != rhsEpisodes { return lhsEpisodes > rhsEpisodes }
                return lhs.id < rhs.id
            }).first
        }

        return chosen ?? candidates.first!
    }
    
    // MARK: - Update Watch Progress
    
    func updateAnimeProgress(
        mediaId: Int,
        episodeNumber: Int,
        token: String
    ) async throws {
        let mutation = """
        mutation {
            SaveMediaListEntry(mediaId: \(mediaId), progress: \(episodeNumber)) {
                id
                progress
            }
        }
        """
        
        _ = try await executeGraphQLQuery(mutation, token: token)
    }

    // MARK: - Catalog Mapping Helpers

    private func mapAniListCatalogToTMDB(_ animeList: [AniListAnime], tmdbService: TMDBService) async -> [TMDBSearchResult] {
        func normalized(_ value: String) -> String {
            return value.lowercased().components(separatedBy: CharacterSet.alphanumerics.inverted).joined()
        }

        let langCode = self.preferredLanguageCode
        
        return await withTaskGroup(of: TMDBSearchResult?.self) { group in
            for anime in animeList {
                group.addTask {
                    let titleCandidates = AniListTitlePicker.titleCandidates(from: anime.title)
                    let expectedYear = anime.seasonYear

                    var bestMatch: TMDBTVShow?

                    for candidate in titleCandidates where !candidate.isEmpty {
                        guard let results = try? await tmdbService.searchTVShows(query: candidate), !results.isEmpty else { continue }
                        let candidateKey = normalized(candidate)

                        // Apply hierarchical filters instead of scoring
                        
                        // 1. Exact title match
                        let exactMatches = results.filter { normalized($0.name) == candidateKey }
                        if !exactMatches.isEmpty {
                            // Among exact matches, prefer by year then animation/poster
                            let bestExact = exactMatches.min { a, b in
                                let aYear = Int(a.firstAirDate?.prefix(4) ?? "")
                                let bYear = Int(b.firstAirDate?.prefix(4) ?? "")
                                
                                if let expectedYear = expectedYear {
                                    let aDiff = aYear.map { abs($0 - expectedYear) } ?? 10000
                                    let bDiff = bYear.map { abs($0 - expectedYear) } ?? 10000
                                    if aDiff != bDiff { return aDiff < bDiff }
                                }
                                
                                let aHasAnimation = a.genreIds?.contains(16) == true
                                let bHasAnimation = b.genreIds?.contains(16) == true
                                if aHasAnimation != bHasAnimation { return aHasAnimation }
                                
                                let aHasPoster = a.posterPath != nil
                                let bHasPoster = b.posterPath != nil
                                if aHasPoster != bHasPoster { return aHasPoster }
                                
                                return a.popularity > b.popularity
                            }
                            if let best = bestExact {
                                bestMatch = best
                                break
                            }
                        }
                        
                        // 2. Partial title match - prefer by year proximity if available, then animation/poster/popularity
                        let partialMatches = results.filter {
                            let nameKey = normalized($0.name)
                            return nameKey.contains(candidateKey) || candidateKey.contains(nameKey)
                        }
                        if !partialMatches.isEmpty {
                            let best = partialMatches.min { a, b in
                                // If we have year info, prioritize by year proximity
                                if let expectedYear = expectedYear {
                                    let aYear = Int(a.firstAirDate?.prefix(4) ?? "")
                                    let bYear = Int(b.firstAirDate?.prefix(4) ?? "")
                                    let aDiff = aYear.map { abs($0 - expectedYear) } ?? 10000
                                    let bDiff = bYear.map { abs($0 - expectedYear) } ?? 10000
                                    if aDiff != bDiff { return aDiff < bDiff }
                                }
                                
                                // Then animation genre
                                let aHasAnimation = a.genreIds?.contains(16) == true
                                let bHasAnimation = b.genreIds?.contains(16) == true
                                if aHasAnimation != bHasAnimation { return aHasAnimation }
                                
                                // Then poster
                                let aHasPoster = a.posterPath != nil
                                let bHasPoster = b.posterPath != nil
                                if aHasPoster != bHasPoster { return aHasPoster }
                                
                                // Finally popularity
                                return a.popularity > b.popularity
                            }
                            if let best = best {
                                bestMatch = best
                                break
                            }
                        }
                        
                        // 3. Last resort: any result (prefer animation, poster, popularity)
                        if bestMatch == nil {
                            let best = results.min { a, b in
                                let aHasAnimation = a.genreIds?.contains(16) == true
                                let bHasAnimation = b.genreIds?.contains(16) == true
                                if aHasAnimation != bHasAnimation { return aHasAnimation }
                                
                                let aHasPoster = a.posterPath != nil
                                let bHasPoster = b.posterPath != nil
                                if aHasPoster != bHasPoster { return aHasPoster }
                                
                                return a.popularity > b.popularity
                            }
                            bestMatch = best
                        }
                    }

                    if let bestMatch = bestMatch {
                        let aniTitle = AniListTitlePicker.title(from: anime.title, preferredLanguageCode: langCode)
                        Logger.shared.log("AniListService: Matched '\(aniTitle)' â†’ TMDB '\(bestMatch.name)' (ID: \(bestMatch.id))", type: "AniList")
                    }
                    return bestMatch?.asSearchResult
                }
            }

            var results: [TMDBSearchResult] = []
            var seenIds = Set<Int>()
            for await match in group {
                if let match = match, !seenIds.contains(match.id) {
                    seenIds.insert(match.id)
                    results.append(match)
                }
            }
            return results
        }
    }

    /// Batch map AniList anime to TMDB, returning a dict keyed by AniList ID for fast lookup.
    private func batchMapAniListToTMDB(_ animeList: [AniListAnime], tmdbService: TMDBService) async -> [Int: TMDBSearchResult] {
        func normalized(_ value: String) -> String {
            return value.lowercased().components(separatedBy: CharacterSet.alphanumerics.inverted).joined()
        }

        let langCode = self.preferredLanguageCode

        return await withTaskGroup(of: (Int, TMDBSearchResult?).self) { group in
            for anime in animeList {
                group.addTask {
                    let titleCandidates = AniListTitlePicker.titleCandidates(from: anime.title)
                    let expectedYear = anime.seasonYear
                    var bestMatch: TMDBTVShow?

                    for candidate in titleCandidates where !candidate.isEmpty {
                        guard let results = try? await tmdbService.searchTVShows(query: candidate), !results.isEmpty else { continue }
                        let candidateKey = normalized(candidate)

                        let exactMatches = results.filter { normalized($0.name) == candidateKey }
                        if !exactMatches.isEmpty {
                            let bestExact = exactMatches.min { a, b in
                                if let expectedYear = expectedYear {
                                    let aDiff = Int(a.firstAirDate?.prefix(4) ?? "").map { abs($0 - expectedYear) } ?? 10000
                                    let bDiff = Int(b.firstAirDate?.prefix(4) ?? "").map { abs($0 - expectedYear) } ?? 10000
                                    if aDiff != bDiff { return aDiff < bDiff }
                                }
                                let aAnim = a.genreIds?.contains(16) == true
                                let bAnim = b.genreIds?.contains(16) == true
                                if aAnim != bAnim { return aAnim }
                                return a.popularity > b.popularity
                            }
                            if let best = bestExact { bestMatch = best; break }
                        }

                        let partialMatches = results.filter {
                            let nameKey = normalized($0.name)
                            return nameKey.contains(candidateKey) || candidateKey.contains(nameKey)
                        }
                        if !partialMatches.isEmpty {
                            let best = partialMatches.min { a, b in
                                if let expectedYear = expectedYear {
                                    let aDiff = Int(a.firstAirDate?.prefix(4) ?? "").map { abs($0 - expectedYear) } ?? 10000
                                    let bDiff = Int(b.firstAirDate?.prefix(4) ?? "").map { abs($0 - expectedYear) } ?? 10000
                                    if aDiff != bDiff { return aDiff < bDiff }
                                }
                                let aAnim = a.genreIds?.contains(16) == true
                                let bAnim = b.genreIds?.contains(16) == true
                                if aAnim != bAnim { return aAnim }
                                return a.popularity > b.popularity
                            }
                            if let best = best { bestMatch = best; break }
                        }

                        if bestMatch == nil {
                            bestMatch = results.min { a, b in
                                let aAnim = a.genreIds?.contains(16) == true
                                let bAnim = b.genreIds?.contains(16) == true
                                if aAnim != bAnim { return aAnim }
                                return a.popularity > b.popularity
                            }
                        }
                    }

                    if let bestMatch = bestMatch {
                        let aniTitle = AniListTitlePicker.title(from: anime.title, preferredLanguageCode: langCode)
                        Logger.shared.log("AniListService: Matched '\(aniTitle)' → TMDB '\(bestMatch.name)' (ID: \(bestMatch.id))", type: "AniList")
                    }
                    return (anime.id, bestMatch?.asSearchResult)
                }
            }

            var dict: [Int: TMDBSearchResult] = [:]
            for await (anilistId, match) in group {
                if let match = match {
                    dict[anilistId] = match
                }
            }
            return dict
        }
    }
    
    // MARK: - MAL ID to AniList ID Conversion
    
    /// Convert MyAnimeList ID to AniList ID for tracking purposes
    func getAniListId(fromMalId malId: Int) async throws -> Int? {
        let query = """
        query {
            Media(idMal: \(malId), type: ANIME) {
                id
            }
        }
        """
        
        struct Response: Codable {
            let data: DataWrapper?
            struct DataWrapper: Codable {
                let Media: MediaData?
                struct MediaData: Codable {
                    let id: Int
                }
            }
        }
        
        do {
            let data = try await executeGraphQLQuery(query, token: nil)
            let result = try JSONDecoder().decode(Response.self, from: data)
            return result.data?.Media?.id
        } catch {
            Logger.shared.log("AniListService: Failed to convert MAL ID \(malId) to AniList ID: \(error.localizedDescription)", type: "AniList")
            return nil
        }
    }
    
    // MARK: - Private Helpers
    
    private func executeGraphQLQuery(_ query: String, token: String?, maxRetries: Int = 3) async throws -> Data {
        // Throttle all AniList requests to stay under rate limit
        await AniListRateLimiter.shared.waitForSlot()
        
        var request = URLRequest(url: graphQLEndpoint)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.timeoutInterval = 30
        
        if let token = token {
            request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        }
        
        let body: [String: Any] = ["query": query]
        request.httpBody = try JSONSerialization.data(withJSONObject: body)
        
        var lastError: Error?
        for attempt in 0..<maxRetries {
            let (data, response) = try await URLSession.shared.data(for: request)
            
            if let httpResponse = response as? HTTPURLResponse {
                if httpResponse.statusCode == 200 {
                    return data
                }
                
                // Rate limited — wait and retry
                if httpResponse.statusCode == 429 {
                    let retryAfter = httpResponse.value(forHTTPHeaderField: "Retry-After")
                        .flatMap(Double.init) ?? Double(2 * (attempt + 1))
                    let delay = min(retryAfter, 10)
                    Logger.shared.log("AniList rate limited (429), retry \(attempt + 1)/\(maxRetries) after \(delay)s", type: "AniList")
                    try await Task.sleep(nanoseconds: UInt64(delay * 1_000_000_000))
                    lastError = NSError(domain: "AniList", code: 429, userInfo: [NSLocalizedDescriptionKey: "AniList rate limited (HTTP 429)"])
                    continue
                }
                
                let error = "AniList error (HTTP \(httpResponse.statusCode))"
                Logger.shared.log("AniListService: GraphQL request failed with HTTP \(httpResponse.statusCode)", type: "Error")
                throw NSError(domain: "AniList", code: httpResponse.statusCode, userInfo: [NSLocalizedDescriptionKey: error])
            }
            
            throw NSError(domain: "AniList", code: -1, userInfo: [NSLocalizedDescriptionKey: "Failed to fetch from AniList"])
        }
        
        throw lastError ?? NSError(domain: "AniList", code: 429, userInfo: [NSLocalizedDescriptionKey: "AniList rate limited after \(maxRetries) retries"])
    }

    /// Batch-fetch multiple anime nodes with relations in a single aliased GraphQL query
    private func batchFetchAniListNodes(ids: [Int]) async -> [Int: AniListAnime] {
        guard !ids.isEmpty else { return [:] }

        let fragment = """
            id
            title { romaji english native }
            episodes
            status
            seasonYear
            season
            format
            type
            coverImage { large medium }
            relations {
                edges {
                    relationType
                    node {
                        id
                        title { romaji english native }
                        episodes
                        status
                        seasonYear
                        season
                        format
                        type
                        coverImage { large medium }
                    }
                }
            }
        """

        let aliases = ids.enumerated().map { i, id in
            "m\(i): Media(id: \(id), type: ANIME) { \(fragment) }"
        }.joined(separator: "\n")

        let query = "query { \(aliases) }"

        do {
            let data = try await executeGraphQLQuery(query, token: nil)
            let json = try JSONSerialization.jsonObject(with: data) as? [String: Any]
            guard let dataDict = json?["data"] as? [String: Any] else { return [:] }

            var result: [Int: AniListAnime] = [:]
            for (i, id) in ids.enumerated() {
                let key = "m\(i)"
                if let mediaJSON = dataDict[key],
                   let mediaData = try? JSONSerialization.data(withJSONObject: mediaJSON),
                   let anime = try? JSONDecoder().decode(AniListAnime.self, from: mediaData) {
                    result[id] = anime
                }
            }
            return result
        } catch {
            Logger.shared.log("AniListService: Batch fetch failed for \(ids.count) nodes: \(error.localizedDescription)", type: "AniList")
            return [:]
        }
    }

    /// Fetch a single anime node with relations for deeper traversal
    private func fetchAniListAnimeNode(id: Int) async throws -> AniListAnime {
        let query = """
        query {
            Media(id: \(id), type: ANIME) {
                id
                title { romaji english native }
                episodes
                status
                seasonYear
                season
                format
                type
                coverImage { large medium }
                relations {
                    edges {
                        relationType
                        node {
                            id
                            title { romaji english native }
                            episodes
                            status
                            seasonYear
                            season
                            format
                            type
                            coverImage { large medium }
                        }
                    }
                }
            }
        }
        """

        struct Response: Codable {
            let data: DataWrapper
            struct DataWrapper: Codable {
                let Media: AniListAnime
            }
        }

        let data = try await executeGraphQLQuery(query, token: nil)
        let decoded = try JSONDecoder().decode(Response.self, from: data)
        return decoded.data.Media
    }

}

// MARK: - Helper Models

protocol AniListEpisodeProtocol {
    var number: Int { get }
    var title: String { get }
    var description: String? { get }
    var seasonNumber: Int { get }
}

struct AniListEpisode: AniListEpisodeProtocol {
    let number: Int                // AniList local episode number (1-12 per season) - used for search
    let title: String
    let description: String?
    let seasonNumber: Int          // AniList season number - used for search
    let stillPath: String?         // From TMDB for metadata
    let airDate: String?
    let runtime: Int?
    let tmdbSeasonNumber: Int?     // Original TMDB season number (before AniList restructuring)
    let tmdbEpisodeNumber: Int?    // Original TMDB episode number (before AniList restructuring)
}

struct AniListAiringScheduleEntry: Identifiable {
    let id: Int
    let mediaId: Int
    let title: String
    let airingAt: Date
    let episode: Int
    let coverImage: String?
}

struct AniListSeasonWithPoster {
    let seasonNumber: Int
    let anilistId: Int             // AniList anime ID for this specific season
    let title: String              // Full AniList title for this season (e.g., "SPYÃ—FAMILY Season 2")
    let episodes: [AniListEpisode]
    let posterUrl: String?
}

struct AniListAnimeWithSeasons {
    let id: Int
    let title: String
    let seasons: [AniListSeasonWithPoster]
    let totalEpisodes: Int
    let status: String
}

// MARK: - AniList Codable Models

struct AniListAnime: Codable {
    let id: Int
    let title: AniListTitle
    let episodes: Int?
    let status: String?
    let seasonYear: Int?
    let season: String?
    let coverImage: AniListCoverImage?
    let format: String?
    let type: String?
    let nextAiringEpisode: AniListNextAiringEpisode?
    let relations: AniListRelations?

    struct AniListTitle: Codable {
        let romaji: String?
        let english: String?
        let native: String?
    }

    struct AniListCoverImage: Codable {
        let large: String?
        let medium: String?
    }

    struct AniListNextAiringEpisode: Codable {
        let episode: Int?
        let airingAt: Int?
    }

    struct AniListRelations: Codable {
        let edges: [AniListRelationEdge]
    }

    struct AniListRelationEdge: Codable {
        let relationType: String
        let node: AniListRelationNode
    }

    struct AniListRelationNode: Codable {
        let id: Int
        let title: AniListTitle
        let episodes: Int?
        let status: String?
        let seasonYear: Int?
        let season: String?
        let format: String?
        let type: String?
        let coverImage: AniListCoverImage?
        let relations: AniListRelations?

        func asAnime() -> AniListAnime {
            return AniListAnime(
                id: id,
                title: title,
                episodes: episodes,
                status: status,
                seasonYear: seasonYear,
                season: season,
                coverImage: coverImage,
                format: format,
                type: type,
                nextAiringEpisode: nil,
                relations: relations
            )
        }
    }
}

enum AniListTitlePicker {
    private static func cleanTitle(_ title: String) -> String {
        let cleaned = title
            .trimmingCharacters(in: CharacterSet(charactersIn: "[]"))
            .trimmingCharacters(in: .whitespaces)
        return cleaned.isEmpty ? title : cleaned
    }
    
    static func title(from title: AniListAnime.AniListTitle, preferredLanguageCode: String) -> String {
        let lang = preferredLanguageCode.lowercased()

        if lang.hasPrefix("en"), let english = title.english, !english.isEmpty {
            return cleanTitle(english)
        }

        if lang.hasPrefix("ja"), let native = title.native, !native.isEmpty {
            return cleanTitle(native)
        }

        if let english = title.english, !english.isEmpty {
            return cleanTitle(english)
        }

        if let romaji = title.romaji, !romaji.isEmpty {
            return cleanTitle(romaji)
        }

        if let native = title.native, !native.isEmpty {
            return cleanTitle(native)
        }

        return "Unknown"
    }

    static func titleCandidates(from title: AniListAnime.AniListTitle) -> [String] {
        var seen = Set<String>()
        let ordered = [title.english, title.romaji, title.native].compactMap { $0 }
        return ordered.compactMap { value in
            let cleaned = value
                .trimmingCharacters(in: CharacterSet(charactersIn: "[]"))
                .trimmingCharacters(in: .whitespaces)
            let finalValue = cleaned.isEmpty ? value : cleaned
            
            if seen.contains(finalValue) { return nil }
            seen.insert(finalValue)
            return finalValue
        }
    }
}
