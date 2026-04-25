package dev.soupy.eclipse.android.data

import dev.soupy.eclipse.android.core.model.MediaCarouselSection
import dev.soupy.eclipse.android.core.model.TMDBSearchResult
import dev.soupy.eclipse.android.core.model.isMovie
import dev.soupy.eclipse.android.core.model.isTVShow
import dev.soupy.eclipse.android.core.network.AniListService
import dev.soupy.eclipse.android.core.network.NetworkResult
import dev.soupy.eclipse.android.core.network.TmdbService
import dev.soupy.eclipse.android.core.storage.SearchHistoryStore
import dev.soupy.eclipse.android.core.storage.SettingsStore
import kotlinx.coroutines.flow.first

private const val HorrorGenreId = 27

data class SearchContent(
    val sections: List<MediaCarouselSection> = emptyList(),
    val recentQueries: List<String> = emptyList(),
)

class SearchRepository(
    private val tmdbService: TmdbService,
    private val aniListService: AniListService,
    private val searchHistoryStore: SearchHistoryStore,
    private val settingsStore: SettingsStore,
    private val tmdbEnabled: Boolean,
) {
    suspend fun recentQueries(): List<String> = searchHistoryStore.read().queries

    suspend fun search(query: String): Result<SearchContent> = runCatching {
        require(query.isNotBlank()) { "Search query cannot be blank." }

        val settings = settingsStore.settings.first()
        val firstTmdbPage = if (tmdbEnabled) {
            tmdbService.searchMulti(query = query, page = 1).orThrow()
        } else {
            dev.soupy.eclipse.android.core.model.TMDBSearchResponse(results = emptyList())
        }
        val extraTmdbPages = if (tmdbEnabled && firstTmdbPage.totalPages > 1) {
            (2..minOf(firstTmdbPage.totalPages, 3))
                .flatMap { page -> tmdbService.searchMulti(query = query, page = page).orEmptyResponse().results }
        } else {
            emptyList()
        }
        val tmdbResults = (firstTmdbPage.results + extraTmdbPages)
            .filter { it.isMovie || it.isTVShow }
            .withoutFilteredHorror(settings.filterHorrorContent)
            .distinctBy { "${it.mediaType}:${it.id}" }
            .take(48)
            .map { it.toExploreMediaCard() }
        val recentQueries = searchHistoryStore.read().remember(query).also { searchHistoryStore.write(it) }.queries

        SearchContent(
            recentQueries = recentQueries,
            sections = if (tmdbResults.isEmpty()) {
                emptyList()
            } else {
                listOf(MediaCarouselSection("search-tmdb", "Search Results", "Movies and TV shows", tmdbResults))
            },
        )
    }
}

private fun NetworkResult<dev.soupy.eclipse.android.core.model.TMDBSearchResponse>.orEmptyResponse():
    dev.soupy.eclipse.android.core.model.TMDBSearchResponse = when (this) {
        is NetworkResult.Success -> value
        is NetworkResult.Failure -> dev.soupy.eclipse.android.core.model.TMDBSearchResponse(results = emptyList())
    }

private fun List<TMDBSearchResult>.withoutFilteredHorror(enabled: Boolean): List<TMDBSearchResult> =
    if (enabled) {
        filterNot { result -> HorrorGenreId in result.genreIds }
    } else {
        this
    }
