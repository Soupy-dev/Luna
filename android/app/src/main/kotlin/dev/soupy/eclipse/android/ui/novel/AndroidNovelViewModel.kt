package dev.soupy.eclipse.android.ui.novel

import androidx.lifecycle.ViewModel
import androidx.lifecycle.viewModelScope
import dev.soupy.eclipse.android.data.MangaOverviewSnapshot
import dev.soupy.eclipse.android.data.MangaRepository
import dev.soupy.eclipse.android.feature.novel.NovelModuleRow
import dev.soupy.eclipse.android.feature.novel.NovelProgressRow
import dev.soupy.eclipse.android.feature.novel.NovelScreenState
import kotlinx.coroutines.flow.MutableStateFlow
import kotlinx.coroutines.flow.StateFlow
import kotlinx.coroutines.flow.asStateFlow
import kotlinx.coroutines.launch

class AndroidNovelViewModel(
    private val repository: MangaRepository,
) : ViewModel() {
    private val _state = MutableStateFlow(NovelScreenState(isLoading = true))
    val state: StateFlow<NovelScreenState> = _state.asStateFlow()

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
                        errorMessage = error.message ?: "Novel reading data could not be loaded.",
                    )
                }
        }
    }

    private fun applyOverview(snapshot: MangaOverviewSnapshot) {
        _state.value = NovelScreenState(
            isLoading = false,
            novelCount = snapshot.novelCount,
            readChapterCount = snapshot.novelReadChapterCount,
            importedFromBackup = snapshot.importedFromBackup,
            recent = snapshot.recentNovelProgress.map { (id, progress) ->
                NovelProgressRow(
                    id = id,
                    title = progress.title ?: "Novel $id",
                    subtitle = listOfNotNull(
                        progress.lastReadChapter?.let { "Chapter $it" },
                        progress.format,
                    ).joinToString(" - "),
                    coverUrl = progress.coverUrl,
                )
            },
            modules = snapshot.modules
                .filter { module -> module.isNovel }
                .map { module ->
                    NovelModuleRow(
                        id = module.id,
                        name = module.displayName,
                        subtitle = listOfNotNull(
                            module.version.takeIf(String::isNotBlank)?.let { "v$it" },
                            module.language.takeIf(String::isNotBlank),
                        ).joinToString(" - "),
                        isActive = module.isActive,
                    )
                },
        )
    }
}
