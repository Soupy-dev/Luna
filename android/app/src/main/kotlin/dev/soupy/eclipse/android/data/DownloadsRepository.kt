package dev.soupy.eclipse.android.data

import dev.soupy.eclipse.android.core.model.DetailTarget
import dev.soupy.eclipse.android.core.model.DownloadRecord
import dev.soupy.eclipse.android.core.model.DownloadSnapshot
import dev.soupy.eclipse.android.core.model.DownloadStatus
import dev.soupy.eclipse.android.core.model.PlayerSource
import dev.soupy.eclipse.android.core.storage.DownloadsStore

data class DownloadDraft(
    val detailTarget: DetailTarget,
    val title: String,
    val subtitle: String? = null,
    val imageUrl: String? = null,
    val backdropUrl: String? = null,
    val mediaLabel: String? = null,
    val progressLabel: String? = null,
    val sourceLabel: String? = null,
    val playerSource: PlayerSource? = null,
)

class DownloadsRepository(
    private val downloadsStore: DownloadsStore,
) {
    suspend fun loadSnapshot(): Result<DownloadSnapshot> = runCatching {
        downloadsStore.read().normalized()
    }

    suspend fun queueDownload(draft: DownloadDraft): Result<DownloadSnapshot> = runCatching {
        val snapshot = downloadsStore.read()
        val key = draft.detailTarget.downloadKey()
        val existing = snapshot.items.firstOrNull { it.id == key }
        writeSnapshot(
            snapshot.copy(
                items = listOf(
                    draft.toRecord(
                        id = key,
                        existing = existing,
                    ),
                ) + snapshot.items.filterNot { it.id == key },
            ),
        )
    }

    suspend fun pause(id: String): Result<DownloadSnapshot> = update(id) { current ->
        current.copy(
            status = DownloadStatus.PAUSED,
            progressLabel = current.progressLabel ?: "Paused before source resolution finished.",
        )
    }

    suspend fun resume(id: String): Result<DownloadSnapshot> = update(id) { current ->
        current.copy(
            status = DownloadStatus.QUEUED,
            progressLabel = current.progressLabel ?: "Queued to resume once the Android downloader is wired.",
        )
    }

    suspend fun markComplete(id: String): Result<DownloadSnapshot> = update(id) { current ->
        current.copy(
            status = DownloadStatus.COMPLETED,
            progressPercent = 1f,
            progressLabel = "Metadata and queue state are ready. Offline file packaging is the next milestone step.",
        )
    }

    suspend fun remove(id: String): Result<DownloadSnapshot> = runCatching {
        val snapshot = downloadsStore.read()
        writeSnapshot(snapshot.copy(items = snapshot.items.filterNot { it.id == id }))
    }

    suspend fun clearCompleted(): Result<DownloadSnapshot> = runCatching {
        val snapshot = downloadsStore.read()
        writeSnapshot(snapshot.copy(items = snapshot.items.filterNot { it.status == DownloadStatus.COMPLETED }))
    }

    private suspend fun update(
        id: String,
        transform: (DownloadRecord) -> DownloadRecord,
    ): Result<DownloadSnapshot> = runCatching {
        val snapshot = downloadsStore.read()
        val updated = snapshot.items.map { record ->
            if (record.id == id) {
                transform(record).copy(updatedAt = System.currentTimeMillis())
            } else {
                record
            }
        }
        writeSnapshot(snapshot.copy(items = updated))
    }

    private suspend fun writeSnapshot(snapshot: DownloadSnapshot): DownloadSnapshot {
        val normalized = snapshot.normalized()
        downloadsStore.write(normalized)
        return normalized
    }
}

private fun DownloadSnapshot.normalized(): DownloadSnapshot = copy(
    items = items
        .map { it.copy(progressPercent = it.progressPercent.coerceIn(0f, 1f)) }
        .sortedByDescending(DownloadRecord::updatedAt),
)

private fun DownloadDraft.toRecord(
    id: String,
    existing: DownloadRecord?,
): DownloadRecord {
    val resolvedSource = playerSource
    return DownloadRecord(
        id = id,
        detailTarget = detailTarget,
        title = title,
        subtitle = subtitle,
        imageUrl = imageUrl,
        backdropUrl = backdropUrl,
        mediaLabel = mediaLabel,
        status = DownloadStatus.QUEUED,
        progressPercent = existing?.takeIf { it.status != DownloadStatus.COMPLETED }?.progressPercent ?: 0f,
        progressLabel = progressLabel ?: if (resolvedSource != null) {
            "Direct stream metadata captured. Offline file transfer and packaging can now attach to this queue item."
        } else {
            "Queued for offline preparation while the Android resolver/download pipeline lands."
        },
        sourceLabel = sourceLabel
            ?: resolvedSource?.title
            ?: existing?.sourceLabel
            ?: "Pending source resolution",
        sourceUri = resolvedSource?.uri ?: existing?.sourceUri,
        mimeType = resolvedSource?.mimeType ?: existing?.mimeType,
        requestHeaders = resolvedSource?.headers ?: existing?.requestHeaders.orEmpty(),
        subtitleTracks = resolvedSource?.subtitles ?: existing?.subtitleTracks.orEmpty(),
        addedAt = existing?.addedAt ?: System.currentTimeMillis(),
        updatedAt = System.currentTimeMillis(),
    )
}

private fun DetailTarget.downloadKey(): String = when (this) {
    is DetailTarget.AniListMediaTarget -> "download:anilist:$id"
    is DetailTarget.TmdbMovie -> "download:tmdb_movie:$id"
    is DetailTarget.TmdbShow -> "download:tmdb_show:$id"
}
