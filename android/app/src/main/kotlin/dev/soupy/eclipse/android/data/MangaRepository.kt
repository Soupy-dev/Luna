package dev.soupy.eclipse.android.data

import dev.soupy.eclipse.android.core.model.KanzenModuleRecord
import dev.soupy.eclipse.android.core.model.AniListMedia
import dev.soupy.eclipse.android.core.model.MangaLibraryItem
import dev.soupy.eclipse.android.core.model.MangaLibraryCollection
import dev.soupy.eclipse.android.core.model.MangaLibrarySnapshot
import dev.soupy.eclipse.android.core.model.MangaProgress
import dev.soupy.eclipse.android.core.model.displayTitle
import dev.soupy.eclipse.android.core.model.posterUrl
import dev.soupy.eclipse.android.core.network.AniListService
import dev.soupy.eclipse.android.core.network.EclipseHttpClient
import dev.soupy.eclipse.android.core.network.EclipseJson
import dev.soupy.eclipse.android.core.storage.BackupFileStore
import dev.soupy.eclipse.android.core.storage.MangaStore
import java.net.URI
import java.time.Instant
import kotlinx.coroutines.async
import kotlinx.coroutines.coroutineScope
import kotlinx.serialization.SerializationException
import kotlinx.serialization.json.JsonElement
import kotlinx.serialization.json.JsonObject
import kotlinx.serialization.json.JsonPrimitive
import kotlinx.serialization.json.booleanOrNull
import kotlinx.serialization.json.contentOrNull
import kotlinx.serialization.json.jsonObject

private const val DefaultMangaCollectionId = "android-library"
private const val DefaultMangaCollectionName = "Library"

data class MangaCatalogSectionSnapshot(
    val id: String,
    val title: String,
    val items: List<MangaCatalogItemSnapshot>,
)

data class MangaCatalogItemSnapshot(
    val id: String,
    val aniListId: Int,
    val title: String,
    val subtitle: String,
    val coverUrl: String? = null,
    val description: String? = null,
    val format: String? = null,
    val totalChapters: Int? = null,
    val isSaved: Boolean = false,
)

data class MangaLibraryItemDraft(
    val aniListId: Int,
    val title: String,
    val coverUrl: String? = null,
    val format: String? = null,
    val totalChapters: Int? = null,
)

data class KanzenModuleDraft(
    val moduleUrl: String,
    val displayName: String? = null,
    val isNovel: Boolean = false,
)

private data class FetchedKanzenModule(
    val sourceName: String,
    val authorName: String,
    val iconUrl: String?,
    val version: String,
    val language: String,
    val scriptUrl: String,
    val isNovel: Boolean,
    val moduleData: JsonObject,
)

data class MangaOverviewSnapshot(
    val collections: List<MangaLibraryCollection>,
    val recentProgress: List<Pair<String, MangaProgress>>,
    val recentNovelProgress: List<Pair<String, MangaProgress>>,
    val modules: List<KanzenModuleRecord>,
    val catalogs: List<MangaCatalogSectionSnapshot>,
    val savedCount: Int,
    val readChapterCount: Int,
    val novelCount: Int,
    val novelReadChapterCount: Int,
    val importedFromBackup: Boolean,
)

class MangaRepository(
    private val mangaStore: MangaStore,
    private val backupFileStore: BackupFileStore,
    private val aniListService: AniListService,
    private val httpClient: EclipseHttpClient = EclipseHttpClient(),
) {
    suspend fun loadOverview(): Result<MangaOverviewSnapshot> = runCatching {
        coroutineScope {
            val backupDeferred = async { seedFromBackupIfNeeded() }
            val catalogsDeferred = async { aniListService.fetchMangaCatalogs(perPage = 12).orNull() }
            val (snapshot, importedFromBackup) = backupDeferred.await()
            snapshot.toOverview(
                importedFromBackup = importedFromBackup,
                catalogs = catalogsDeferred.await().toCatalogSections(
                    savedAniListIds = snapshot.savedAniListIds(),
                    label = "Manga",
                ),
            )
        }
    }

    suspend fun loadNovelOverview(): Result<MangaOverviewSnapshot> = runCatching {
        coroutineScope {
            val backupDeferred = async { seedFromBackupIfNeeded() }
            val catalogsDeferred = async { aniListService.fetchNovelCatalogs(perPage = 12).orNull() }
            val (snapshot, importedFromBackup) = backupDeferred.await()
            snapshot.toOverview(
                importedFromBackup = importedFromBackup,
                catalogs = catalogsDeferred.await().toCatalogSections(
                    savedAniListIds = snapshot.savedAniListIds(),
                    label = "Novels",
                ),
            )
        }
    }

    suspend fun searchManga(query: String): Result<List<MangaCatalogItemSnapshot>> = runCatching {
        val trimmed = query.trim()
        if (trimmed.isBlank()) return@runCatching emptyList()
        val savedIds = mangaStore.read().savedAniListIds()
        aniListService.searchManga(
            query = trimmed,
            page = 1,
            perPage = 24,
        ).orThrow().media.toCatalogItems(savedIds)
    }

    suspend fun searchNovels(query: String): Result<List<MangaCatalogItemSnapshot>> = runCatching {
        val trimmed = query.trim()
        if (trimmed.isBlank()) return@runCatching emptyList()
        val savedIds = mangaStore.read().savedAniListIds()
        aniListService.searchNovels(
            query = trimmed,
            page = 1,
            perPage = 24,
        ).orThrow().media.toCatalogItems(savedIds)
    }

    suspend fun saveToLibrary(draft: MangaLibraryItemDraft): Result<MangaLibrarySnapshot> = runCatching {
        require(draft.aniListId > 0) { "Saving manga requires an AniList id." }
        require(draft.title.isNotBlank()) { "Saving manga requires a title." }
        val snapshot = seedFromBackupIfNeeded().first
        val item = MangaLibraryItem(
            aniListId = draft.aniListId,
            title = draft.title,
            coverUrl = draft.coverUrl,
            format = draft.format,
            totalChapters = draft.totalChapters,
            dateAdded = Instant.now().toString(),
        )
        val updated = snapshot.copy(
            collections = snapshot.collections.withSavedManga(item),
        )
        mangaStore.write(updated)
        updated
    }

    suspend fun removeFromLibrary(aniListId: Int): Result<MangaLibrarySnapshot> = runCatching {
        require(aniListId > 0) { "Removing manga requires an AniList id." }
        val snapshot = mangaStore.read()
        val updated = snapshot.copy(
            collections = snapshot.collections.map { collection ->
                collection.copy(items = collection.items.filterNot { item -> item.aniListId == aniListId })
            }.filterNot { collection ->
                collection.id == DefaultMangaCollectionId && collection.items.isEmpty()
            },
        )
        mangaStore.write(updated)
        updated
    }

    suspend fun clearReadingProgress(progressId: String): Result<MangaLibrarySnapshot> = runCatching {
        require(progressId.isNotBlank()) { "Reading progress id is required." }
        val snapshot = seedFromBackupIfNeeded().first
        val updated = snapshot.copy(
            readingProgress = snapshot.readingProgress - progressId,
        )
        mangaStore.write(updated)
        updated
    }

    suspend fun addModule(draft: KanzenModuleDraft): Result<MangaLibrarySnapshot> = runCatching {
        val normalizedUrl = draft.moduleUrl.normalizedKanzenModuleUrl()
        val snapshot = seedFromBackupIfNeeded().first
        val manifest = fetchAndValidateKanzenModule(
            httpClient = httpClient,
            moduleUrl = normalizedUrl,
            requestedNovel = draft.isNovel,
            displayNameOverride = draft.displayName,
        )
        val existing = snapshot.modules.firstOrNull { module ->
            module.moduleUrl.equals(normalizedUrl, ignoreCase = true) ||
                module.scriptUrl.equals(manifest.scriptUrl, ignoreCase = true)
        }
        val id = existing?.id?.takeIf(String::isNotBlank) ?: normalizedUrl.toModuleId()
        val record = KanzenModuleRecord(
            id = id,
            sourceName = manifest.sourceName,
            authorName = manifest.authorName,
            iconUrl = manifest.iconUrl,
            version = manifest.version,
            language = manifest.language,
            scriptUrl = manifest.scriptUrl,
            isNovel = manifest.isNovel,
            localPath = existing?.localPath,
            moduleUrl = normalizedUrl,
            isActive = true,
            moduleData = manifest.moduleData,
        )
        val updated = snapshot.copy(
            modules = listOf(record) + snapshot.modules.filterNot { module ->
                module.id == id ||
                    module.moduleUrl.equals(normalizedUrl, ignoreCase = true) ||
                    module.scriptUrl.equals(manifest.scriptUrl, ignoreCase = true)
            },
        )
        mangaStore.write(updated)
        updated
    }

    suspend fun setModuleActive(
        moduleId: String,
        active: Boolean,
    ): Result<MangaLibrarySnapshot> = runCatching {
        require(moduleId.isNotBlank()) { "Module id is required." }
        val snapshot = seedFromBackupIfNeeded().first
        val updated = snapshot.copy(
            modules = snapshot.modules.map { module ->
                if (module.id == moduleId) module.copy(isActive = active) else module
            },
        )
        mangaStore.write(updated)
        updated
    }

    suspend fun removeModule(moduleId: String): Result<MangaLibrarySnapshot> = runCatching {
        require(moduleId.isNotBlank()) { "Module id is required." }
        val snapshot = seedFromBackupIfNeeded().first
        val updated = snapshot.copy(
            modules = snapshot.modules.filterNot { module -> module.id == moduleId },
        )
        mangaStore.write(updated)
        updated
    }

    suspend fun updateModule(moduleId: String): Result<MangaLibrarySnapshot> = runCatching {
        require(moduleId.isNotBlank()) { "Module id is required." }
        val snapshot = seedFromBackupIfNeeded().first
        val existing = snapshot.modules.firstOrNull { module -> module.id == moduleId }
            ?: error("Kanzen module was not found.")
        val moduleUrl = existing.moduleUrl
            ?: existing.moduleData.jsonObjectOrNull()?.string("moduleURL")
            ?: existing.moduleData.jsonObjectOrNull()?.string("moduleUrl")
            ?: error("Kanzen module does not have an update URL.")
        val normalizedUrl = moduleUrl.normalizedKanzenModuleUrl()
        val manifest = fetchAndValidateKanzenModule(
            httpClient = httpClient,
            moduleUrl = normalizedUrl,
            requestedNovel = existing.isNovel,
            displayNameOverride = null,
        )
        val refreshed = existing.copy(
            sourceName = manifest.sourceName,
            authorName = manifest.authorName,
            iconUrl = manifest.iconUrl,
            version = manifest.version,
            language = manifest.language,
            scriptUrl = manifest.scriptUrl,
            isNovel = manifest.isNovel,
            moduleUrl = normalizedUrl,
            moduleData = manifest.moduleData,
        )
        val updated = snapshot.copy(
            modules = listOf(refreshed) + snapshot.modules.filterNot { module -> module.id == moduleId },
        )
        mangaStore.write(updated)
        updated
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

private suspend fun fetchAndValidateKanzenModule(
    httpClient: EclipseHttpClient,
    moduleUrl: String,
    requestedNovel: Boolean,
    displayNameOverride: String?,
): FetchedKanzenModule {
    val manifestRaw = httpClient.get(moduleUrl).orThrow()
    val manifestJson = runCatching {
        EclipseJson.parseToJsonElement(manifestRaw).jsonObject
    }.getOrElse { error ->
        throw SerializationException("Kanzen module manifest is not valid JSON.", error)
    }
    val scriptUrl = manifestJson.scriptUrl()
        ?.resolveAgainst(moduleUrl)
        ?: error("Kanzen module manifest is missing scriptURL.")
    val script = httpClient.get(scriptUrl).orThrow()
    script.validateKanzenScript()

    val author = manifestJson.getObject("author")
    val sourceName = displayNameOverride?.trim()?.takeIf(String::isNotBlank)
        ?: manifestJson.string("sourceName")
        ?: moduleUrl.toModuleDisplayName()
    val isNovel = manifestJson.boolean("novel") ?: requestedNovel
    val moduleData = manifestJson.withModuleMetadata(
        sourceName = sourceName,
        moduleUrl = moduleUrl,
        scriptUrl = scriptUrl,
        isNovel = isNovel,
    )
    return FetchedKanzenModule(
        sourceName = sourceName,
        authorName = author?.string("name").orEmpty(),
        iconUrl = manifestJson.string("iconURL")
            ?: manifestJson.string("iconUrl")
            ?: author?.string("iconURL")
            ?: author?.string("icon"),
        version = manifestJson.string("version").orEmpty(),
        language = manifestJson.string("language").orEmpty(),
        scriptUrl = scriptUrl,
        isNovel = isNovel,
        moduleData = moduleData,
    )
}

private fun MangaLibrarySnapshot.toOverview(
    importedFromBackup: Boolean,
    catalogs: List<MangaCatalogSectionSnapshot>,
): MangaOverviewSnapshot {
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
        catalogs = catalogs,
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

private fun AniListService.MangaCatalogs?.toCatalogSections(
    savedAniListIds: Set<Int>,
    label: String,
): List<MangaCatalogSectionSnapshot> =
    listOfNotNull(
        this?.trending?.toCatalogSection("trending", "Trending $label", savedAniListIds),
        this?.popular?.toCatalogSection("popular", "Popular $label", savedAniListIds),
        this?.topRated?.toCatalogSection("top-rated", "Top Rated $label", savedAniListIds),
        this?.recentlyUpdated?.toCatalogSection("updated", "Recently Updated", savedAniListIds),
    ).filter { it.items.isNotEmpty() }

private fun List<AniListMedia>.toCatalogSection(
    id: String,
    title: String,
    savedAniListIds: Set<Int>,
): MangaCatalogSectionSnapshot = MangaCatalogSectionSnapshot(
    id = id,
    title = title,
    items = take(12).toCatalogItems(savedAniListIds),
)

private fun List<AniListMedia>.toCatalogItems(
    savedAniListIds: Set<Int>,
): List<MangaCatalogItemSnapshot> =
    map { media ->
        MangaCatalogItemSnapshot(
            id = "anilist-manga-${media.id}",
            aniListId = media.id,
            title = media.displayTitle,
            subtitle = listOfNotNull(
                media.format?.replace('_', ' '),
                media.chapters?.let { "$it chapters" },
                media.volumes?.let { "$it volumes" },
                media.status?.replace('_', ' '),
            ).joinToString(" - "),
            coverUrl = media.posterUrl,
            description = media.description?.stripHtmlTags(),
            format = media.format,
            totalChapters = media.chapters,
            isSaved = media.id in savedAniListIds,
        )
    }

private fun MangaLibrarySnapshot.savedAniListIds(): Set<Int> =
    collections.flatMap(MangaLibraryCollection::items)
        .map(MangaLibraryItem::aniListId)
        .toSet()

private fun List<MangaLibraryCollection>.withSavedManga(
    item: MangaLibraryItem,
): List<MangaLibraryCollection> {
    val withoutDuplicate = map { collection ->
        collection.copy(items = collection.items.filterNot { existing -> existing.aniListId == item.aniListId })
    }
    val existingIndex = withoutDuplicate.indexOfFirst { collection ->
        collection.id == DefaultMangaCollectionId || collection.name.equals(DefaultMangaCollectionName, ignoreCase = true)
    }
    val targetCollection = if (existingIndex >= 0) {
        withoutDuplicate[existingIndex].copy(
            id = withoutDuplicate[existingIndex].id.ifBlank { DefaultMangaCollectionId },
            items = listOf(item) + withoutDuplicate[existingIndex].items,
        )
    } else {
        MangaLibraryCollection(
            id = DefaultMangaCollectionId,
            name = DefaultMangaCollectionName,
            description = "Saved on Android",
            items = listOf(item),
        )
    }

    return if (existingIndex >= 0) {
        withoutDuplicate.mapIndexed { index, collection ->
            if (index == existingIndex) targetCollection else collection
        }
    } else {
        listOf(targetCollection) + withoutDuplicate
    }
}

private fun String.normalizedKanzenModuleUrl(): String {
    val trimmed = trim()
    require(trimmed.isNotBlank()) { "Paste a Kanzen module URL first." }
    val uri = runCatching { URI(trimmed) }.getOrElse {
        throw IllegalArgumentException("Kanzen module URL is not valid.")
    }
    val scheme = uri.scheme?.lowercase()
    require(scheme == "http" || scheme == "https") { "Kanzen modules must use http or https URLs." }
    require(!uri.host.isNullOrBlank()) { "Kanzen module URL needs a host." }
    return uri.normalize().toString().trimEnd('/')
}

private fun String.toModuleId(): String =
    "kanzen-${hashCode().toUInt().toString(16)}"

private fun String.toModuleDisplayName(): String {
    val uri = runCatching { URI(this) }.getOrNull()
    val pathName = uri?.path
        ?.substringAfterLast('/')
        ?.substringBeforeLast('.')
        ?.takeIf(String::isNotBlank)
    return pathName ?: uri?.host?.removePrefix("www.") ?: "Kanzen Module"
}

private fun JsonElement?.withModuleMetadata(
    sourceName: String,
    moduleUrl: String,
    scriptUrl: String?,
    isNovel: Boolean,
): JsonObject {
    val current = this as? JsonObject ?: JsonObject(emptyMap())
    val preservedSourceName = current.string("sourceName")
    val preservedScriptUrl = current.string("scriptURL") ?: current.string("scriptUrl")
    return JsonObject(
        current + mapOf(
            "sourceName" to JsonPrimitive(preservedSourceName ?: sourceName),
            "moduleURL" to JsonPrimitive(moduleUrl),
            "moduleUrl" to JsonPrimitive(moduleUrl),
            "scriptURL" to JsonPrimitive(preservedScriptUrl ?: scriptUrl.orEmpty()),
            "novel" to JsonPrimitive(isNovel),
        ),
    )
}

private fun JsonObject.string(key: String): String? =
    (this[key] as? JsonPrimitive)?.contentOrNull

private fun JsonObject.boolean(key: String): Boolean? =
    (this[key] as? JsonPrimitive)?.let { primitive ->
        primitive.booleanOrNull ?: primitive.contentOrNull?.toBooleanStrictOrNull()
    }

private fun JsonObject.getObject(key: String): JsonObject? =
    this[key] as? JsonObject

private fun JsonElement.jsonObjectOrNull(): JsonObject? =
    this as? JsonObject

private fun JsonObject.scriptUrl(): String? =
    string("scriptURL") ?: string("scriptUrl")

private fun String.resolveAgainst(baseUrl: String): String {
    val uri = runCatching { URI(this) }.getOrNull()
    if (uri?.isAbsolute == true) return uri.normalize().toString()
    val base = URI(baseUrl)
    return base.resolve(this).normalize().toString()
}

private fun String.validateKanzenScript() {
    require(isNotBlank()) { "Kanzen script is empty." }
    require(Regex("""\bsearchResults\b""").containsMatchIn(this)) {
        "Kanzen script must define searchResults."
    }
    val extractors = listOf("extractDetails", "extractChapters", "extractImages", "extractText")
    require(extractors.any { functionName -> Regex("""\b$functionName\b""").containsMatchIn(this) }) {
        "Kanzen script must define at least one extract function."
    }
}
