package dev.soupy.eclipse.android.core.storage

import android.content.Context
import dev.soupy.eclipse.android.core.model.MangaLibrarySnapshot
import kotlinx.serialization.json.Json

class MangaStore(
    context: Context,
    json: Json,
) {
    private val store = JsonFileStore(
        context = context,
        relativePath = "manga/manga-library.json",
        serializer = MangaLibrarySnapshot.serializer(),
        json = json,
    )

    suspend fun read(): MangaLibrarySnapshot = store.read() ?: MangaLibrarySnapshot()

    suspend fun write(snapshot: MangaLibrarySnapshot) {
        store.write(snapshot)
    }
}
