package dev.soupy.eclipse.android.data

import kotlinx.coroutines.async
import kotlinx.coroutines.coroutineScope
import dev.soupy.eclipse.android.core.model.AniListMedia
import dev.soupy.eclipse.android.core.model.DetailTarget
import dev.soupy.eclipse.android.core.model.ExploreMediaCard
import dev.soupy.eclipse.android.core.model.TMDBCastMember
import dev.soupy.eclipse.android.core.model.displayTitle
import dev.soupy.eclipse.android.core.model.fullBackdropUrl
import dev.soupy.eclipse.android.core.model.fullProfileUrl
import dev.soupy.eclipse.android.core.model.fullPosterUrl
import dev.soupy.eclipse.android.core.model.fullStillUrl
import dev.soupy.eclipse.android.core.model.isMovie
import dev.soupy.eclipse.android.core.model.isTVShow
import dev.soupy.eclipse.android.core.model.posterUrl
import dev.soupy.eclipse.android.core.model.TMDBEpisode
import dev.soupy.eclipse.android.core.model.TMDBSearchResult
import dev.soupy.eclipse.android.core.model.TMDBSeason
import dev.soupy.eclipse.android.core.model.TMDBSeasonDetail
import dev.soupy.eclipse.android.core.model.usCertification
import dev.soupy.eclipse.android.core.model.usRating
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
    val runtimeMinutes: Int? = null,
)

data class DetailCastEntry(
    val id: String,
    val name: String,
    val role: String? = null,
    val imageUrl: String? = null,
)

data class DetailContent(
    val title: String,
    val subtitle: String? = null,
    val overview: String? = null,
    val posterUrl: String? = null,
    val backdropUrl: String? = null,
    val metadataChips: List<String> = emptyList(),
    val contentRating: String? = null,
    val cast: List<DetailCastEntry> = emptyList(),
    val recommendations: List<ExploreMediaCard> = emptyList(),
    val episodesTitle: String? = null,
    val episodes: List<DetailEpisodeEntry> = emptyList(),
    val progressTarget: DetailTarget? = null,
)

class DetailRepository(
    private val tmdbService: TmdbService,
    private val aniListService: AniListService,
    private val animeTmdbMapper: AnimeTmdbMapper,
) {
    suspend fun load(target: DetailTarget): Result<DetailContent> = runCatching {
        when (target) {
            is DetailTarget.TmdbMovie -> loadMovieContent(target.id)

            is DetailTarget.TmdbShow -> loadShowContent(target.id)

            is DetailTarget.AniListMediaTarget -> {
                val media = aniListService.mediaById(target.id).orThrow()
                media.toDetailContent(
                    tmdbMatch = animeTmdbMapper.findBestMatch(media),
                    tmdbService = tmdbService,
                )
            }
        }
    }

    private suspend fun loadMovieContent(movieId: Int): DetailContent = coroutineScope {
        val movieDeferred = async { tmdbService.movieDetail(movieId).orThrow() }
        val creditsDeferred = async { tmdbService.movieCredits(movieId).orNull() }
        val recommendationsDeferred = async { tmdbService.movieRecommendations(movieId).orEmptyList() }
        val releaseDatesDeferred = async { tmdbService.movieReleaseDates(movieId).orNull() }

        val movie = movieDeferred.await()
        val certification = releaseDatesDeferred.await()?.usCertification
        DetailContent(
            title = movie.title,
            subtitle = movie.releaseDate?.take(4)?.let { "Movie | $it" } ?: "Movie",
            overview = movie.overview,
            posterUrl = movie.fullPosterUrl,
            backdropUrl = movie.fullBackdropUrl,
            metadataChips = buildList {
                add("Movie")
                movie.releaseDate?.take(4)?.let(::add)
                movie.runtime?.takeIf { it > 0 }?.let { add(formatRuntime(it)) }
                certification?.let { add("Rated $it") }
                addAll(movie.genres.map { it.name }.take(3))
            },
            contentRating = certification,
            cast = creditsDeferred.await().toDetailCastEntries(),
            recommendations = recommendationsDeferred.await().toRecommendationCards(),
            progressTarget = DetailTarget.TmdbMovie(movieId),
        )
    }

    private suspend fun loadShowContent(showId: Int): DetailContent = coroutineScope {
        val showDeferred = async { tmdbService.tvShowDetail(showId).orThrow() }
        val creditsDeferred = async { tmdbService.tvCredits(showId).orNull() }
        val recommendationsDeferred = async { tmdbService.tvRecommendations(showId).orEmptyList() }
        val ratingsDeferred = async { tmdbService.tvContentRatings(showId).orNull() }

        val show = showDeferred.await()
        val seasonDetails = tmdbService.playableSeasonDetails(
            showId = showId,
            seasons = show.seasons,
        )
        val contentRating = ratingsDeferred.await()?.usRating
        DetailContent(
            title = show.name,
            subtitle = show.firstAirDate?.take(4)?.let { "Series | $it" } ?: "Series",
            overview = show.overview,
            posterUrl = show.fullPosterUrl,
            backdropUrl = show.fullBackdropUrl,
            metadataChips = buildList {
                add("Series")
                show.firstAirDate?.take(4)?.let(::add)
                show.seasons.count { it.seasonNumber > 0 && it.episodeCount > 0 }.takeIf { it > 0 }?.let { add("$it seasons") }
                show.episodeRunTime.firstOrNull { it > 0 }?.let { add(formatRuntime(it)) }
                contentRating?.let { add("Rated $it") }
                addAll(show.genres.map { it.name }.take(3))
            },
            contentRating = contentRating,
            cast = creditsDeferred.await().toDetailCastEntries(),
            recommendations = recommendationsDeferred.await().toRecommendationCards(),
            episodesTitle = seasonDetails.title(show.name),
            episodes = seasonDetails.flatMap { seasonDetail ->
                seasonDetail.episodes.map { it.toDetailEpisodeEntry() }
            },
            progressTarget = DetailTarget.TmdbShow(showId),
        )
    }
}

private fun TMDBEpisode.toDetailEpisodeEntry(): DetailEpisodeEntry = DetailEpisodeEntry(
    id = "episode-$seasonNumber-$episodeNumber",
    title = name.ifBlank { "Episode $episodeNumber" },
    subtitle = buildList {
        add("S$seasonNumber")
        add("E$episodeNumber")
        runtime?.takeIf { it > 0 }?.let { add(formatRuntime(it)) }
        airDate?.takeIf { it.isNotBlank() }?.let(::add)
    }.joinToString(" | "),
    imageUrl = fullStillUrl,
    overview = overview,
    seasonNumber = seasonNumber,
    episodeNumber = episodeNumber,
    runtimeMinutes = runtime,
)

private suspend fun AniListMedia.toDetailContent(
    tmdbMatch: AnimeTmdbMatch?,
    tmdbService: TmdbService,
): DetailContent {
    val tmdbShowMetadata = (tmdbMatch?.target as? DetailTarget.TmdbShow)?.let { target ->
        runCatching {
            coroutineScope {
                val showDeferred = async { tmdbService.tvShowDetail(target.id).orThrow() }
                val creditsDeferred = async { tmdbService.tvCredits(target.id).orNull() }
                val recommendationsDeferred = async { tmdbService.tvRecommendations(target.id).orEmptyList() }
                val ratingsDeferred = async { tmdbService.tvContentRatings(target.id).orNull() }
                val show = showDeferred.await()
                val seasons = tmdbService.playableSeasonDetails(
                    showId = target.id,
                    seasons = show.seasons,
                )
                HydratedTmdbShowMetadata(
                    episodesTitle = seasons.title(show.name),
                    episodes = seasons.flatMap { seasonDetail ->
                        seasonDetail.episodes.map { it.toDetailEpisodeEntry() }
                    },
                    cast = creditsDeferred.await().toDetailCastEntries(),
                    recommendations = recommendationsDeferred.await().toRecommendationCards(),
                    contentRating = ratingsDeferred.await()?.usRating,
                )
            }
        }.getOrNull()
    }
    val syntheticEpisodes = if (tmdbShowMetadata == null) syntheticAnimeEpisodes() else emptyList()

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
            tmdbShowMetadata?.contentRating?.let { add("Rated $it") }
            tmdbMatch?.let { add("TMDB match ${(it.confidence * 100).toInt()}%") }
            addAll(genres.take(3))
        },
        contentRating = tmdbShowMetadata?.contentRating,
        cast = tmdbShowMetadata?.cast.orEmpty(),
        recommendations = tmdbShowMetadata?.recommendations.orEmpty(),
        episodesTitle = tmdbShowMetadata?.episodesTitle ?: syntheticEpisodes.takeIf { it.isNotEmpty() }?.let { "Episodes" },
        episodes = tmdbShowMetadata?.episodes ?: syntheticEpisodes,
        progressTarget = tmdbMatch?.target,
    )
}

private data class HydratedTmdbShowMetadata(
    val episodesTitle: String?,
    val episodes: List<DetailEpisodeEntry>,
    val cast: List<DetailCastEntry>,
    val recommendations: List<ExploreMediaCard>,
    val contentRating: String?,
)

private suspend fun TmdbService.playableSeasonDetails(
    showId: Int,
    seasons: List<TMDBSeason>,
): List<TMDBSeasonDetail> = coroutineScope {
    seasons
        .filter { season -> season.seasonNumber > 0 && season.episodeCount > 0 }
        .take(8)
        .map { season ->
            async { seasonDetail(showId, season.seasonNumber).orNull() }
        }
        .mapNotNull { deferred -> deferred.await() }
        .filter { season -> season.episodes.isNotEmpty() }
}

private fun List<TMDBSeasonDetail>.title(showName: String): String? = when {
    isEmpty() -> null
    size == 1 -> first().name.ifBlank { "$showName Episodes" }
    else -> "Episodes"
}

private fun dev.soupy.eclipse.android.core.model.TMDBCreditsResponse?.toDetailCastEntries(): List<DetailCastEntry> =
    this?.cast.orEmpty()
        .sortedBy(TMDBCastMember::order)
        .take(12)
        .map { member ->
            DetailCastEntry(
                id = "cast-${member.id}-${member.order}",
                name = member.name,
                role = member.character.takeIf { it.isNotBlank() },
                imageUrl = member.fullProfileUrl,
            )
        }

private fun List<TMDBSearchResult>.toRecommendationCards(): List<ExploreMediaCard> =
    asSequence()
        .filter { it.isMovie || it.isTVShow }
        .mapNotNull { result ->
            runCatching { result.toExploreMediaCard("Recommended") }.getOrNull()
        }
        .take(12)
        .toList()

private fun formatRuntime(minutes: Int): String =
    if (minutes < 60) {
        "${minutes}m"
    } else {
        val hours = minutes / 60
        val remainder = minutes % 60
        if (remainder > 0) "${hours}h ${remainder}m" else "${hours}h"
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

