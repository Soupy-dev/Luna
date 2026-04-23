package dev.soupy.eclipse.android.data

import android.content.Context
import android.net.Uri
import dev.soupy.eclipse.android.core.model.BackupData
import dev.soupy.eclipse.android.core.model.BackupDocument
import dev.soupy.eclipse.android.core.model.ServiceBackup
import dev.soupy.eclipse.android.core.network.EclipseJson
import dev.soupy.eclipse.android.core.storage.BackupFileStore
import dev.soupy.eclipse.android.core.storage.ServiceDao
import dev.soupy.eclipse.android.core.storage.ServiceEntity
import dev.soupy.eclipse.android.core.storage.SettingsStore
import dev.soupy.eclipse.android.core.storage.StremioAddonDao
import dev.soupy.eclipse.android.core.storage.StremioAddonEntity
import java.time.Instant
import java.time.ZoneId
import java.time.format.DateTimeFormatter
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.flow.first
import kotlinx.coroutines.withContext

data class BackupStatusSnapshot(
    val hasLocalBackup: Boolean,
    val headline: String,
    val supportingText: String,
)

class BackupRepository(
    private val context: Context,
    private val backupFileStore: BackupFileStore,
    private val settingsStore: SettingsStore,
    private val serviceDao: ServiceDao,
    private val stremioAddonDao: StremioAddonDao,
) {
    suspend fun loadStatus(): Result<BackupStatusSnapshot> = runCatching {
        backupFileStore.read().toStatus()
    }

    suspend fun exportToUri(uri: Uri): Result<BackupStatusSnapshot> = runCatching {
        val document = buildDocument()
        val raw = document.encode(EclipseJson)
        writeUri(uri, raw)
        backupFileStore.write(document)
        document.toStatus(
            headline = "Backup exported",
            supportingPrefix = "Saved settings plus ${document.payload.services.size} services and ${document.payload.stremioAddons.size} addons to your selected JSON archive.",
        )
    }

    suspend fun importFromUri(uri: Uri): Result<BackupStatusSnapshot> = runCatching {
        val document = BackupDocument.decode(EclipseJson, readUri(uri))
        applyPayload(document.payload)
        backupFileStore.write(document)
        document.toStatus(
            headline = "Backup imported",
            supportingPrefix = "Restored Android-owned settings plus ${document.payload.services.size} services and ${document.payload.stremioAddons.size} addons from the selected archive.",
        )
    }

    private suspend fun buildDocument(): BackupDocument {
        val existing = backupFileStore.read()
        val payload = existing?.payload
        val settings = settingsStore.settings.first()
        val services = serviceDao.observeAll().first()
        val addons = stremioAddonDao.observeAll().first()

        return BackupDocument(
            payload = BackupData(
                version = maxOf(payload?.version ?: 1, 1),
                createdDate = Instant.now().toString(),
                accentColor = settings.accentColor,
                tmdbLanguage = settings.tmdbLanguage,
                selectedAppearance = payload?.selectedAppearance,
                inAppPlayer = settings.inAppPlayer,
                holdSpeedPlayer = payload?.holdSpeedPlayer ?: true,
                externalPlayer = payload?.externalPlayer,
                alwaysLandscape = payload?.alwaysLandscape ?: false,
                aniSkipAutoSkip = payload?.aniSkipAutoSkip ?: false,
                skip85sEnabled = payload?.skip85sEnabled ?: false,
                showNextEpisodeButton = settings.showNextEpisodeButton,
                nextEpisodeThreshold = settings.nextEpisodeThreshold,
                vlcHeaderProxyEnabled = payload?.vlcHeaderProxyEnabled ?: false,
                collections = payload?.collections.orEmpty(),
                progressData = payload?.progressData.orEmpty(),
                trackerState = payload?.trackerState,
                catalogs = payload?.catalogs.orEmpty(),
                services = services.map(ServiceEntity::toBackup),
                stremioAddons = addons.map(StremioAddonEntity::toBackup),
                mangaCollections = payload?.mangaCollections.orEmpty(),
                mangaProgressData = payload?.mangaProgressData.orEmpty(),
                mangaCatalogs = payload?.mangaCatalogs.orEmpty(),
                kanzenModules = payload?.kanzenModules.orEmpty(),
                recommendationCache = payload?.recommendationCache.orEmpty(),
                userRatings = payload?.userRatings.orEmpty(),
            ),
            unknownKeys = existing?.unknownKeys.orEmpty(),
        )
    }

    private suspend fun applyPayload(payload: BackupData) {
        settingsStore.restoreFromBackup(payload)
        val importedServices = syncServices(payload.services)
        val importedAddons = syncAddons(payload.stremioAddons)
        settingsStore.retainAutoModeSources(
            importedServices.mapTo(mutableSetOf()) { "service:${it.id}" }
                .apply { addAll(importedAddons.map { "stremio:${it.transportUrl}" }) },
        )
    }

    private suspend fun syncServices(backups: List<ServiceBackup>): List<ServiceEntity> {
        val current = serviceDao.observeAll().first()
        val currentById = current.associateBy(ServiceEntity::id)
        val now = System.currentTimeMillis()
        val imported = backups.mapIndexed { index, backup ->
            val id = backup.id.ifBlank { backup.name.slugified() }
            val currentEntity = currentById[id]
            val inferredScriptUrl = backup.scriptUrl ?: backup.manifestUrl?.takeIf {
                backup.sourceKind.equals("script", ignoreCase = true)
            }
            val manifestUrl = backup.manifestUrl?.takeUnless {
                inferredScriptUrl != null &&
                    backup.sourceKind.equals("script", ignoreCase = true) &&
                    it == inferredScriptUrl
            }
            val scriptUrl = inferredScriptUrl
            ServiceEntity(
                id = id,
                name = backup.name.ifBlank { id },
                manifestUrl = manifestUrl,
                scriptUrl = scriptUrl,
                enabled = backup.enabled,
                sortIndex = if (backups.any { it.sortIndex != 0 }) backup.sortIndex else index,
                sourceKind = backup.sourceKind ?: when {
                    scriptUrl != null && manifestUrl != null -> "manifest+script"
                    scriptUrl != null -> "script"
                    manifestUrl != null -> "manifest"
                    else -> "backup"
                },
                configurationJson = backup.configurationJson ?: currentEntity?.configurationJson,
                createdAt = currentEntity?.createdAt ?: now,
                updatedAt = now,
            )
        }

        current.filterNot { existing -> imported.any { it.id == existing.id } }
            .forEach { stale -> serviceDao.delete(stale) }
        if (imported.isNotEmpty()) {
            serviceDao.upsert(imported)
        }
        return imported
    }

    private suspend fun syncAddons(backups: List<ServiceBackup>): List<StremioAddonEntity> {
        val current = stremioAddonDao.observeAll().first()
        val currentByTransport = current.associateBy(StremioAddonEntity::transportUrl)
        val now = System.currentTimeMillis()
        val imported = backups.mapIndexed { index, backup ->
            val transportUrl = backup.transportUrl
                ?: backup.manifestUrl
                ?: backup.id.ifBlank { "addon-${index + 1}" }
            val currentEntity = currentByTransport[transportUrl]
            StremioAddonEntity(
                transportUrl = transportUrl,
                manifestId = backup.id.ifBlank { transportUrl },
                name = backup.name.ifBlank { transportUrl },
                enabled = backup.enabled,
                sortIndex = if (backups.any { it.sortIndex != 0 }) backup.sortIndex else index,
                configured = transportUrl.isNotBlank(),
                manifestJson = currentEntity?.manifestJson,
                createdAt = currentEntity?.createdAt ?: now,
                updatedAt = now,
            )
        }

        current.filterNot { existing -> imported.any { it.transportUrl == existing.transportUrl } }
            .forEach { stale -> stremioAddonDao.delete(stale) }
        if (imported.isNotEmpty()) {
            stremioAddonDao.upsert(imported)
        }
        return imported
    }

    private suspend fun readUri(uri: Uri): String = withContext(Dispatchers.IO) {
        context.contentResolver.openInputStream(uri)?.bufferedReader()?.use { reader ->
            reader.readText()
        } ?: error("Couldn't open the selected backup file for reading.")
    }

    private suspend fun writeUri(uri: Uri, raw: String) = withContext(Dispatchers.IO) {
        context.contentResolver.openOutputStream(uri, "wt")?.bufferedWriter()?.use { writer ->
            writer.write(raw)
        } ?: error("Couldn't open the selected backup destination for writing.")
    }
}

private fun ServiceEntity.toBackup(): ServiceBackup = ServiceBackup(
    id = id,
    name = name,
    manifestUrl = manifestUrl,
    scriptUrl = scriptUrl,
    enabled = enabled,
    sortIndex = sortIndex,
    sourceKind = sourceKind,
    configurationJson = configurationJson,
)

private fun StremioAddonEntity.toBackup(): ServiceBackup = ServiceBackup(
    id = manifestId,
    name = name,
    manifestUrl = transportUrl,
    transportUrl = transportUrl,
    enabled = enabled,
    sortIndex = sortIndex,
    sourceKind = "stremio-addon",
)

private fun BackupDocument?.toStatus(): BackupStatusSnapshot = if (this == null) {
    BackupStatusSnapshot(
        hasLocalBackup = false,
        headline = "No local backup yet",
        supportingText = "Export a JSON archive from Settings or import an existing Luna backup to stage one on Android.",
    )
} else {
    toStatus(
        headline = "Local backup ready",
        supportingPrefix = "A Luna-compatible JSON archive is staged locally for re-export and future parity work.",
    )
}

private fun BackupDocument.toStatus(
    headline: String,
    supportingPrefix: String,
): BackupStatusSnapshot {
    val createdDate = payload.createdDate?.toReadableTimestamp() ?: "unknown date"
    val preservedSections = buildList {
        if (payload.collections.isNotEmpty()) add("collections")
        if (payload.progressData.isNotEmpty()) add("progress")
        if (payload.catalogs.isNotEmpty()) add("catalogs")
        if (payload.mangaCollections.isNotEmpty() || payload.mangaProgressData.isNotEmpty()) add("manga")
        if (payload.kanzenModules.isNotEmpty()) add("modules")
        if (payload.recommendationCache.isNotEmpty() || payload.userRatings.isNotEmpty()) add("personalization")
    }
    val preservationText = if (preservedSections.isEmpty()) {
        " The rest of the archive is ready for later Android parity work."
    } else {
        " Preserving ${preservedSections.joinToString()} data so a later export won't drop it while those Android flows are still being built."
    }

    return BackupStatusSnapshot(
        hasLocalBackup = true,
        headline = headline,
        supportingText = "$supportingPrefix Created $createdDate.$preservationText",
    )
}

private fun String.toReadableTimestamp(): String = runCatching {
    Instant.parse(this)
        .atZone(ZoneId.systemDefault())
        .format(DateTimeFormatter.ofPattern("yyyy-MM-dd HH:mm"))
}.getOrElse { this }

private fun String.slugified(): String = trim()
    .lowercase()
    .replace(Regex("[^a-z0-9]+"), "-")
    .trim('-')
    .ifBlank { "service-${System.currentTimeMillis()}" }
