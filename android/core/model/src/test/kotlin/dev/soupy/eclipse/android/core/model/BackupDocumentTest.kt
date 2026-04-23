package dev.soupy.eclipse.android.core.model

import kotlin.test.Test
import kotlin.test.assertEquals
import kotlin.test.assertTrue
import kotlinx.serialization.json.Json

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
}


