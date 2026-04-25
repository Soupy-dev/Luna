package dev.soupy.eclipse.android.data

internal enum class DownloadSourceKind {
    WAITING_FOR_SOURCE,
    BLOCKED_TORRENT,
    UNSUPPORTED_SOURCE,
    HLS_PLAYLIST,
    DIRECT_HTTP,
}

internal fun classifyDownloadSource(sourceUri: String?): DownloadSourceKind {
    val clean = sourceUri?.trim().orEmpty()
    return when {
        clean.isBlank() -> DownloadSourceKind.WAITING_FOR_SOURCE
        clean.isTorrentLikeSourceUri() -> DownloadSourceKind.BLOCKED_TORRENT
        !clean.isDirectHttpDownloadUrl() -> DownloadSourceKind.UNSUPPORTED_SOURCE
        clean.isHlsPlaylistSource() -> DownloadSourceKind.HLS_PLAYLIST
        else -> DownloadSourceKind.DIRECT_HTTP
    }
}

internal fun String.isDirectHttpDownloadUrl(): Boolean =
    startsWith("http://", ignoreCase = true) || startsWith("https://", ignoreCase = true)

internal fun String.isTorrentLikeSourceUri(): Boolean {
    val clean = trim()
    return clean.startsWith("magnet:", ignoreCase = true) ||
        clean.contains("btih:", ignoreCase = true) ||
        clean.substringBefore('?').substringBefore('#').endsWith(".torrent", ignoreCase = true)
}

internal fun String.isHlsPlaylistSource(): Boolean =
    substringBefore('?').substringBefore('#').endsWith(".m3u8", ignoreCase = true)
