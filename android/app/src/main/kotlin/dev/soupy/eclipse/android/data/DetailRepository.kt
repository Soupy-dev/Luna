package dev.soupy.eclipse.android.data

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
                val firstSeason = show.seasons.firstOrNull { it.seasonNumber > 0 } ?: show.seasons.firstOrNull()
                val seasonDetail = firstSeason?.let { tmdbService.seasonDetail(target.id, it.seasonNumber).orNull() }

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
                    episodesTitle = seasonDetail?.name ?: firstSeason?.name,
                    episodes = seasonDetail?.episodes?.take(10)?.map { it.toDetailEpisodeEntry() }.orEmpty(),
                )
            }

            is DetailTarget.AniListMediaTarget -> {
                val media = aniListService.mediaById(target.id).orThrow()
                media.toDetailContent()
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
)

private fun AniListMedia.toDetailContent(): DetailContent = DetailContent(
    title = displayTitle,
    subtitle = listOfNotNull(
        format?.replace('_', ' '),
        seasonYear?.toString(),
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
        addAll(genres.take(3))
    },
)

