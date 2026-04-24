package dev.soupy.eclipse.android.ui.manga

import androidx.lifecycle.ViewModel
import androidx.lifecycle.viewModelScope
import dev.soupy.eclipse.android.data.MangaOverviewSnapshot
import dev.soupy.eclipse.android.data.MangaRepository
import dev.soupy.eclipse.android.feature.manga.MangaCollectionRow
import dev.soupy.eclipse.android.feature.manga.MangaModuleRow
import dev.soupy.eclipse.android.feature.manga.MangaProgressRow
import dev.soupy.eclipse.android.feature.manga.MangaScreenState
import kotlinx.coroutines.flow.MutableStateFlow
import kotlinx.coroutines.flow.StateFlow
import kotlinx.coroutines.flow.asStateFlow
import kotlinx.coroutines.launch

class AndroidMangaViewModel(
    private val repository: MangaRepository,
) : ViewModel() {
    private val _state = MutableStateFlow(MangaScreenState(isLoading = true))
    val state: StateFlow<MangaScreenState> = _state.asStateFlow()

    init {
        refresh()
    }

    fun refresh() {
        viewModelScope.launch {
            _state.value = _state.value.copy(isLoading = true, errorMessage = null)
            repository.loadOverview()
                .onSuccess(::applyOverview)
                .onFailure { error ->
                    _state.value = _state.value.copy(
                        isLoading = false,
                        errorMessage = error.message ?: "Manga library data could not be loaded.",
                    )
                }
        }
    }

    private fun applyOverview(snapshot: MangaOverviewSnapshot) {
        _state.value = MangaScreenState(
            isLoading = false,
            savedCount = snapshot.savedCount,
            readChapterCount = snapshot.readChapterCount,
            novelCount = snapshot.novelCount,
            importedFromBackup = snapshot.importedFromBackup,
            collections = snapshot.collections.map { collection ->
                MangaCollectionRow(
                    id = collection.id.ifBlank { collection.name },
                    name = collection.name,
                    subtitle = listOfNotNull(
                        "${collection.items.size} saved",
                        collection.description,
                    ).joinToString(" - "),
                )
            },
            recent = snapshot.recentProgress.map { (id, progress) ->
                MangaProgressRow(
                    id = id,
                    title = progress.title ?: "Manga $id",
                    subtitle = listOfNotNull(
                        progress.lastReadChapter?.let { "Chapter $it" },
                        progress.format,
                    ).joinToString(" - "),
                    coverUrl = progress.coverUrl,
                )
            },
            modules = snapshot.modules.map { module ->
                MangaModuleRow(
                    id = module.id,
                    name = module.displayName,
                    subtitle = listOfNotNull(
                        module.version.takeIf(String::isNotBlank)?.let { "v$it" },
                        module.language.takeIf(String::isNotBlank),
                        if (module.isNovel) "Novel" else "Manga",
                    ).joinToString(" - "),
                    isActive = module.isActive,
                )
            },
        )
    }
}
