package dev.soupy.eclipse.android.data

import kotlinx.coroutines.async
import kotlinx.coroutines.coroutineScope
import dev.soupy.eclipse.android.core.model.AniListMedia
import dev.soupy.eclipse.android.core.model.DetailTarget
import dev.soupy.eclipse.android.core.model.displayTitle
import dev.soupy.eclipse.android.core.model.fullBackdropUrl
import dev.soupy.eclipse.android.core.model.fullPosterUrl
import dev.soupy.eclipse.android.core.model.fullStillUrl
import dev.soupy.eclipse.android.core.model.posterUrl
import dev.soupy.eclipse.android.core.model.TMDBEpisode
import dev.soupy.eclipse.android.core.network.AniListService
import dev.soupy.eclipse.android.core.network.TmdbService

data class DetailEpisodeEntry(
    val id: String,
    val title: String,
    val subtitle: String? = null,
    val imageUrl: String? = null,
    val overview: String? = null,
    val seasonNumber: Int? = null,
    val episodeNumber: Int? = null,
)

data class DetailContent(
    val title: String,
    val subtitle: String? = null,
    val overview: String? = null,
    val posterUrl: String? = null,
    val backdropUrl: String? = null,
    val metadataChips: List<String> = emptyList(),
    val episodesTitle: String? = null,
    val episodes: List<DetailEpisodeEntry> = emptyList(),
)

class DetailRepository(
    private val tmdbService: TmdbService,
    private val aniListService: AniListService,
    private val animeTmdbMapper: AnimeTmdbMapper,
) {
    suspend fun load(target: DetailTarget): Result<DetailContent> = runCatching {
        when (target) {
            is DetailTarget.TmdbMovie -> {
                val movie = tmdbService.movieDetail(target.id).orThrow()
                DetailContent(
                    title = movie.title,
                    subtitle = movie.releaseDate?.take(4)?.let { "Movie | $it" } ?: "Movie",
                    overview = movie.overview,
                    posterUrl = movie.fullPosterUrl,
                    backdropUrl = movie.fullBackdropUrl,
                    metadataChips = buildList {
                        add("Movie")
                        movie.releaseDate?.take(4)?.let(::add)
                        movie.runtime?.takeIf { it > 0 }?.let { add("${it}m") }
                        addAll(movie.genres.map { it.name }.take(3))
                    },
                )
            }

            is DetailTarget.TmdbShow -> {
                val show = tmdbService.tvShowDetail(target.id).orThrow()
                val seasonDetails = tmdbService.firstPlayableSeasonDetails(
                    showId = target.id,
                    seasons = show.seasons,
                )

                DetailContent(
                    title = show.name,
                    subtitle = show.firstAirDate?.take(4)?.let { "Series | $it" } ?: "Series",
                    overview = show.overview,
                    posterUrl = show.fullPosterUrl,
                    backdropUrl = show.fullBackdropUrl,
                    metadataChips = buildList {
                        add("Series")
                        show.firstAirDate?.take(4)?.let(::add)
                        show.seasons.size.takeIf { it > 0 }?.let { add("$it seasons") }
                        addAll(show.genres.map { it.name }.take(3))
                    },
                    episodesTitle = seasonDetails.title(show.name),
                    episodes = seasonDetails.flatMap { seasonDetail ->
                        seasonDetail.episodes.map { it.toDetailEpisodeEntry() }
                    },
                )
            }

            is DetailTarget.AniListMediaTarget -> {
                val media = aniListService.mediaById(target.id).orThrow()
                media.toDetailContent(
                    tmdbMatch = animeTmdbMapper.findBestMatch(media),
                    tmdbService = tmdbService,
                )
            }
        }
    }
}

private fun TMDBEpisode.toDetailEpisodeEntry(): DetailEpisodeEntry = DetailEpisodeEntry(
    id = "episode-$seasonNumber-$episodeNumber",
    title = name.ifBlank { "Episode $episodeNumber" },
    subtitle = "S$seasonNumber | E$episodeNumber" + (airDate?.takeIf { it.isNotBlank() }?.let { " | $it" } ?: ""),
    imageUrl = fullStillUrl,
    overview = overview,
    seasonNumber = seasonNumber,
    episodeNumber = episodeNumber,
)

private suspend fun AniListMedia.toDetailContent(
    tmdbMatch: AnimeTmdbMatch?,
    tmdbService: TmdbService,
): DetailContent {
    val tmdbShowEpisodes = (tmdbMatch?.target as? DetailTarget.TmdbShow)?.let { target ->
        runCatching {
            val show = tmdbService.tvShowDetail(target.id).orThrow()
            val seasons = tmdbService.firstPlayableSeasonDetails(
                showId = target.id,
                seasons = show.seasons,
            )
            seasons.title(show.name) to seasons.flatMap { seasonDetail ->
                seasonDetail.episodes.map { it.toDetailEpisodeEntry() }
            }
        }.getOrNull()
    }
    val syntheticEpisodes = if (tmdbShowEpisodes == null) syntheticAnimeEpisodes() else emptyList()

    return DetailContent(
        title = displayTitle,
        subtitle = listOfNotNull(
            format?.replace('_', ' '),
            seasonYear?.toString(),
            tmdbMatch?.title?.let { "TMDB: $it" },
        ).joinToString(" | ").ifBlank { "Anime" },
        overview = description?.stripHtmlTags(),
        posterUrl = posterUrl,
        backdropUrl = bannerImage ?: posterUrl,
        metadataChips = buildList {
            add("Anime")
            format?.replace('_', ' ')?.let(::add)
            seasonYear?.toString()?.let(::add)
            episodes?.takeIf { it > 0 }?.let { add("$it eps") }
            status?.replace('_', ' ')?.let(::add)
            tmdbMatch?.let { add("TMDB match ${(it.confidence * 100).toInt()}%") }
            addAll(genres.take(3))
        },
        episodesTitle = tmdbShowEpisodes?.first ?: syntheticEpisodes.takeIf { it.isNotEmpty() }?.let { "Episodes" },
        episodes = tmdbShowEpisodes?.second ?: syntheticEpisodes,
    )
}

private suspend fun TmdbService.firstPlayableSeasonDetails(
    showId: Int,
    seasons: List<dev.soupy.eclipse.android.core.model.TMDBSeason>,
): List<dev.soupy.eclipse.android.core.model.TMDBSeasonDetail> = coroutineScope {
    seasons
        .filter { season -> season.seasonNumber > 0 && season.episodeCount > 0 }
        .take(3)
        .map { season ->
            async { seasonDetail(showId, season.seasonNumber).orNull() }
        }
        .mapNotNull { deferred -> deferred.await() }
        .filter { season -> season.episodes.isNotEmpty() }
}

private fun List<dev.soupy.eclipse.android.core.model.TMDBSeasonDetail>.title(showName: String): String? = when {
    isEmpty() -> null
    size == 1 -> first().name.ifBlank { "$showName Episodes" }
    else -> "Episodes"
}

private fun AniListMedia.syntheticAnimeEpisodes(): List<DetailEpisodeEntry> {
    val count = episodes ?: nextAiringEpisode?.episode?.minus(1) ?: 0
    return (1..count.coerceAtMost(24)).map { episode ->
        DetailEpisodeEntry(
            id = "anilist-$id-episode-$episode",
            title = "Episode $episode",
            subtitle = "Episode $episode",
            imageUrl = posterUrl,
            overview = null,
            seasonNumber = 1,
            episodeNumber = episode,
        )
    }
}

