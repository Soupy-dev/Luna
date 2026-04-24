package dev.soupy.eclipse.android.data

import dev.soupy.eclipse.android.core.model.TrackerAccountSnapshot
import dev.soupy.eclipse.android.core.model.TrackerStateSnapshot
import dev.soupy.eclipse.android.core.storage.TrackerStore
import java.time.Instant

data class TrackerAccountDraft(
    val service: String,
    val username: String,
    val accessToken: String,
    val refreshToken: String? = null,
    val userId: String = "",
)

class TrackerRepository(
    private val trackerStore: TrackerStore,
) {
    suspend fun loadSnapshot(): Result<TrackerStateSnapshot> = runCatching {
        trackerStore.read()
    }

    suspend fun restoreFromBackup(snapshot: TrackerStateSnapshot): Result<TrackerStateSnapshot> = runCatching {
        trackerStore.write(snapshot)
        snapshot
    }

    suspend fun saveManualAccount(draft: TrackerAccountDraft): Result<TrackerStateSnapshot> = runCatching {
        val service = draft.service.trim().ifBlank { "Tracker" }
        val accessToken = draft.accessToken.trim()
        require(accessToken.isNotBlank()) { "Tracker token or PIN is required." }

        val current = trackerStore.read()
        val account = TrackerAccountSnapshot(
            service = service,
            username = draft.username.trim(),
            accessToken = accessToken,
            refreshToken = draft.refreshToken?.trim()?.takeIf(String::isNotBlank),
            userId = draft.userId.trim(),
            isConnected = true,
        )
        val accounts = listOf(account) + current.accounts.filterNot {
            it.service.equals(service, ignoreCase = true)
        }
        val updated = current.copy(
            accounts = accounts,
            syncEnabled = current.syncEnabled,
            lastSyncDate = current.lastSyncDate,
            provider = service,
            accessToken = accessToken,
            refreshToken = account.refreshToken,
            userName = account.username.takeIf(String::isNotBlank),
        )
        trackerStore.write(updated)
        updated
    }

    suspend fun setSyncEnabled(enabled: Boolean): Result<TrackerStateSnapshot> = runCatching {
        val updated = trackerStore.read().copy(syncEnabled = enabled)
        trackerStore.write(updated)
        updated
    }

    suspend fun markSyncAttempted(): Result<TrackerStateSnapshot> = runCatching {
        val updated = trackerStore.read().copy(lastSyncDate = Instant.now().toString())
        trackerStore.write(updated)
        updated
    }

    suspend fun disconnect(service: String): Result<TrackerStateSnapshot> = runCatching {
        val normalized = service.trim()
        require(normalized.isNotBlank()) { "Tracker service is required." }
        val current = trackerStore.read()
        val accounts = current.accounts.filterNot {
            it.service.equals(normalized, ignoreCase = true)
        }
        val primary = accounts.firstOrNull()
        val updated = current.copy(
            accounts = accounts,
            provider = primary?.service,
            accessToken = primary?.accessToken,
            refreshToken = primary?.refreshToken,
            userName = primary?.username,
        )
        trackerStore.write(updated)
        updated
    }

    suspend fun exportState(fallback: TrackerStateSnapshot): TrackerStateSnapshot {
        val state = trackerStore.read()
        return if (state.accounts.isNotEmpty() || state.accessToken != null || state.provider != null) {
            state
        } else {
            fallback
        }
    }
}
