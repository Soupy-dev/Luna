package dev.soupy.eclipse.android.data

import dev.soupy.eclipse.android.core.model.DetailTarget
import dev.soupy.eclipse.android.core.model.DownloadRecord
import dev.soupy.eclipse.android.core.model.DownloadSnapshot
import dev.soupy.eclipse.android.core.model.DownloadStatus
import dev.soupy.eclipse.android.core.model.PlayerSource
import dev.soupy.eclipse.android.core.model.SubtitleTrack
import dev.soupy.eclipse.android.core.storage.DownloadsStore
import java.io.File
import java.net.HttpURLConnection
import java.net.URL
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.withContext

private const val BufferSize = 64 * 1024

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
    private val downloadEngine = DirectFileDownloadEngine(downloadsStore)

    suspend fun loadSnapshot(): Result<DownloadSnapshot> = runCatching {
        downloadsStore.read().normalized()
    }

    suspend fun queueDownload(draft: DownloadDraft): Result<DownloadSnapshot> = runCatching {
        val snapshot = downloadsStore.read()
        val key = draft.detailTarget.downloadKey()
        val existing = snapshot.items.firstOrNull { it.id == key }
        val queued = draft.toRecord(
            id = key,
            existing = existing,
        )
        val withQueued = writeSnapshot(
            snapshot.copy(
                items = listOf(queued) + snapshot.items.filterNot { it.id == key },
            ),
        )

        val sourceUri = queued.sourceUri
        when {
            sourceUri == null -> withQueued
            !sourceUri.isDirectHttpUrl() -> writeRecord(
                queued.copy(
                    status = DownloadStatus.FAILED,
                    progressLabel = "Only direct HTTP(S) streams can be downloaded by Android right now.",
                    error = "Unsupported source URI: $sourceUri",
                ),
            )
            sourceUri.isHlsPlaylist() -> writeRecord(
                queued.copy(
                    status = DownloadStatus.FAILED,
                    progressLabel = "HLS playlist downloads are recognized, but segment packaging is the next offline milestone.",
                    error = "HLS packaging pending",
                ),
            )
            else -> {
                writeRecord(
                    queued.copy(
                        status = DownloadStatus.DOWNLOADING,
                        progressLabel = "Downloading direct stream into Android app storage.",
                    ),
                )
                writeRecord(downloadEngine.download(queued))
            }
        }
    }

    suspend fun pause(id: String): Result<DownloadSnapshot> = update(id) { current ->
        current.copy(
            status = DownloadStatus.PAUSED,
            progressLabel = current.progressLabel ?: "Paused before a background-capable worker picked it up.",
        )
    }

    suspend fun resume(id: String): Result<DownloadSnapshot> = update(id) { current ->
        current.copy(
            status = DownloadStatus.QUEUED,
            progressLabel = current.localUri?.let { "Queued to verify the existing offline file." }
                ?: "Queued to retry the direct download.",
            error = null,
        )
    }

    suspend fun markComplete(id: String): Result<DownloadSnapshot> = update(id) { current ->
        current.copy(
            status = DownloadStatus.COMPLETED,
            progressPercent = 1f,
            progressLabel = current.localUri?.let { "Offline file is available in Android app storage." }
                ?: "Marked complete manually.",
            error = null,
        )
    }

    suspend fun remove(id: String): Result<DownloadSnapshot> = runCatching {
        val snapshot = downloadsStore.read()
        snapshot.items.firstOrNull { it.id == id }?.let { record ->
            deleteDownloadedFiles(record)
        }
        writeSnapshot(snapshot.copy(items = snapshot.items.filterNot { it.id == id }))
    }

    suspend fun clearCompleted(): Result<DownloadSnapshot> = runCatching {
        val snapshot = downloadsStore.read()
        snapshot.items
            .filter { it.status == DownloadStatus.COMPLETED }
            .forEach(::deleteDownloadedFiles)
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

    private suspend fun writeRecord(record: DownloadRecord): DownloadSnapshot {
        val snapshot = downloadsStore.read()
        return writeSnapshot(
            snapshot.copy(
                items = listOf(record.copy(updatedAt = System.currentTimeMillis())) +
                    snapshot.items.filterNot { it.id == record.id },
            ),
        )
    }

    private suspend fun writeSnapshot(snapshot: DownloadSnapshot): DownloadSnapshot {
        val normalized = snapshot.normalized()
        downloadsStore.write(normalized)
        return normalized
    }

    private fun deleteDownloadedFiles(record: DownloadRecord) {
        val directory = downloadsStore.downloadsDirectory()
        listOfNotNull(record.localFileName)
            .plus(record.subtitleFileNames)
            .forEach { name ->
                File(directory, name).takeIf { file -> file.exists() }?.delete()
            }
    }
}

private class DirectFileDownloadEngine(
    private val downloadsStore: DownloadsStore,
) {
    suspend fun download(record: DownloadRecord): DownloadRecord = withContext(Dispatchers.IO) {
        val sourceUri = record.sourceUri ?: return@withContext record.copy(
            status = DownloadStatus.FAILED,
            error = "No source URI was captured for this download.",
        )

        runCatching {
            val directory = downloadsStore.downloadsDirectory()
            val outputFile = File(directory, record.outputFileName(sourceUri))
            var downloadedBytes = 0L
            var totalBytes = 0L

            val connection = URL(sourceUri).openConnection() as HttpURLConnection
            try {
                connection.instanceFollowRedirects = true
                record.requestHeaders.forEach { (name, value) ->
                    connection.setRequestProperty(name, value)
                }
                connection.connectTimeout = 20_000
                connection.readTimeout = 30_000
                connection.connect()

                val status = connection.responseCode
                if (status !in 200..299) {
                    error("HTTP $status while downloading ${record.title}")
                }

                totalBytes = connection.contentLengthLong.coerceAtLeast(0L)
                connection.inputStream.use { input ->
                    outputFile.outputStream().use { output ->
                        val buffer = ByteArray(BufferSize)
                        while (true) {
                            val read = input.read(buffer)
                            if (read < 0) break
                            output.write(buffer, 0, read)
                            downloadedBytes += read
                        }
                    }
                }
            } finally {
                connection.disconnect()
            }

            val subtitleFiles = record.subtitleTracks.downloadSubtitles(directory, record.id)
            record.copy(
                status = DownloadStatus.COMPLETED,
                progressPercent = 1f,
                progressLabel = buildString {
                    append("Downloaded ")
                    append(downloadedBytes.toByteCountLabel())
                    if (subtitleFiles.isNotEmpty()) {
                        append(" with ${subtitleFiles.size} subtitle file")
                        if (subtitleFiles.size != 1) append("s")
                    }
                    append(" into Android app storage.")
                },
                downloadedBytes = downloadedBytes,
                totalBytes = totalBytes.takeIf { it > 0 } ?: downloadedBytes,
                localFileName = outputFile.name,
                localUri = outputFile.toURI().toString(),
                subtitleFileNames = subtitleFiles,
                error = null,
            )
        }.getOrElse { error ->
            record.copy(
                status = DownloadStatus.FAILED,
                progressLabel = "Direct download failed: ${error.message ?: "unknown error"}",
                error = error.message ?: error::class.simpleName,
            )
        }
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
            "Direct stream captured. Android will attempt an offline file transfer now."
        } else {
            "Queued for offline preparation while Android waits for source resolution."
        },
        sourceLabel = sourceLabel
            ?: resolvedSource?.title
            ?: existing?.sourceLabel
            ?: "Pending source resolution",
        sourceUri = resolvedSource?.uri ?: existing?.sourceUri,
        mimeType = resolvedSource?.mimeType ?: existing?.mimeType,
        requestHeaders = resolvedSource?.headers ?: existing?.requestHeaders.orEmpty(),
        subtitleTracks = resolvedSource?.subtitles ?: existing?.subtitleTracks.orEmpty(),
        downloadedBytes = existing?.downloadedBytes ?: 0,
        totalBytes = existing?.totalBytes ?: 0,
        localFileName = existing?.localFileName,
        localUri = existing?.localUri,
        subtitleFileNames = existing?.subtitleFileNames.orEmpty(),
        error = null,
        addedAt = existing?.addedAt ?: System.currentTimeMillis(),
        updatedAt = System.currentTimeMillis(),
    )
}

private fun List<SubtitleTrack>.downloadSubtitles(directory: File, downloadId: String): List<String> =
    mapIndexedNotNull { index, subtitle ->
        val subtitleUri = subtitle.uri?.takeIf { it.isDirectHttpUrl() } ?: return@mapIndexedNotNull null
        runCatching {
            val extension = subtitleUri.fileExtension(default = "vtt")
            val file = File(directory, "${downloadId.safeFileStem()}_sub_${index + 1}.$extension")
            val connection = URL(subtitleUri).openConnection() as HttpURLConnection
            try {
                connection.instanceFollowRedirects = true
                connection.connectTimeout = 15_000
                connection.readTimeout = 20_000
                connection.connect()
                if (connection.responseCode !in 200..299) return@runCatching null
                connection.inputStream.use { input ->
                    file.outputStream().use { output -> input.copyTo(output) }
                }
                file.name
            } finally {
                connection.disconnect()
            }
        }.getOrNull()
    }

private fun DownloadRecord.outputFileName(sourceUri: String): String {
    val extension = sourceUri.fileExtension(
        default = when {
            mimeType?.contains("mp4", ignoreCase = true) == true -> "mp4"
            mimeType?.contains("matroska", ignoreCase = true) == true -> "mkv"
            else -> "mp4"
        },
    )
    return "${id.safeFileStem()}.$extension"
}

private fun DetailTarget.downloadKey(): String = when (this) {
    is DetailTarget.AniListMediaTarget -> "download:anilist:$id"
    is DetailTarget.TmdbMovie -> "download:tmdb_movie:$id"
    is DetailTarget.TmdbShow -> "download:tmdb_show:$id"
}

private fun String.isDirectHttpUrl(): Boolean =
    startsWith("http://", ignoreCase = true) || startsWith("https://", ignoreCase = true)

private fun String.isHlsPlaylist(): Boolean =
    substringBefore('?').endsWith(".m3u8", ignoreCase = true)

private fun String.fileExtension(default: String): String {
    val cleanPath = substringBefore('?').substringBefore('#')
    val extension = cleanPath.substringAfterLast('.', missingDelimiterValue = "")
        .takeIf { it.length in 2..5 && it.all(Char::isLetterOrDigit) }
        ?: default
    return extension.lowercase()
}

private fun String.safeFileStem(): String = replace(Regex("[^A-Za-z0-9._-]+"), "_")
    .trim('_')
    .ifBlank { "download_${System.currentTimeMillis()}" }

private fun Long.toByteCountLabel(): String {
    if (this < 1_000) return "$this B"
    val units = listOf("KB", "MB", "GB")
    var value = this / 1_000.0
    var unit = units.first()
    for (candidate in units.drop(1)) {
        if (value < 1_000.0) break
        value /= 1_000.0
        unit = candidate
    }
    return String.format("%.1f %s", value, unit)
}
