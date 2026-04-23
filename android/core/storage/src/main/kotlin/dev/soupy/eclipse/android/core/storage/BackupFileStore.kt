package dev.soupy.eclipse.android.core.storage

import android.content.Context
import java.io.File
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.withContext
import kotlinx.serialization.json.Json
import dev.soupy.eclipse.android.core.model.BackupDocument

class BackupFileStore(
    context: Context,
    private val json: Json,
) {
    private val file = File(context.filesDir, "backup/eclipse-backup.json")

    suspend fun read(): BackupDocument? = withContext(Dispatchers.IO) {
        if (!file.exists()) {
            null
        } else {
            BackupDocument.decode(json, file.readText())
        }
    }

    suspend fun write(document: BackupDocument) = withContext(Dispatchers.IO) {
        file.parentFile?.mkdirs()
        file.writeText(document.encode(json))
    }
}

