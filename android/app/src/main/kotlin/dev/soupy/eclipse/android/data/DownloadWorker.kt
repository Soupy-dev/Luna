package dev.soupy.eclipse.android.data

import android.content.Context
import androidx.work.CoroutineWorker
import androidx.work.WorkerParameters
import dev.soupy.eclipse.android.core.model.DownloadStatus
import dev.soupy.eclipse.android.core.network.EclipseJson
import dev.soupy.eclipse.android.core.storage.DownloadsStore

class DownloadWorker(
    appContext: Context,
    workerParameters: WorkerParameters,
) : CoroutineWorker(appContext, workerParameters) {
    override suspend fun doWork(): Result {
        val downloadId = inputData.getString(DownloadsRepository.DownloadWorkerIdKey)
            ?: return Result.failure()
        val store = DownloadsStore(
            context = applicationContext,
            json = EclipseJson,
        )
        val repository = DownloadsRepository(downloadsStore = store)

        return repository.processQueuedDownload(downloadId).fold(
            onSuccess = { snapshot ->
                val record = snapshot.items.firstOrNull { it.id == downloadId }
                when {
                    record == null -> Result.failure()
                    record.status == DownloadStatus.FAILED && runAttemptCount < 2 -> Result.retry()
                    else -> Result.success()
                }
            },
            onFailure = { Result.failure() },
        )
    }
}
