package dev.soupy.eclipse.android.core.model

import kotlinx.serialization.SerialName
import kotlinx.serialization.Serializable
import kotlinx.serialization.json.JsonElement
import kotlinx.serialization.json.JsonObject

@Serializable
data class MangaLibraryItem(
    val aniListId: Int,
    val title: String,
    @SerialName("coverURL") val coverUrl: String? = null,
    val format: String? = null,
    val totalChapters: Int? = null,
    val dateAdded: String? = null,
)

@Serializable
data class MangaLibraryCollection(
    @Serializable(with = StringOrNumberAsStringSerializer::class)
    val id: String = "",
    val name: String,
    val items: List<MangaLibraryItem> = emptyList(),
    val description: String? = null,
)

@Serializable
data class MangaProgress(
    val readChapterNumbers: Set<String> = emptySet(),
    val lastReadChapter: String? = null,
    val lastReadDate: String? = null,
    val pagePositions: Map<String, Int> = emptyMap(),
    val title: String? = null,
    @SerialName("coverURL") val coverUrl: String? = null,
    val format: String? = null,
    val totalChapters: Int? = null,
    val moduleUUID: String? = null,
    val contentParams: String? = null,
    val isNovel: Boolean? = null,
)

@Serializable
data class KanzenModuleRecord(
    @Serializable(with = StringOrNumberAsStringSerializer::class)
    val id: String = "",
    val sourceName: String = "",
    val authorName: String = "",
    val iconUrl: String? = null,
    val version: String = "",
    val language: String = "",
    val scriptUrl: String? = null,
    val isNovel: Boolean = false,
    val localPath: String? = null,
    val moduleUrl: String? = null,
    val isActive: Boolean = false,
    val moduleData: JsonElement = JsonObject(emptyMap()),
) {
    val displayName: String
        get() = sourceName.ifBlank { moduleUrl ?: scriptUrl ?: id.ifBlank { "Module" } }
}

@Serializable
data class MangaLibrarySnapshot(
    val collections: List<MangaLibraryCollection> = emptyList(),
    val readingProgress: Map<String, MangaProgress> = emptyMap(),
    val catalogs: List<BackupCatalog> = emptyList(),
    val modules: List<KanzenModuleRecord> = emptyList(),
) {
    val hasUserData: Boolean
        get() = collections.isNotEmpty() ||
            readingProgress.isNotEmpty() ||
            catalogs.isNotEmpty() ||
            modules.isNotEmpty()
}
