package dev.soupy.eclipse.android.data

import dev.soupy.eclipse.android.core.model.KanzenModuleRecord
import dev.soupy.eclipse.android.core.model.MangaLibraryCollection
import dev.soupy.eclipse.android.core.model.MangaLibrarySnapshot
import dev.soupy.eclipse.android.core.model.MangaProgress
import dev.soupy.eclipse.android.core.storage.BackupFileStore
import dev.soupy.eclipse.android.core.storage.MangaStore

data class MangaOverviewSnapshot(
    val collections: List<MangaLibraryCollection>,
    val recentProgress: List<Pair<String, MangaProgress>>,
    val modules: List<KanzenModuleRecord>,
    val savedCount: Int,
    val readChapterCount: Int,
    val novelCount: Int,
    val importedFromBackup: Boolean,
)

class MangaRepository(
    private val mangaStore: MangaStore,
    private val backupFileStore: BackupFileStore,
) {
    suspend fun loadOverview(): Result<MangaOverviewSnapshot> = runCatching {
        val (snapshot, importedFromBackup) = seedFromBackupIfNeeded()
        snapshot.toOverview(importedFromBackup = importedFromBackup)
    }

    private suspend fun seedFromBackupIfNeeded(): Pair<MangaLibrarySnapshot, Boolean> {
        val current = mangaStore.read()
        if (current.hasUserData) {
            return current to false
        }

        val imported = backupFileStore.read()
            ?.payload
            ?.toMangaLibrarySnapshot()
            ?.takeIf(MangaLibrarySnapshot::hasUserData)
            ?: return current to false

        mangaStore.write(imported)
        return imported to true
    }
}

private fun MangaLibrarySnapshot.toOverview(importedFromBackup: Boolean): MangaOverviewSnapshot {
    val progressEntries = readingProgress.entries
        .sortedByDescending { (_, progress) -> progress.lastReadDate.orEmpty() }
        .take(8)

    return MangaOverviewSnapshot(
        collections = collections,
        recentProgress = progressEntries.map { (id, progress) -> id to progress },
        modules = modules,
        savedCount = collections.flatMap(MangaLibraryCollection::items)
            .distinctBy { item -> item.aniListId }
            .size,
        readChapterCount = readingProgress.values.sumOf { progress -> progress.readChapterNumbers.size },
        novelCount = readingProgress.values.count { progress -> progress.isNovel == true || progress.format == "NOVEL" },
        importedFromBackup = importedFromBackup,
    )
}
