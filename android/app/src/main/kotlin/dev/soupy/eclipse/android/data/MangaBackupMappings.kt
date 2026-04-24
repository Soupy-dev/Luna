package dev.soupy.eclipse.android.data

import dev.soupy.eclipse.android.core.model.BackupCollection
import dev.soupy.eclipse.android.core.model.BackupData
import dev.soupy.eclipse.android.core.model.KanzenModuleRecord
import dev.soupy.eclipse.android.core.model.MangaLibraryCollection
import dev.soupy.eclipse.android.core.model.MangaLibraryItem
import dev.soupy.eclipse.android.core.model.MangaLibrarySnapshot
import dev.soupy.eclipse.android.core.model.MangaProgress
import dev.soupy.eclipse.android.core.model.MangaProgressBackup
import dev.soupy.eclipse.android.core.model.ModuleBackup
import dev.soupy.eclipse.android.core.network.EclipseJson
import kotlinx.serialization.json.JsonObject
import kotlinx.serialization.json.JsonPrimitive
import kotlinx.serialization.json.booleanOrNull
import kotlinx.serialization.json.contentOrNull
import kotlinx.serialization.json.decodeFromJsonElement
import kotlinx.serialization.json.encodeToJsonElement

internal fun BackupData.toMangaLibrarySnapshot(): MangaLibrarySnapshot = MangaLibrarySnapshot(
    collections = mangaCollections.map(BackupCollection::toMangaLibraryCollection),
    readingProgress = mangaReadingProgress.mapValues { (_, progress) -> progress.toMangaProgress() },
    catalogs = mangaCatalogs,
    modules = kanzenModules.map(ModuleBackup::toKanzenModuleRecord),
)

internal fun MangaLibrarySnapshot.toBackupCollections(): List<BackupCollection> =
    collections.map { collection ->
        BackupCollection(
            id = collection.id,
            name = collection.name,
            description = collection.description,
            items = collection.items.map { item ->
                EclipseJson.encodeToJsonElement(MangaLibraryItem.serializer(), item)
            },
        )
    }

internal fun MangaLibrarySnapshot.toBackupProgress(): Map<String, MangaProgressBackup> =
    readingProgress.mapValues { (_, progress) -> progress.toBackup() }

internal fun MangaLibrarySnapshot.toBackupModules(): List<ModuleBackup> =
    modules.map(KanzenModuleRecord::toBackup)

private fun BackupCollection.toMangaLibraryCollection(): MangaLibraryCollection = MangaLibraryCollection(
    id = id,
    name = name,
    description = description,
    items = items.mapNotNull { element ->
        runCatching {
            EclipseJson.decodeFromJsonElement<MangaLibraryItem>(element)
        }.getOrNull()
    },
)

private fun MangaProgressBackup.toMangaProgress(): MangaProgress = MangaProgress(
    readChapterNumbers = readChapterNumbers,
    lastReadChapter = lastReadChapter,
    lastReadDate = lastReadDate,
    pagePositions = pagePositions,
    title = title,
    coverUrl = coverUrl,
    format = format,
    totalChapters = totalChapters,
    moduleUUID = moduleUUID,
    contentParams = contentParams,
    isNovel = isNovel,
)

private fun MangaProgress.toBackup(): MangaProgressBackup = MangaProgressBackup(
    readChapterNumbers = readChapterNumbers,
    lastReadChapter = lastReadChapter,
    lastReadDate = lastReadDate,
    pagePositions = pagePositions,
    title = title,
    coverUrl = coverUrl,
    format = format,
    totalChapters = totalChapters,
    moduleUUID = moduleUUID,
    contentParams = contentParams,
    isNovel = isNovel,
)

private fun ModuleBackup.toKanzenModuleRecord(): KanzenModuleRecord {
    val data = moduleData as? JsonObject
    val author = data?.getObject("author")
    return KanzenModuleRecord(
        id = id.ifBlank { moduleurl ?: manifestUrl ?: data?.string("sourceName").orEmpty() },
        sourceName = data?.string("sourceName") ?: name,
        authorName = author?.string("name").orEmpty(),
        iconUrl = data?.string("iconURL") ?: data?.string("iconUrl") ?: author?.string("iconURL") ?: author?.string("icon"),
        version = data?.string("version").orEmpty(),
        language = data?.string("language").orEmpty(),
        scriptUrl = data?.string("scriptURL") ?: data?.string("scriptUrl"),
        isNovel = data?.boolean("novel") ?: false,
        localPath = localPath,
        moduleUrl = moduleurl ?: manifestUrl,
        isActive = active,
        moduleData = moduleData,
    )
}

private fun KanzenModuleRecord.toBackup(): ModuleBackup = ModuleBackup(
    id = id,
    name = displayName,
    manifestUrl = moduleUrl,
    enabled = isActive,
    moduleData = moduleData,
    localPath = localPath,
    moduleurl = moduleUrl,
    isActive = isActive,
)

private fun JsonObject.getObject(key: String): JsonObject? = this[key] as? JsonObject

private fun JsonObject.string(key: String): String? = (this[key] as? JsonPrimitive)?.contentOrNull

private fun JsonObject.boolean(key: String): Boolean? = (this[key] as? JsonPrimitive)?.let { primitive ->
    primitive.booleanOrNull ?: primitive.contentOrNull?.toBooleanStrictOrNull()
}
