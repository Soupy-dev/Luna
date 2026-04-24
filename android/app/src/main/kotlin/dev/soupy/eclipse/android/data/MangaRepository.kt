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
    val recentNovelProgress: List<Pair<String, MangaProgress>>,
    val modules: List<KanzenModuleRecord>,
    val savedCount: Int,
    val readChapterCount: Int,
    val novelCount: Int,
    val novelReadChapterCount: Int,
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
    val novelProgressEntries = readingProgress.entries
        .filter { (_, progress) -> progress.isNovelProgress }
        .sortedByDescending { (_, progress) -> progress.lastReadDate.orEmpty() }
        .take(8)
    val allNovelProgress = readingProgress.values.filter(MangaProgress::isNovelProgress)

    return MangaOverviewSnapshot(
        collections = collections,
        recentProgress = progressEntries.map { (id, progress) -> id to progress },
        recentNovelProgress = novelProgressEntries.map { (id, progress) -> id to progress },
        modules = modules,
        savedCount = collections.flatMap(MangaLibraryCollection::items)
            .distinctBy { item -> item.aniListId }
            .size,
        readChapterCount = readingProgress.values.sumOf { progress -> progress.readChapterNumbers.size },
        novelCount = allNovelProgress.size,
        novelReadChapterCount = allNovelProgress.sumOf { progress -> progress.readChapterNumbers.size },
        importedFromBackup = importedFromBackup,
    )
}

private val MangaProgress.isNovelProgress: Boolean
    get() = isNovel == true || format.equals("NOVEL", ignoreCase = true) || format.equals("LIGHT_NOVEL", ignoreCase = true)
