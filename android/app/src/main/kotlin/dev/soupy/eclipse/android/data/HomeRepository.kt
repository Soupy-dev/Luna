package dev.soupy.eclipse.android.data

import kotlinx.coroutines.async
import kotlinx.coroutines.coroutineScope
import dev.soupy.eclipse.android.core.model.ExploreMediaCard
import dev.soupy.eclipse.android.core.model.MediaCarouselSection
import dev.soupy.eclipse.android.core.model.isMovie
import dev.soupy.eclipse.android.core.model.isTVShow
import dev.soupy.eclipse.android.core.network.AniListService
import dev.soupy.eclipse.android.core.network.TmdbService

data class HomeContent(
    val hero: ExploreMediaCard? = null,
    val sections: List<MediaCarouselSection> = emptyList(),
)

class HomeRepository(
    private val tmdbService: TmdbService,
    private val aniListService: AniListService,
    private val tmdbEnabled: Boolean,
) {
    suspend fun loadHome(): Result<HomeContent> = runCatching {
        coroutineScope {
            val trendingDeferred = async {
                if (tmdbEnabled) tmdbService.trendingAll()
                else dev.soupy.eclipse.android.core.network.NetworkResult.Success(emptyList<dev.soupy.eclipse.android.core.model.TMDBSearchResult>())
            }
            val popularMoviesDeferred = async {
                if (tmdbEnabled) tmdbService.popularMovies()
                else dev.soupy.eclipse.android.core.network.NetworkResult.Success(emptyList<dev.soupy.eclipse.android.core.model.TMDBSearchResult>())
            }
            val nowPlayingMoviesDeferred = async {
                if (tmdbEnabled) tmdbService.nowPlayingMovies()
                else dev.soupy.eclipse.android.core.network.NetworkResult.Success(emptyList<dev.soupy.eclipse.android.core.model.TMDBSearchResult>())
            }
            val upcomingMoviesDeferred = async {
                if (tmdbEnabled) tmdbService.upcomingMovies()
                else dev.soupy.eclipse.android.core.network.NetworkResult.Success(emptyList<dev.soupy.eclipse.android.core.model.TMDBSearchResult>())
            }
            val popularTvDeferred = async {
                if (tmdbEnabled) tmdbService.popularTv()
                else dev.soupy.eclipse.android.core.network.NetworkResult.Success(emptyList<dev.soupy.eclipse.android.core.model.TMDBSearchResult>())
            }
            val airingTodayDeferred = async {
                if (tmdbEnabled) tmdbService.airingTodayTv()
                else dev.soupy.eclipse.android.core.network.NetworkResult.Success(emptyList<dev.soupy.eclipse.android.core.model.TMDBSearchResult>())
            }
            val topRatedTvDeferred = async {
                if (tmdbEnabled) tmdbService.topRatedTv()
                else dev.soupy.eclipse.android.core.network.NetworkResult.Success(emptyList<dev.soupy.eclipse.android.core.model.TMDBSearchResult>())
            }
            val topRatedMoviesDeferred = async {
                if (tmdbEnabled) tmdbService.topRatedMovies()
                else dev.soupy.eclipse.android.core.network.NetworkResult.Success(emptyList<dev.soupy.eclipse.android.core.model.TMDBSearchResult>())
            }
            val animeCatalogsDeferred = async { aniListService.fetchHomeCatalogs() }

            val sections = buildList {
                val trending = trendingDeferred.await().orEmptyList()
                    .filter { it.isMovie || it.isTVShow }
                    .take(12)
                    .map { it.toExploreMediaCard("Trending") }
                val popularMovies = popularMoviesDeferred.await().orEmptyList().take(12).map { it.toExploreMediaCard("Movie") }
                val nowPlayingMovies = nowPlayingMoviesDeferred.await().orEmptyList().take(12).map { it.toExploreMediaCard("Now playing") }
                val upcomingMovies = upcomingMoviesDeferred.await().orEmptyList().take(12).map { it.toExploreMediaCard("Upcoming") }
                val popularTv = popularTvDeferred.await().orEmptyList().take(12).map { it.toExploreMediaCard("Series") }
                val airingToday = airingTodayDeferred.await().orEmptyList().take(12).map { it.toExploreMediaCard("Airing today") }
                val topRatedTv = topRatedTvDeferred.await().orEmptyList().take(12).map { it.toExploreMediaCard("Top rated") }
                val topRatedMovies = topRatedMoviesDeferred.await().orEmptyList().take(12).map { it.toExploreMediaCard("Top rated") }
                val animeCatalogs = animeCatalogsDeferred.await().orThrow()

                if (trending.isNotEmpty()) {
                    add(MediaCarouselSection("tmdb-trending", "Trending This Week", "Live TMDB discovery feed", trending))
                }
                if (popularMovies.isNotEmpty()) {
                    add(MediaCarouselSection("tmdb-movies", "Popular Movies", "What people are queueing right now", popularMovies))
                }
                if (nowPlayingMovies.isNotEmpty()) {
                    add(MediaCarouselSection("tmdb-now-playing", "Now Playing Movies", "Fresh theatrical and streaming movie picks", nowPlayingMovies))
                }
                if (upcomingMovies.isNotEmpty()) {
                    add(MediaCarouselSection("tmdb-upcoming-movies", "Upcoming Movies", "Movies arriving soon", upcomingMovies))
                }
                if (popularTv.isNotEmpty()) {
                    add(MediaCarouselSection("tmdb-tv", "Popular Series", "The TV side of the current Luna browse flow", popularTv))
                }
                if (airingToday.isNotEmpty()) {
                    add(MediaCarouselSection("tmdb-airing", "Airing Today", "Shows with fresh TV episodes today", airingToday))
                }
                if (topRatedTv.isNotEmpty()) {
                    add(MediaCarouselSection("tmdb-top-tv", "Top Rated Series", "High-signal TV picks from TMDB", topRatedTv))
                }
                if (topRatedMovies.isNotEmpty()) {
                    add(MediaCarouselSection("tmdb-top-movies", "Top Rated Movies", "High-signal movie picks from TMDB", topRatedMovies))
                }
                if (animeCatalogs.trending.isNotEmpty()) {
                    add(MediaCarouselSection("anime-trending", "Trending Anime", "AniList-powered anime discovery", animeCatalogs.trending.take(12).map { it.toExploreMediaCard("Anime") }))
                }
                if (animeCatalogs.popular.isNotEmpty()) {
                    add(MediaCarouselSection("anime-popular", "Popular Anime", "Frequently watched AniList anime picks", animeCatalogs.popular.take(12).map { it.toExploreMediaCard("Anime") }))
                }
                if (animeCatalogs.airing.isNotEmpty()) {
                    add(MediaCarouselSection("anime-airing", "Currently Airing Anime", "What's actively rolling out now", animeCatalogs.airing.take(12).map { it.toExploreMediaCard("Airing") }))
                }
                if (animeCatalogs.upcoming.isNotEmpty()) {
                    add(MediaCarouselSection("anime-upcoming", "Upcoming Anime", "Not-yet-released anime with strong interest", animeCatalogs.upcoming.take(12).map { it.toExploreMediaCard("Upcoming") }))
                }
                if (animeCatalogs.topRated.isNotEmpty()) {
                    add(MediaCarouselSection("anime-top", "Top Rated Anime", "Score-sorted AniList picks", animeCatalogs.topRated.take(12).map { it.toExploreMediaCard("Top rated") }))
                }
            }

            if (sections.isEmpty()) {
                error("No TMDB or AniList browse sections were available.")
            }

            HomeContent(
                hero = sections.firstNotNullOfOrNull { it.items.firstOrNull() },
                sections = sections,
            )
        }
    }
}

