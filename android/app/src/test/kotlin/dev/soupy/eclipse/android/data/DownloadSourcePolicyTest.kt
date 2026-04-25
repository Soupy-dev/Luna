package dev.soupy.eclipse.android.data

import kotlin.test.Test
import kotlin.test.assertEquals
import kotlin.test.assertFalse
import kotlin.test.assertTrue

class DownloadSourcePolicyTest {
    @Test
    fun torrentLikeSourcesAreAlwaysBlocked() {
        val blocked = listOf(
            "magnet:?xt=urn:btih:1234",
            "https://example.com/movie.torrent",
            "https://example.com/movie.torrent?download=1",
            "https://example.com/stream?xt=urn:btih:abcd",
        )

        blocked.forEach { uri ->
            assertEquals(DownloadSourceKind.BLOCKED_TORRENT, classifyDownloadSource(uri))
        }
    }

    @Test
    fun directHttpAndHlsSourcesAreSeparated() {
        assertEquals(
            DownloadSourceKind.DIRECT_HTTP,
            classifyDownloadSource("https://cdn.example.com/video.mp4"),
        )
        assertEquals(
            DownloadSourceKind.HLS_PLAYLIST,
            classifyDownloadSource("https://cdn.example.com/master.m3u8?token=abc"),
        )
    }

    @Test
    fun missingOrUnsupportedSourcesCannotDownload() {
        assertEquals(DownloadSourceKind.WAITING_FOR_SOURCE, classifyDownloadSource(null))
        assertEquals(DownloadSourceKind.WAITING_FOR_SOURCE, classifyDownloadSource("   "))
        assertEquals(DownloadSourceKind.UNSUPPORTED_SOURCE, classifyDownloadSource("file:///tmp/video.mp4"))
        assertFalse("ftp://example.com/video.mp4".isDirectHttpDownloadUrl())
        assertTrue("https://example.com/video.mp4".isDirectHttpDownloadUrl())
    }
}
