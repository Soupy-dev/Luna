package dev.soupy.eclipse.android.core.model

import kotlin.test.Test
import kotlin.test.assertEquals
import kotlin.test.assertNotNull
import kotlin.test.assertTrue
import kotlinx.serialization.json.Json
import kotlinx.serialization.json.jsonObject

class BackupDocumentTest {
    private val json = Json {
        ignoreUnknownKeys = true
        explicitNulls = false
    }

    @Test
    fun preservesUnknownKeysAcrossDecodeAndEncode() {
        val raw = """
            {
              "version": 1,
              "createdDate": "2026-04-23T00:00:00Z",
              "accentColor": "#6D8CFF",
              "futureAndroidField": {
                "enabled": true
              }
            }
        """.trimIndent()

        val document = BackupDocument.decode(json, raw)
        val encoded = document.encode(json)

        assertEquals("#6D8CFF", document.payload.accentColor)
        assertTrue("futureAndroidField" in document.unknownKeys)
        assertTrue(encoded.contains("futureAndroidField"))
    }

    @Test
    fun decodesModernIosBackupShape() {
        val raw = """
            {
              "version": "1.0",
              "createdDate": "2026-04-23T00:00:00Z",
              "tmdbLanguage": "en-US",
              "selectedAppearance": "dark",
              "enableSubtitlesByDefault": true,
              "defaultSubtitleLanguage": "eng",
              "preferredAnimeAudioLanguage": "jpn",
              "inAppPlayer": "VLC",
              "holdSpeedPlayer": 2.0,
              "externalPlayer": "org.videolan.vlc",
              "alwaysLandscape": true,
              "vlcHeaderProxyEnabled": false,
              "skip85sEnabled": true,
              "nextEpisodeThreshold": 0.9,
              "subtitleForegroundColor": "#FFFFFF",
              "subtitleStrokeColor": "#111111",
              "subtitleStrokeWidth": 2.5,
              "subtitleFontSize": 34.0,
              "subtitleVerticalOffset": -8.0,
              "showKanzen": true,
              "readerFontFamily": "Georgia",
              "collections": [
                {
                  "id": "8F5C2E48-77FB-430F-B904-AB0FEEA420A8",
                  "name": "Bookmarks",
                  "items": [
                    {
                      "id": "movie-1",
                      "searchResult": {
                        "id": 1,
                        "title": "Example"
                      }
                    }
                  ],
                  "description": "Saved items"
                }
              ],
              "progressData": {
                "movieProgress": [
                  {
                    "id": 1,
                    "title": "Example",
                    "currentTime": 42.0,
                    "totalDuration": 100.0,
                    "isWatched": false
                  }
                ],
                "episodeProgress": [],
                "showMetadata": {}
              },
              "trackerState": {
                "accounts": [
                  {
                    "service": "anilist",
                    "username": "viewer",
                    "accessToken": "token",
                    "userId": "123",
                    "isConnected": true
                  }
                ],
                "syncEnabled": true
              },
              "catalogs": [
                {
                  "id": "trending",
                  "name": "Trending This Week",
                  "source": "TMDB",
                  "isEnabled": true,
                  "order": 2,
                  "displayStyle": "standard"
                }
              ],
              "services": [
                {
                  "id": "3C357FD9-AE8B-42D3-A201-1734B56D2804",
                  "url": "https://example.test/service.json",
                  "jsonMetadata": "{\"name\":\"Example\"}",
                  "jsScript": "async function searchResults() { return [] }",
                  "isActive": true,
                  "sortIndex": 4
                }
              ],
              "stremioAddons": [
                {
                  "id": "org.example",
                  "configuredURL": "https://addon.example",
                  "manifestJSON": "{\"id\":\"org.example\",\"name\":\"Example\"}",
                  "isActive": true,
                  "sortIndex": 1
                }
              ],
              "mangaReadingProgress": {
                "123": {
                  "readChapterNumbers": ["1", "2"],
                  "lastReadChapter": "2",
                  "pagePositions": {
                    "2": 5
                  },
                  "title": "Manga"
                }
              },
              "recommendationCache": [
                {
                  "id": 99,
                  "title": "Recommended"
                }
              ],
              "userRatings": {
                "99": 5
              },
              "futureIosOnlySection": {
                "still": "preserved"
              }
            }
        """.trimIndent()

        val document = BackupDocument.decode(json, raw)
        val encoded = document.encode(json)

        assertEquals("1.0", document.payload.version)
        assertEquals(InAppPlayer.VLC, document.payload.resolvedInAppPlayer)
        assertEquals(90, document.payload.nextEpisodeThresholdPercent())
        assertEquals(true, document.payload.enableSubtitlesByDefault)
        assertEquals("org.videolan.vlc", document.payload.externalPlayer)
        assertEquals(true, document.payload.alwaysLandscape)
        assertEquals(false, document.payload.vlcHeaderProxyEnabled)
        assertEquals(true, document.payload.skip85sEnabled)
        assertEquals("#FFFFFF", document.payload.subtitleForegroundColor)
        assertEquals("#111111", document.payload.subtitleStrokeColor)
        assertEquals(2.5, document.payload.subtitleStrokeWidth)
        assertEquals(34.0, document.payload.subtitleFontSize)
        assertEquals(-8.0, document.payload.subtitleVerticalOffset)
        assertEquals("Georgia", document.payload.readerFontFamily)
        assertEquals(1, document.payload.collections.single().items.size)
        assertTrue(document.payload.progressData.jsonObject.containsKey("movieProgress"))
        assertEquals("viewer", document.payload.trackerState.accounts.single().username)
        assertEquals("Trending This Week", document.payload.catalogs.single().displayName)
        assertEquals("https://example.test/service.json", document.payload.services.single().resolvedScriptUrl)
        val stremioAddons = assertNotNull(document.payload.stremioAddons)
        assertEquals("https://addon.example", stremioAddons.single().resolvedTransportUrl)
        assertEquals("2", document.payload.mangaReadingProgress.getValue("123").lastReadChapter)
        assertEquals(5, document.payload.userRatings.getValue("99"))
        assertTrue("futureIosOnlySection" in document.unknownKeys)
        assertTrue(encoded.contains("futureIosOnlySection"))
        assertTrue(encoded.contains("manifestJSON"))
    }
}


