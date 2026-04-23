package dev.soupy.eclipse.android.data

import java.time.Instant
import java.time.ZoneId
import java.time.format.DateTimeFormatter
import java.util.Locale
import dev.soupy.eclipse.android.core.model.AniListAiringScheduleEntry
import dev.soupy.eclipse.android.core.model.AniListMedia
import dev.soupy.eclipse.android.core.model.bestAvailableUrl
import dev.soupy.eclipse.android.core.model.DetailTarget
import dev.soupy.eclipse.android.core.model.displayDate
import dev.soupy.eclipse.android.core.model.displayTitle
import dev.soupy.eclipse.android.core.model.displayTitle as airingMediaDisplayTitle
import dev.soupy.eclipse.android.core.model.ExploreMediaCard
import dev.soupy.eclipse.android.core.model.fullBackdropUrl
import dev.soupy.eclipse.android.core.model.fullPosterUrl
import dev.soupy.eclipse.android.core.model.isMovie
import dev.soupy.eclipse.android.core.model.isTVShow
import dev.soupy.eclipse.android.core.model.posterUrl
import dev.soupy.eclipse.android.core.model.ScheduleEntryCard
import dev.soupy.eclipse.android.core.model.TMDBSearchResult

internal fun TMDBSearchResult.toExploreMediaCard(
    badge: String? = if (isMovie) "Movie" else "Series",
): ExploreMediaCard {
    require(isMovie || isTVShow) {
        "TMDB person results are not supported in ExploreMediaCard."
    }

    return ExploreMediaCard(
        id = "tmdb-${mediaType ?: if (isMovie) "movie" else "tv"}-$id",
        title = displayTitle,
        subtitle = displayDate?.take(4),
        overview = overview,
        imageUrl = fullPosterUrl,
        backdropUrl = fullBackdropUrl,
        badge = badge,
        detailTarget = if (isMovie) DetailTarget.TmdbMovie(id) else DetailTarget.TmdbShow(id),
    )
}

internal fun AniListMedia.toExploreMediaCard(
    badge: String? = format
        ?.replace('_', ' ')
        ?.lowercase(Locale.US)
        ?.replaceFirstChar { if (it.isLowerCase()) it.titlecase(Locale.US) else it.toString() },
): ExploreMediaCard = ExploreMediaCard(
    id = "anilist-$id",
    title = displayTitle,
    subtitle = seasonYear?.toString(),
    overview = description?.stripHtmlTags(),
    imageUrl = posterUrl,
    backdropUrl = bannerImage ?: posterUrl,
    badge = badge,
    detailTarget = DetailTarget.AniListMediaTarget(id),
)

internal fun AniListAiringScheduleEntry.toScheduleEntryCard(
    zoneId: ZoneId = ZoneId.systemDefault(),
): ScheduleEntryCard {
    val timeText = Instant.ofEpochSecond(airingAtEpochSeconds)
        .atZone(zoneId)
        .format(DateTimeFormatter.ofPattern("h:mm a", Locale.US))
    return ScheduleEntryCard(
        id = "airing-$id",
        title = media.airingMediaDisplayTitle,
        subtitle = "Episode $episode | $timeText",
        imageUrl = media.coverImage.bestAvailableUrl,
        detailTarget = DetailTarget.AniListMediaTarget(media.id),
    )
}

internal fun String.stripHtmlTags(): String =
    replace(Regex("<[^>]+>"), " ")
        .replace("&quot;", "\"")
        .replace("&#39;", "'")
        .replace("&amp;", "&")
        .replace(Regex("\\s+"), " ")
        .trim()

