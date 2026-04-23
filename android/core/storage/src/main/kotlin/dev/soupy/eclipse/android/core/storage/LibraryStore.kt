package dev.soupy.eclipse.android.core.storage

import android.content.Context
import kotlinx.serialization.json.Json
import dev.soupy.eclipse.android.core.model.LibrarySnapshot

class LibraryStore(
    context: Context,
    json: Json,
) {
    private val store = JsonFileStore(
        context = context,
        relativePath = "library/library.json",
        serializer = LibrarySnapshot.serializer(),
        json = json,
    )

    suspend fun read(): LibrarySnapshot = store.read() ?: LibrarySnapshot()

    suspend fun write(snapshot: LibrarySnapshot) {
        store.write(snapshot)
    }
}
