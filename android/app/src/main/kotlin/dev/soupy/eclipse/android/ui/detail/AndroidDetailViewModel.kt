package dev.soupy.eclipse.android.ui.detail

import androidx.lifecycle.ViewModel
import androidx.lifecycle.viewModelScope
import kotlinx.coroutines.flow.MutableStateFlow
import kotlinx.coroutines.flow.StateFlow
import kotlinx.coroutines.flow.asStateFlow
import kotlinx.coroutines.flow.update
import kotlinx.coroutines.launch
import dev.soupy.eclipse.android.data.ContinueWatchingDraft
import dev.soupy.eclipse.android.data.DetailContent
import dev.soupy.eclipse.android.data.DetailRepository
import dev.soupy.eclipse.android.data.DownloadDraft
import dev.soupy.eclipse.android.data.EpisodeProgressDraft
import dev.soupy.eclipse.android.data.LibraryItemDraft
import dev.soupy.eclipse.android.data.MovieProgressDraft
import dev.soupy.eclipse.android.data.ProgressRepository
import dev.soupy.eclipse.android.data.RatingsRepository
import dev.soupy.eclipse.android.data.StreamResolutionRepository
import dev.soupy.eclipse.android.data.StreamEpisodeSelection
import dev.soupy.eclipse.android.core.model.DetailTarget
import dev.soupy.eclipse.android.feature.detail.DetailCastRow
import dev.soupy.eclipse.android.feature.detail.DetailEpisodeRow
import dev.soupy.eclipse.android.feature.detail.DetailScreenState
import dev.soupy.eclipse.android.feature.detail.DetailStreamRow
import kotlin.math.roundToInt

class AndroidDetailViewModel(
    private val repository: DetailRepository,
    private val streamResolutionRepository: StreamResolutionRepository,
    private val progressRepository: ProgressRepository,
    private val ratingsRepository: RatingsRepository,
) : ViewModel() {
    private val _state = MutableStateFlow(DetailScreenState())
    val state: StateFlow<DetailScreenState> = _state.asStateFlow()

    private var currentTarget: DetailTarget? = null
    private var currentProgressTarget: DetailTarget? = null
    private var currentRatingTmdbId: Int? = null

    fun load(target: DetailTarget?) {
        if (target == null) {
            currentTarget = null
            currentProgressTarget = null
            currentRatingTmdbId = null
            _state.value = DetailScreenState()
            return
        }

        if (target == currentTarget && (_state.value.title.isNotBlank() || _state.value.isLoading)) {
            return
        }

        currentTarget = target
        viewModelScope.launch {
            _state.value = DetailScreenState(hasSelection = true, isLoading = true)
            val result = repository.load(target)
            result
                .onSuccess { content ->
                    currentProgressTarget = content.progressTarget ?: target
                    currentRatingTmdbId = (currentProgressTarget ?: target).tmdbRatingId()
                    val rating = currentRatingTmdbId?.let { id ->
                        ratingsRepository.loadSnapshot().getOrNull()?.ratings?.get(id.toString())
                    }
                    _state.value = content.toUiState(userRating = rating)
                }
                .onFailure { error ->
                    currentProgressTarget = null
                    currentRatingTmdbId = null
                    _state.update {
                        it.copy(
                            hasSelection = true,
                            isLoading = false,
                            errorMessage = error.message ?: "Unknown detail error.",
                        )
                    }
                }
        }
    }

    fun setUserRating(rating: Int) {
        val tmdbId = currentRatingTmdbId ?: return markUnsupportedRating()
        viewModelScope.launch {
            ratingsRepository.setRating(tmdbId, rating)
                .onSuccess {
                    _state.update {
                        it.copy(
                            userRating = rating.coerceIn(1, 5),
                            streamStatusMessage = "Saved rating ${rating.coerceIn(1, 5)}/5.",
                        )
                    }
                }
                .onFailure { error ->
                    _state.update {
                        it.copy(streamStatusMessage = error.message ?: "Could not save rating.")
                    }
                }
        }
    }

    fun clearUserRating() {
        val tmdbId = currentRatingTmdbId ?: return markUnsupportedRating()
        viewModelScope.launch {
            ratingsRepository.removeRating(tmdbId)
                .onSuccess {
                    _state.update {
                        it.copy(userRating = null, streamStatusMessage = "Removed your rating.")
                    }
                }
                .onFailure { error ->
                    _state.update {
                        it.copy(streamStatusMessage = error.message ?: "Could not remove rating.")
                    }
                }
        }
    }

    fun markCurrentWatched() {
        markCurrent(watched = true)
    }

    fun markCurrentUnwatched() {
        markCurrent(watched = false)
    }

    fun markEpisodeWatched(episodeId: String) {
        markEpisode(episodeId = episodeId, watched = true)
    }

    fun markEpisodeUnwatched(episodeId: String) {
        markEpisode(episodeId = episodeId, watched = false)
    }

    fun markPreviousEpisodesWatched(episodeId: String) {
        val target = currentProgressTarget as? DetailTarget.TmdbShow ?: return markUnsupportedProgress()
        val episode = state.value.episodes.firstOrNull { it.id == episodeId } ?: return
        val seasonNumber = episode.seasonNumber ?: return
        val episodeNumber = episode.episodeNumber ?: return
        if (episodeNumber <= 1) {
            _state.update { it.copy(streamStatusMessage = "There are no previous episodes in this season.") }
            return
        }
        viewModelScope.launch {
            progressRepository.markPreviousEpisodesWatched(
                showId = target.id,
                seasonNumber = seasonNumber,
                throughEpisodeExclusive = episodeNumber,
                watched = true,
            ).onSuccess {
                _state.update {
                    it.copy(streamStatusMessage = "Marked previous episodes watched through S${seasonNumber}E${episodeNumber - 1}.")
                }
            }.onFailure { error ->
                _state.update {
                    it.copy(streamStatusMessage = error.message ?: "Could not mark previous episodes watched.")
                }
            }
        }
    }

    fun retry() {
        load(currentTarget)
    }

    fun resolveStreams() {
        val selectedEpisode = state.value.selectedEpisodeId
            ?.let { id -> state.value.episodes.firstOrNull { it.id == id } }
            ?.toStreamEpisodeSelection()
        resolveStreamsForEpisode(selectedEpisode)
    }

    fun resolveEpisodeStreams(episodeId: String) {
        val episode = state.value.episodes.firstOrNull { it.id == episodeId } ?: return
        val selection = episode.toStreamEpisodeSelection() ?: return
        resolveStreamsForEpisode(selection)
    }

    private fun resolveStreamsForEpisode(episode: StreamEpisodeSelection?) {
        val target = currentTarget ?: return
        if (_state.value.isResolvingStreams) return

        viewModelScope.launch {
            _state.update {
                it.copy(
                    isResolvingStreams = true,
                    streamStatusMessage = episode?.let { selected ->
                        "Resolving addon streams for ${selected.label}..."
                    } ?: "Resolving addon streams...",
                    selectedEpisodeId = episode?.let { selected ->
                        _state.value.episodes.firstOrNull {
                            it.seasonNumber == selected.seasonNumber && it.episodeNumber == selected.episodeNumber
                        }?.id
                    } ?: it.selectedEpisodeId,
                    selectedEpisodeLabel = episode?.label ?: it.selectedEpisodeLabel,
                )
            }
            streamResolutionRepository.resolve(target, episode)
                .onSuccess { result ->
                    _state.update { state ->
                        state.copy(
                            isResolvingStreams = false,
                            streamStatusMessage = result.statusMessage,
                            streamCandidates = result.candidates.map { candidate ->
                                DetailStreamRow(
                                    id = candidate.id,
                                    title = candidate.title,
                                    subtitle = candidate.subtitle,
                                    supportingText = candidate.supportingText,
                                    playable = candidate.isPlayable,
                                    playerSource = candidate.playerSource,
                                )
                            },
                            playerSource = result.selectedSource ?: state.playerSource,
                        )
                    }
                }
                .onFailure { error ->
                    _state.update {
                        it.copy(
                            isResolvingStreams = false,
                            streamStatusMessage = error.message ?: "Android stream resolution failed.",
                            streamCandidates = emptyList(),
                        )
                    }
                }
        }
    }

    fun playResolvedStream(streamId: String) {
        _state.update { state ->
            state.copy(
                playerSource = state.streamCandidates.firstOrNull { it.id == streamId }?.playerSource
                    ?: state.playerSource,
            )
        }
    }

    fun playNextEpisode() {
        val nextEpisode = nextEpisodeAfterCurrent()
        if (nextEpisode == null) {
            _state.update { it.copy(streamStatusMessage = "No next episode is loaded yet.") }
            return
        }
        val selection = nextEpisode.toStreamEpisodeSelection()
        if (selection == null) {
            _state.update { it.copy(streamStatusMessage = "Next episode metadata is not playable yet.") }
            return
        }
        resolveStreamsForEpisode(selection)
    }

    fun currentPlaybackProgressDraft(
        positionMs: Long,
        durationMs: Long,
        isFinished: Boolean,
    ): ContinueWatchingDraft? {
        val target = currentProgressTarget ?: currentTarget ?: return null
        val snapshot = state.value
        if (snapshot.title.isBlank() || durationMs <= 0L) return null

        val progressPercent = if (isFinished) {
            1f
        } else {
            (positionMs.toFloat() / durationMs.toFloat()).coerceIn(0f, 1f)
        }
        if (!isFinished && positionMs < 15_000L && progressPercent < 0.05f) {
            return null
        }

        val selectedEpisode = snapshot.selectedEpisodeId
            ?.let { id -> snapshot.episodes.firstOrNull { it.id == id } }
            ?: snapshot.episodes.firstOrNull()
        recordTypedProgress(
            target = target,
            snapshot = snapshot,
            selectedEpisode = selectedEpisode,
            positionMs = positionMs,
            durationMs = durationMs,
            isFinished = isFinished,
        )

        val subtitle = selectedEpisode?.title ?: snapshot.subtitle ?: snapshot.playerSource?.title
        val progressLabel = listOfNotNull(
            selectedEpisode?.subtitle,
            "${(progressPercent * 100f).roundToInt()}% watched",
        ).joinToString(" | ").ifBlank {
            "${(progressPercent * 100f).roundToInt()}% watched"
        }

        return ContinueWatchingDraft(
            detailTarget = target,
            title = snapshot.title,
            subtitle = subtitle,
            imageUrl = snapshot.posterUrl,
            backdropUrl = snapshot.backdropUrl,
            progressPercent = progressPercent,
            progressLabel = progressLabel,
        )
    }

    fun currentLibraryItemDraft(): LibraryItemDraft? {
        val target = currentTarget ?: return null
        val snapshot = state.value
        if (snapshot.title.isBlank()) return null

        return LibraryItemDraft(
            detailTarget = target,
            title = snapshot.title,
            subtitle = snapshot.subtitle,
            overview = snapshot.overview,
            imageUrl = snapshot.posterUrl,
            backdropUrl = snapshot.backdropUrl,
            mediaLabel = snapshot.metadataChips.firstOrNull(),
        )
    }

    fun currentContinueWatchingDraft(): ContinueWatchingDraft? {
        val target = currentTarget ?: return null
        val snapshot = state.value
        if (snapshot.title.isBlank()) return null

        val firstEpisode = snapshot.episodes.firstOrNull()
        return ContinueWatchingDraft(
            detailTarget = target,
            title = snapshot.title,
            subtitle = firstEpisode?.title ?: snapshot.subtitle,
            imageUrl = snapshot.posterUrl,
            backdropUrl = snapshot.backdropUrl,
            progressPercent = if (firstEpisode == null) 0.42f else 0.08f,
            progressLabel = firstEpisode?.let { episode ->
                episode.subtitle?.let { "Resume near $it" } ?: "Resume from ${episode.title}"
            } ?: "Resume from the last saved movie position once playback reporting is wired.",
        )
    }

    fun currentDownloadDraft(): DownloadDraft? {
        val target = currentTarget ?: return null
        val snapshot = state.value
        if (snapshot.title.isBlank()) return null

        val firstEpisode = snapshot.episodes.firstOrNull()
        return DownloadDraft(
            detailTarget = target,
            title = snapshot.title,
            subtitle = firstEpisode?.title ?: snapshot.subtitle,
            imageUrl = snapshot.posterUrl,
            backdropUrl = snapshot.backdropUrl,
            mediaLabel = snapshot.metadataChips.firstOrNull(),
            progressLabel = firstEpisode?.subtitle?.let { "Preparing offline draft near $it" }
                ?: "Preparing an offline draft while Android source resolution lands.",
            sourceLabel = snapshot.playerSource?.title ?: if (firstEpisode == null) {
                "Movie download draft"
            } else {
                "Episode download draft"
            },
            playerSource = snapshot.playerSource,
        )
    }

    private fun recordTypedProgress(
        target: DetailTarget,
        snapshot: DetailScreenState,
        selectedEpisode: DetailEpisodeRow?,
        positionMs: Long,
        durationMs: Long,
        isFinished: Boolean,
    ) {
        val currentSeconds = positionMs.toDouble() / 1000.0
        val durationSeconds = durationMs.toDouble() / 1000.0
        when (target) {
            is DetailTarget.TmdbMovie -> {
                viewModelScope.launch {
                    progressRepository.recordMovieProgress(
                        MovieProgressDraft(
                            movieId = target.id,
                            title = snapshot.title,
                            posterUrl = snapshot.posterUrl,
                            currentTimeSeconds = currentSeconds,
                            totalDurationSeconds = durationSeconds,
                            isFinished = isFinished,
                        ),
                    )
                }
            }
            is DetailTarget.TmdbShow -> {
                val episode = selectedEpisode ?: return
                val seasonNumber = episode.seasonNumber ?: return
                val episodeNumber = episode.episodeNumber ?: return
                viewModelScope.launch {
                    progressRepository.recordEpisodeProgress(
                        EpisodeProgressDraft(
                            showId = target.id,
                            seasonNumber = seasonNumber,
                            episodeNumber = episodeNumber,
                            showTitle = snapshot.title,
                            showPosterUrl = snapshot.posterUrl,
                            currentTimeSeconds = currentSeconds,
                            totalDurationSeconds = durationSeconds,
                            isFinished = isFinished,
                        ),
                    )
                }
            }
            is DetailTarget.AniListMediaTarget -> Unit
        }
    }

    private fun markCurrent(watched: Boolean) {
        when (val target = currentProgressTarget ?: currentTarget) {
            is DetailTarget.TmdbMovie -> {
                viewModelScope.launch {
                    progressRepository.markMovieWatched(target.id, watched)
                        .onSuccess {
                            _state.update {
                                it.copy(streamStatusMessage = if (watched) "Marked movie watched." else "Marked movie unwatched.")
                            }
                        }
                        .onFailure { error ->
                            _state.update {
                                it.copy(streamStatusMessage = error.message ?: "Could not update movie progress.")
                            }
                        }
                }
            }
            is DetailTarget.TmdbShow -> markLoadedShowEpisodes(target.id, watched)
            is DetailTarget.AniListMediaTarget,
            null -> markUnsupportedProgress()
        }
    }

    private fun markLoadedShowEpisodes(showId: Int, watched: Boolean) {
        val episodes = state.value.episodes.filter {
            it.seasonNumber != null && it.episodeNumber != null
        }
        if (episodes.isEmpty()) {
            markUnsupportedProgress()
            return
        }
        viewModelScope.launch {
            episodes.forEach { episode ->
                progressRepository.markEpisodeWatched(
                    showId = showId,
                    seasonNumber = episode.seasonNumber ?: return@forEach,
                    episodeNumber = episode.episodeNumber ?: return@forEach,
                    watched = watched,
                )
            }
            _state.update {
                it.copy(
                    streamStatusMessage = if (watched) {
                        "Marked ${episodes.size} loaded episodes watched."
                    } else {
                        "Marked ${episodes.size} loaded episodes unwatched."
                    },
                )
            }
        }
    }

    private fun markEpisode(episodeId: String, watched: Boolean) {
        val target = currentProgressTarget as? DetailTarget.TmdbShow ?: return markUnsupportedProgress()
        val episode = state.value.episodes.firstOrNull { it.id == episodeId } ?: return
        val seasonNumber = episode.seasonNumber ?: return
        val episodeNumber = episode.episodeNumber ?: return
        viewModelScope.launch {
            progressRepository.markEpisodeWatched(
                showId = target.id,
                seasonNumber = seasonNumber,
                episodeNumber = episodeNumber,
                watched = watched,
            ).onSuccess {
                _state.update {
                    it.copy(
                        streamStatusMessage = if (watched) {
                            "Marked S${seasonNumber}E${episodeNumber} watched."
                        } else {
                            "Marked S${seasonNumber}E${episodeNumber} unwatched."
                        },
                    )
                }
            }.onFailure { error ->
                _state.update {
                    it.copy(streamStatusMessage = error.message ?: "Could not update episode progress.")
                }
            }
        }
    }

    private fun markUnsupportedProgress() {
        _state.update {
            it.copy(streamStatusMessage = "Progress actions need a TMDB movie or mapped TMDB series.")
        }
    }

    private fun markUnsupportedRating() {
        _state.update {
            it.copy(streamStatusMessage = "Ratings need a TMDB movie or mapped TMDB series.")
        }
    }

    private fun nextEpisodeAfterCurrent(): DetailEpisodeRow? {
        val playableEpisodes = state.value.episodes.filter {
            it.seasonNumber != null && it.episodeNumber != null
        }
        if (playableEpisodes.size < 2) return null
        val currentIndex = state.value.selectedEpisodeId
            ?.let { id -> playableEpisodes.indexOfFirst { it.id == id } }
            ?.takeIf { it >= 0 }
            ?: 0
        return playableEpisodes.getOrNull(currentIndex + 1)
    }
}

private fun DetailContent.toUiState(userRating: Int?): DetailScreenState = DetailScreenState(
    hasSelection = true,
    isLoading = false,
    title = title,
    subtitle = subtitle,
    overview = overview,
    posterUrl = posterUrl,
    backdropUrl = backdropUrl,
    metadataChips = metadataChips,
    contentRating = contentRating,
    userRating = userRating,
    cast = cast.map {
        DetailCastRow(
            id = it.id,
            name = it.name,
            role = it.role,
            imageUrl = it.imageUrl,
        )
    },
    recommendations = recommendations,
    episodesTitle = episodesTitle,
    episodes = episodes.map {
        DetailEpisodeRow(
            id = it.id,
            title = it.title,
            subtitle = it.subtitle,
            imageUrl = it.imageUrl,
            overview = it.overview,
            seasonNumber = it.seasonNumber,
            episodeNumber = it.episodeNumber,
            runtimeMinutes = it.runtimeMinutes,
        )
    },
)

private fun DetailTarget.tmdbRatingId(): Int? = when (this) {
    is DetailTarget.TmdbMovie -> id
    is DetailTarget.TmdbShow -> id
    is DetailTarget.AniListMediaTarget -> null
}

private fun DetailEpisodeRow.toStreamEpisodeSelection(): StreamEpisodeSelection? {
    val season = seasonNumber ?: return null
    val episode = episodeNumber ?: return null
    return StreamEpisodeSelection(
        seasonNumber = season,
        episodeNumber = episode,
        label = "S${season}E${episode}",
    )
}


