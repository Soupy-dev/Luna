package dev.soupy.eclipse.android.data

import dev.soupy.eclipse.android.core.model.DetailTarget
import dev.soupy.eclipse.android.core.model.PlayerSource
import dev.soupy.eclipse.android.core.model.StremioManifest
import dev.soupy.eclipse.android.core.model.StremioStream
import dev.soupy.eclipse.android.core.model.SubtitleTrack
import dev.soupy.eclipse.android.core.network.EclipseJson
import dev.soupy.eclipse.android.core.network.StremioService
import dev.soupy.eclipse.android.core.network.TmdbService
import dev.soupy.eclipse.android.core.storage.SettingsStore
import dev.soupy.eclipse.android.core.storage.StremioAddonDao
import dev.soupy.eclipse.android.core.storage.StremioAddonEntity
import kotlinx.coroutines.flow.first
import kotlinx.serialization.decodeFromString

data class ResolvedStreamCandidate(
    val id: String,
    val title: String,
    val subtitle: String? = null,
    val supportingText: String? = null,
    val addonName: String,
    val isPlayable: Boolean,
    val playerSource: PlayerSource? = null,
)

data class StreamResolutionResult(
    val statusMessage: String,
    val candidates: List<ResolvedStreamCandidate> = emptyList(),
    val selectedSource: PlayerSource? = null,
)

class StreamResolutionRepository(
    private val tmdbService: TmdbService,
    private val stremioService: StremioService,
    private val stremioAddonDao: StremioAddonDao,
    private val settingsStore: SettingsStore,
) {
    suspend fun resolve(target: DetailTarget): Result<StreamResolutionResult> = runCatching {
        if (target is DetailTarget.AniListMediaTarget) {
            return@runCatching StreamResolutionResult(
                statusMessage = "Anime stream resolution still needs the AniList-to-TMDB/Stremio bridge on Android. TMDB movie and series detail pages are supported first.",
            )
        }

        val request = buildRequest(target)
        val settings = settingsStore.settings.first()
        val addons = stremioAddonDao.observeAll().first()
            .filter(StremioAddonEntity::enabled)
            .let { enabled ->
                val selectedAddonIds = enabled
                    .map { addon -> "stremio:${addon.transportUrl}" }
                    .filter { it in settings.autoModeSourceIds }
                if (settings.autoModeEnabled && selectedAddonIds.isNotEmpty()) {
                    enabled.filter { addon -> "stremio:${addon.transportUrl}" in selectedAddonIds }
                } else {
                    enabled
                }
            }
            .filter { addon ->
                val manifest = addon.manifest()
                manifest == null || manifest.types.isEmpty() || request.type in manifest.types
            }

        if (addons.isEmpty()) {
            return@runCatching StreamResolutionResult(
                statusMessage = "No enabled Stremio addons are ready for ${request.type}. Import one in Services first, or include it in Auto Mode if you want Android to prefer selected addons.",
            )
        }

        val candidates = buildList {
            addons.forEach { addon ->
                val addonLabel = addon.name.ifBlank { addon.transportUrl }
                stremioService.fetchStreams(
                    transportUrl = addon.transportUrl,
                    type = request.type,
                    id = request.id,
                ).orNull()?.streams.orEmpty()
                    .mapIndexed { index, stream ->
                        stream.toResolvedCandidate(
                            addon = addon,
                            addonLabel = addonLabel,
                            requestSummary = request.summary,
                            index = index,
                        )
                    }
                    .let(::addAll)
            }
        }.sortedWith(
            compareByDescending<ResolvedStreamCandidate> { it.isPlayable }
                .thenBy { it.addonName.lowercase() }
                .thenBy { it.title.lowercase() },
        )

        if (candidates.isEmpty()) {
            return@runCatching StreamResolutionResult(
                statusMessage = "The enabled addons didn't return any streams for ${request.summary} yet.",
            )
        }

        val playable = candidates.firstOrNull(ResolvedStreamCandidate::isPlayable)?.playerSource
        val playableCount = candidates.count(ResolvedStreamCandidate::isPlayable)
        val pendingCount = candidates.size - playableCount

        StreamResolutionResult(
            statusMessage = when {
                playable != null && pendingCount > 0 ->
                    "Resolved $playableCount direct stream${if (playableCount == 1) "" else "s"} plus $pendingCount torrent or unsupported result${if (pendingCount == 1) "" else "s"} for ${request.summary}."
                playable != null ->
                    "Resolved $playableCount direct stream${if (playableCount == 1) "" else "s"} for ${request.summary}."
                else ->
                    "Found ${candidates.size} stream result${if (candidates.size == 1) "" else "s"} for ${request.summary}, but they still need torrent or alternate-player support on Android."
            },
            candidates = candidates,
            selectedSource = playable,
        )
    }

    private suspend fun buildRequest(target: DetailTarget): StremioRequest = when (target) {
        is DetailTarget.TmdbMovie -> {
            val movie = tmdbService.movieDetail(target.id).orThrow()
            val imdbId = movie.externalIds?.imdbId?.takeIf { it.isNotBlank() }
                ?: error("TMDB didn't return an IMDb ID for this movie, so Android can't build a Stremio request yet.")
            StremioRequest(
                type = "movie",
                id = imdbId,
                summary = movie.title.ifBlank { imdbId },
            )
        }

        is DetailTarget.TmdbShow -> {
            val show = tmdbService.tvShowDetail(target.id).orThrow()
            val imdbId = show.externalIds?.imdbId?.takeIf { it.isNotBlank() }
                ?: error("TMDB didn't return an IMDb ID for this series, so Android can't build a Stremio request yet.")
            val firstSeason = show.seasons.firstOrNull { it.seasonNumber > 0 } ?: show.seasons.firstOrNull()
                ?: error("This series doesn't expose any seasons yet, so Android can't resolve Stremio episode streams.")
            val seasonDetail = tmdbService.seasonDetail(target.id, firstSeason.seasonNumber).orThrow()
            val firstEpisode = seasonDetail.episodes.firstOrNull { it.episodeNumber > 0 }
                ?: error("This series doesn't expose a playable episode yet for Android stream resolution.")
            StremioRequest(
                type = "series",
                id = "$imdbId:${firstSeason.seasonNumber}:${firstEpisode.episodeNumber}",
                summary = "${show.name} S${firstSeason.seasonNumber}E${firstEpisode.episodeNumber}",
            )
        }

        is DetailTarget.AniListMediaTarget -> error("AniList media targets are not supported in the first Android stream resolver.")
    }
}

private data class StremioRequest(
    val type: String,
    val id: String,
    val summary: String,
)

private fun StremioStream.toResolvedCandidate(
    addon: StremioAddonEntity,
    addonLabel: String,
    requestSummary: String,
    index: Int,
): ResolvedStreamCandidate {
    val directUrl = url?.takeIf { it.startsWith("http://") || it.startsWith("https://") }
    val playerSource = directUrl?.let {
        PlayerSource(
            uri = it,
            title = title ?: name ?: addonLabel,
            headers = behaviorHints?.proxyHeaders?.request.orEmpty(),
            subtitles = subtitles.mapNotNull { subtitle ->
                subtitle.url?.let { subtitleUrl ->
                    SubtitleTrack(
                        id = subtitle.id ?: "$addonLabel-$index-${subtitle.lang ?: "sub"}",
                        label = subtitle.label ?: subtitle.lang ?: "Subtitle",
                        language = subtitle.lang,
                        uri = subtitleUrl,
                    )
                }
            },
        )
    }

    val stateText = when {
        playerSource != null -> "Direct stream"
        infoHash != null -> "Torrent stream pending engine support"
        ytId != null -> "YouTube handoff pending"
        else -> "Unsupported stream format"
    }

    return ResolvedStreamCandidate(
        id = "${addon.transportUrl}#$index",
        title = title ?: name ?: addonLabel,
        subtitle = addonLabel,
        supportingText = listOfNotNull(
            description?.takeIf { it.isNotBlank() },
            stateText,
            behaviorHints?.filename,
            requestSummary.takeIf { playerSource != null && description.isNullOrBlank() },
        ).joinToString(" | ").ifBlank { null },
        addonName = addonLabel,
        isPlayable = playerSource != null,
        playerSource = playerSource,
    )
}

private fun StremioAddonEntity.manifest(): StremioManifest? = manifestJson?.runCatching {
    EclipseJson.decodeFromString<StremioManifest>(this)
}?.getOrNull()
