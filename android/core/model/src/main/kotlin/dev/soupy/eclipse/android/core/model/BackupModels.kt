package dev.soupy.eclipse.android.core.model

import kotlinx.serialization.SerialName
import kotlinx.serialization.Serializable
import kotlinx.serialization.SerializationException
import kotlinx.serialization.encodeToString
import kotlinx.serialization.descriptors.SerialDescriptor
import kotlinx.serialization.json.Json
import kotlinx.serialization.json.JsonElement
import kotlinx.serialization.json.JsonObject
import kotlinx.serialization.json.decodeFromJsonElement
import kotlinx.serialization.json.encodeToJsonElement
import kotlinx.serialization.json.jsonObject

@Serializable
data class BackupCollection(
    val id: String,
    val name: String,
    val items: List<String> = emptyList(),
)

@Serializable
data class BackupProgressEntry(
    val key: String,
    val positionMs: Long = 0,
    val durationMs: Long = 0,
    val updatedAt: Long = 0,
    val context: EpisodePlaybackContext? = null,
)

@Serializable
data class BackupCatalog(
    val id: String,
    val title: String,
    val type: String,
    val manifestUrl: String? = null,
)

@Serializable
data class ServiceBackup(
    val id: String,
    val name: String,
    val manifestUrl: String? = null,
    val enabled: Boolean = true,
    val sortIndex: Int = 0,
)

@Serializable
data class ModuleBackup(
    val id: String,
    val name: String,
    val manifestUrl: String? = null,
    val enabled: Boolean = true,
)

@Serializable
data class TrackerStateSnapshot(
    val provider: String? = null,
    val accessToken: String? = null,
    val refreshToken: String? = null,
    val userName: String? = null,
)

@Serializable
data class BackupData(
    val version: Int = 1,
    val createdDate: String? = null,
    val accentColor: String? = null,
    val tmdbLanguage: String? = null,
    val selectedAppearance: String? = null,
    val inAppPlayer: InAppPlayer = InAppPlayer.NORMAL,
    val holdSpeedPlayer: Boolean = true,
    val externalPlayer: String? = null,
    val alwaysLandscape: Boolean = false,
    val aniSkipAutoSkip: Boolean = false,
    val skip85sEnabled: Boolean = false,
    val showNextEpisodeButton: Boolean = true,
    val nextEpisodeThreshold: Int = 90,
    val vlcHeaderProxyEnabled: Boolean = false,
    val collections: List<BackupCollection> = emptyList(),
    val progressData: List<BackupProgressEntry> = emptyList(),
    val trackerState: TrackerStateSnapshot? = null,
    val catalogs: List<BackupCatalog> = emptyList(),
    val services: List<ServiceBackup> = emptyList(),
    val stremioAddons: List<ServiceBackup> = emptyList(),
    val mangaCollections: List<BackupCollection> = emptyList(),
    val mangaProgressData: List<BackupProgressEntry> = emptyList(),
    val mangaCatalogs: List<BackupCatalog> = emptyList(),
    val kanzenModules: List<ModuleBackup> = emptyList(),
    val recommendationCache: Map<String, JsonElement> = emptyMap(),
    @SerialName("userRatings") val userRatings: Map<String, Double> = emptyMap(),
)

data class BackupDocument(
    val payload: BackupData,
    val unknownKeys: Map<String, JsonElement> = emptyMap(),
) {
    fun encode(json: Json): String = json.encodeToString(JsonObject.serializer(), toJsonObject(json))

    fun toJsonObject(json: Json): JsonObject {
        val known = json.encodeToJsonElement(payload).jsonObject
        return JsonObject(known + unknownKeys)
    }

    companion object {
        fun decode(json: Json, raw: String): BackupDocument {
            val root = try {
                json.parseToJsonElement(raw).jsonObject
            } catch (error: IllegalStateException) {
                throw SerializationException("Backup root is not a JSON object", error)
            }
            val payload = json.decodeFromJsonElement<BackupData>(root)
            val knownKeys = BackupData.serializer().descriptor.elementNames()
            val unknownKeys = root.filterKeys { it !in knownKeys }
            return BackupDocument(payload = payload, unknownKeys = unknownKeys)
        }
    }
}

private fun SerialDescriptor.elementNames(): Set<String> =
    (0 until elementsCount).map(::getElementName).toSet()

