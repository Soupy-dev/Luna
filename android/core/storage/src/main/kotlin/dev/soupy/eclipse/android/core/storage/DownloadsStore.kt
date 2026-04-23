package dev.soupy.eclipse.android.core.storage

import android.content.Context
import kotlinx.serialization.json.Json
import dev.soupy.eclipse.android.core.model.DownloadSnapshot

class DownloadsStore(
    context: Context,
    json: Json,
) {
    private val store = JsonFileStore(
        context = context,
        relativePath = "downloads/downloads.json",
        serializer = DownloadSnapshot.serializer(),
        json = json,
    )

    suspend fun read(): DownloadSnapshot = store.read() ?: DownloadSnapshot()

    suspend fun write(snapshot: DownloadSnapshot) {
        store.write(snapshot)
    }
}
