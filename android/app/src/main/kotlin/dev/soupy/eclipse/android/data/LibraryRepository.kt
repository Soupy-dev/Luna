package dev.soupy.eclipse.android.data

import dev.soupy.eclipse.android.core.model.ContinueWatchingRecord
import dev.soupy.eclipse.android.core.model.DetailTarget
import dev.soupy.eclipse.android.core.model.LibraryItemRecord
import dev.soupy.eclipse.android.core.model.LibrarySnapshot
import dev.soupy.eclipse.android.core.storage.LibraryStore

data class LibraryItemDraft(
    val detailTarget: DetailTarget,
    val title: String,
    val subtitle: String? = null,
    val overview: String? = null,
    val imageUrl: String? = null,
    val backdropUrl: String? = null,
    val mediaLabel: String? = null,
)

data class ContinueWatchingDraft(
    val detailTarget: DetailTarget,
    val title: String,
    val subtitle: String? = null,
    val imageUrl: String? = null,
    val backdropUrl: String? = null,
    val progressPercent: Float = 0f,
    val progressLabel: String? = null,
)

class LibraryRepository(
    private val libraryStore: LibraryStore,
) {
    suspend fun loadSnapshot(): Result<LibrarySnapshot> = runCatching {
        libraryStore.read().normalized()
    }

    suspend fun toggleSaved(draft: LibraryItemDraft): Result<LibrarySnapshot> = runCatching {
        val snapshot = libraryStore.read()
        val key = draft.detailTarget.storageKey()
        val alreadySaved = snapshot.savedItems.any { it.id == key }
        val updatedSaved = if (alreadySaved) {
            snapshot.savedItems.filterNot { it.id == key }
        } else {
            listOf(draft.toRecord(key)) + snapshot.savedItems.filterNot { it.id == key }
        }

        writeSnapshot(snapshot.copy(savedItems = updatedSaved))
    }

    suspend fun recordContinueWatching(draft: ContinueWatchingDraft): Result<LibrarySnapshot> = runCatching {
        val snapshot = libraryStore.read()
        val key = draft.detailTarget.storageKey()
        val updatedContinueWatching = listOf(draft.toRecord(key)) +
            snapshot.continueWatching.filterNot { it.id == key }

        writeSnapshot(
            snapshot.copy(
                continueWatching = updatedContinueWatching.take(20),
            ),
        )
    }

    suspend fun removeSaved(id: String): Result<LibrarySnapshot> = runCatching {
        val snapshot = libraryStore.read()
        writeSnapshot(snapshot.copy(savedItems = snapshot.savedItems.filterNot { it.id == id }))
    }

    suspend fun removeContinueWatching(id: String): Result<LibrarySnapshot> = runCatching {
        val snapshot = libraryStore.read()
        writeSnapshot(
            snapshot.copy(
                continueWatching = snapshot.continueWatching.filterNot { it.id == id },
            ),
        )
    }

    private suspend fun writeSnapshot(snapshot: LibrarySnapshot): LibrarySnapshot {
        val normalized = snapshot.normalized()
        libraryStore.write(normalized)
        return normalized
    }
}

private fun LibrarySnapshot.normalized(): LibrarySnapshot = copy(
    savedItems = savedItems.sortedByDescending { it.updatedAt },
    continueWatching = continueWatching.sortedByDescending { it.updatedAt },
)

private fun LibraryItemDraft.toRecord(id: String): LibraryItemRecord = LibraryItemRecord(
    id = id,
    detailTarget = detailTarget,
    title = title,
    subtitle = subtitle,
    overview = overview,
    imageUrl = imageUrl,
    backdropUrl = backdropUrl,
    mediaLabel = mediaLabel,
)

private fun ContinueWatchingDraft.toRecord(id: String): ContinueWatchingRecord = ContinueWatchingRecord(
    id = id,
    detailTarget = detailTarget,
    title = title,
    subtitle = subtitle,
    imageUrl = imageUrl,
    backdropUrl = backdropUrl,
    progressPercent = progressPercent.coerceIn(0f, 1f),
    progressLabel = progressLabel,
)

private fun DetailTarget.storageKey(): String = when (this) {
    is DetailTarget.AniListMediaTarget -> "anilist:$id"
    is DetailTarget.TmdbMovie -> "tmdb_movie:$id"
    is DetailTarget.TmdbShow -> "tmdb_show:$id"
}
