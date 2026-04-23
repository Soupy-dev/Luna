package dev.soupy.eclipse.android.core.storage

import android.content.Context
import java.io.File
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.withContext
import kotlinx.serialization.KSerializer
import kotlinx.serialization.decodeFromString
import kotlinx.serialization.encodeToString
import kotlinx.serialization.json.Json

class JsonFileStore<T>(
    context: Context,
    relativePath: String,
    private val serializer: KSerializer<T>,
    private val json: Json,
) {
    private val file = File(context.filesDir, relativePath)

    suspend fun read(): T? = withContext(Dispatchers.IO) {
        if (!file.exists()) {
            null
        } else {
            json.decodeFromString(serializer, file.readText())
        }
    }

    suspend fun write(value: T) = withContext(Dispatchers.IO) {
        file.parentFile?.mkdirs()
        file.writeText(json.encodeToString(serializer, value))
    }

    suspend fun delete() = withContext(Dispatchers.IO) {
        file.delete()
    }
}

