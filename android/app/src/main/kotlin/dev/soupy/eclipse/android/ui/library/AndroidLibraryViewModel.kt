package dev.soupy.eclipse.android.ui.library

import androidx.lifecycle.ViewModel
import androidx.lifecycle.viewModelScope
import kotlinx.coroutines.flow.MutableStateFlow
import kotlinx.coroutines.flow.StateFlow
import kotlinx.coroutines.flow.asStateFlow
import kotlinx.coroutines.flow.update
import kotlinx.coroutines.launch
import dev.soupy.eclipse.android.data.ContinueWatchingDraft
import dev.soupy.eclipse.android.data.LibraryItemDraft
import dev.soupy.eclipse.android.data.LibraryRepository
import dev.soupy.eclipse.android.core.model.LibrarySnapshot
import dev.soupy.eclipse.android.feature.library.ContinueWatchingRow
import dev.soupy.eclipse.android.feature.library.LibraryMetric
import dev.soupy.eclipse.android.feature.library.LibrarySavedItemRow
import dev.soupy.eclipse.android.feature.library.LibraryScreenState

class AndroidLibraryViewModel(
    private val repository: LibraryRepository,
) : ViewModel() {
    private val _state = MutableStateFlow(LibraryScreenState())
    val state: StateFlow<LibraryScreenState> = _state.asStateFlow()

    init {
        refresh()
    }

    fun refresh() {
        viewModelScope.launch {
            _state.update { it.copy(isLoading = true, errorMessage = null) }
            repository.loadSnapshot()
                .onSuccess { snapshot ->
                    _state.value = snapshot.toUiState()
                }
                .onFailure { error ->
                    _state.update {
                        it.copy(
                            isLoading = false,
                            errorMessage = error.message ?: "Unknown library error.",
                        )
                    }
                }
        }
    }

    fun toggleSaved(draft: LibraryItemDraft) {
        viewModelScope.launch {
            repository.toggleSaved(draft)
                .onSuccess { snapshot -> _state.value = snapshot.toUiState() }
        }
    }

    fun recordContinueWatching(draft: ContinueWatchingDraft) {
        syncContinueWatching(draft)
    }

    fun syncContinueWatching(draft: ContinueWatchingDraft) {
        viewModelScope.launch {
            repository.syncContinueWatching(draft)
                .onSuccess { snapshot -> _state.value = snapshot.toUiState() }
        }
    }

    fun removeSaved(id: String) {
        viewModelScope.launch {
            repository.removeSaved(id)
                .onSuccess { snapshot -> _state.value = snapshot.toUiState() }
        }
    }

    fun removeContinueWatching(id: String) {
        viewModelScope.launch {
            repository.removeContinueWatching(id)
                .onSuccess { snapshot -> _state.value = snapshot.toUiState() }
        }
    }
}

private fun LibrarySnapshot.toUiState(): LibraryScreenState {
    val heroTitle = continueWatching.firstOrNull()?.title
        ?: savedItems.firstOrNull()?.title
        ?: "Library"
    val heroImageUrl = continueWatching.firstOrNull()?.backdropUrl
        ?: continueWatching.firstOrNull()?.imageUrl
        ?: savedItems.firstOrNull()?.backdropUrl
        ?: savedItems.firstOrNull()?.imageUrl
    val heroSupportingText = when {
        continueWatching.isNotEmpty() ->
            "Direct Android playback now updates resume state automatically for supported streams, and completed sessions fall back out of Continue Watching."
        savedItems.isNotEmpty() ->
            "Saved titles now survive app restarts and are ready to become part of full backup parity."
        else ->
            "Saved titles and continue watching are now backed by Android-side storage instead of placeholder UI."
    }

    return LibraryScreenState(
        isLoading = false,
        heroTitle = heroTitle,
        heroSubtitle = when {
            continueWatching.isNotEmpty() -> "Continue Watching"
            savedItems.isNotEmpty() -> "Saved titles"
            else -> "Milestone 2"
        },
        heroImageUrl = heroImageUrl,
        heroSupportingText = heroSupportingText,
        metrics = listOf(
            LibraryMetric(
                label = "Saved",
                value = savedItems.size.toString(),
                supportingText = "Pinned titles that stay outside resume state.",
            ),
            LibraryMetric(
                label = "Resume",
                value = continueWatching.size.toString(),
                supportingText = "Playback callbacks now keep supported sessions in sync automatically.",
            ),
        ),
        continueWatching = continueWatching.map { record ->
            ContinueWatchingRow(
                id = record.id,
                title = record.title,
                subtitle = record.subtitle,
                imageUrl = record.imageUrl,
                backdropUrl = record.backdropUrl,
                progressPercent = record.progressPercent,
                progressLabel = record.progressLabel,
                detailTarget = record.detailTarget,
            )
        },
        savedItems = savedItems.map { record ->
            LibrarySavedItemRow(
                id = record.id,
                title = record.title,
                subtitle = record.subtitle,
                overview = record.overview,
                imageUrl = record.imageUrl,
                backdropUrl = record.backdropUrl,
                mediaLabel = record.mediaLabel,
                detailTarget = record.detailTarget,
            )
        },
    )
}
