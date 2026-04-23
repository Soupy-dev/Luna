package dev.soupy.eclipse.android.core.model

import kotlinx.serialization.Serializable

@Serializable
enum class DownloadStatus {
    QUEUED,
    PAUSED,
    COMPLETED,
    FAILED,
}

@Serializable
data class DownloadRecord(
    val id: String,
    val detailTarget: DetailTarget,
    val title: String,
    val subtitle: String? = null,
    val imageUrl: String? = null,
    val backdropUrl: String? = null,
    val mediaLabel: String? = null,
    val status: DownloadStatus = DownloadStatus.QUEUED,
    val progressPercent: Float = 0f,
    val progressLabel: String? = null,
    val sourceLabel: String? = null,
    val sourceUri: String? = null,
    val mimeType: String? = null,
    val requestHeaders: Map<String, String> = emptyMap(),
    val subtitleTracks: List<SubtitleTrack> = emptyList(),
    val addedAt: Long = System.currentTimeMillis(),
    val updatedAt: Long = System.currentTimeMillis(),
)

@Serializable
data class DownloadSnapshot(
    val items: List<DownloadRecord> = emptyList(),
)
