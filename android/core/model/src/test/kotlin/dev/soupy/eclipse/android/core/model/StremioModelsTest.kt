package dev.soupy.eclipse.android.core.model

import kotlin.test.Test
import kotlin.test.assertEquals
import kotlin.test.assertNull
import kotlin.test.assertTrue

class StremioModelsTest {
    @Test
    fun buildsImdbSeriesIdsWhenAddonSupportsImdb() {
        val manifest = StremioManifest(
            id = "addon",
            name = "Addon",
            idPrefixes = listOf("tt"),
        )

        val id = manifest.buildContentId(
            StremioContentIdRequest(
                tmdbId = 100,
                imdbId = "1234567",
                type = "series",
                season = 2,
                episode = 5,
            ),
        )

        assertEquals("tt1234567:2:5", id)
    }

    @Test
    fun fallsBackToTmdbWhenAddonDoesNotSupportImdb() {
        val manifest = StremioManifest(
            id = "addon",
            name = "Addon",
            idPrefixes = listOf("tmdb:"),
        )

        val id = manifest.buildContentId(
            StremioContentIdRequest(
                tmdbId = 100,
                imdbId = "tt1234567",
                type = "movie",
            ),
        )

        assertEquals("tmdb:100", id)
    }

    @Test
    fun returnsNullWhenNoSupportedPrefixCanBeBuilt() {
        val manifest = StremioManifest(
            id = "addon",
            name = "Addon",
            idPrefixes = listOf("kitsu:"),
        )

        assertNull(
            manifest.buildContentId(
                StremioContentIdRequest(
                    tmdbId = 100,
                    imdbId = "tt1234567",
                    type = "movie",
                ),
            ),
        )
    }

    @Test
    fun scoresHighQualityDirectStreamsAboveLowQualityStreams() {
        val remux = StremioStream(
            title = "Movie 2160p HDR BluRay Remux",
            url = "https://cdn.example/movie.mkv",
        )
        val cam = StremioStream(
            title = "Movie HDCAM",
            url = "https://cdn.example/cam.mp4",
        )

        assertTrue(remux.isDirectHttp)
        assertTrue(remux.qualityScore() > cam.qualityScore())
        assertTrue(remux.qualityScore() > 0.9)
    }
}
