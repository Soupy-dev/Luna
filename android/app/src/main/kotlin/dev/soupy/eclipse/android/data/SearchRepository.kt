package dev.soupy.eclipse.android.data

import kotlinx.coroutines.async
import kotlinx.coroutines.coroutineScope
import dev.soupy.eclipse.android.core.model.MediaCarouselSection
import dev.soupy.eclipse.android.core.model.isMovie
import dev.soupy.eclipse.android.core.model.isTVShow
import dev.soupy.eclipse.android.core.network.AniListService
import dev.soupy.eclipse.android.core.network.NetworkResult
import dev.soupy.eclipse.android.core.network.TmdbService

data class SearchContent(
    val sections: List<MediaCarouselSection> = emptyList(),
)

class SearchRepository(
    private val tmdbService: TmdbService,
    private val aniListService: AniListService,
    private val tmdbEnabled: Boolean,
) {
    suspend fun search(query: String): Result<SearchContent> = runCatching {
        require(query.isNotBlank()) { "Search query cannot be blank." }

        coroutineScope {
            val tmdbDeferred = async {
                if (tmdbEnabled) tmdbService.searchMulti(query = query, page = 1) else NetworkResult.Success(
                    dev.soupy.eclipse.android.core.model.TMDBSearchResponse(results = emptyList()),
                )
            }
            val animeDeferred = async { aniListService.searchAnime(query = query, page = 1, perPage = 18) }

            val tmdbResults = tmdbDeferred.await().orThrow().results
                .filter { it.isMovie || it.isTVShow }
                .take(18)
                .map { it.toExploreMediaCard() }
            val animeResults = animeDeferred.await().orThrow().media
                .take(18)
                .map { it.toExploreMediaCard("Anime") }

            SearchContent(
                sections = buildList {
                    if (tmdbResults.isNotEmpty()) {
                        add(MediaCarouselSection("search-tmdb", "TMDB Matches", "Movies and shows from TMDB", tmdbResults))
                    }
                    if (animeResults.isNotEmpty()) {
                        add(MediaCarouselSection("search-anilist", "AniList Anime Matches", "Anime-focused matches that keep sequel titles intact", animeResults))
                    }
                },
            )
        }
    }
}

