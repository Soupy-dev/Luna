package dev.soupy.eclipse.android.core.model

import kotlinx.serialization.SerialName
import kotlinx.serialization.Serializable
import kotlinx.serialization.json.JsonObject

@Serializable
data class StremioManifestBehaviorHints(
    val configurable: Boolean = false,
    @SerialName("configurationRequired") val configurationRequired: Boolean = false,
)

@Serializable
data class StremioResourceDescriptor(
    val name: String = "",
    val types: List<String> = emptyList(),
    @SerialName("idPrefixes") val idPrefixes: List<String> = emptyList(),
)

@Serializable
data class StremioManifest(
    val id: String = "",
    val version: String = "",
    val name: String = "",
    val description: String? = null,
    @SerialName("logo") val logoUrl: String? = null,
    val background: String? = null,
    val resources: List<StremioResourceDescriptor> = emptyList(),
    val types: List<String> = emptyList(),
    val catalogs: List<JsonObject> = emptyList(),
    @SerialName("behaviorHints") val behaviorHints: StremioManifestBehaviorHints = StremioManifestBehaviorHints(),
)

@Serializable
data class StremioProxyHeaders(
    val request: Map<String, String> = emptyMap(),
    val response: Map<String, String> = emptyMap(),
)

@Serializable
data class StremioSubtitle(
    val id: String? = null,
    val lang: String? = null,
    val label: String? = null,
    val url: String? = null,
)

@Serializable
data class StremioStreamBehaviorHints(
    @SerialName("bingeGroup") val bingeGroup: String? = null,
    @SerialName("filename") val filename: String? = null,
    @SerialName("notWebReady") val notWebReady: Boolean = false,
    @SerialName("proxyHeaders") val proxyHeaders: StremioProxyHeaders? = null,
)

@Serializable
data class StremioStream(
    val name: String? = null,
    val title: String? = null,
    val description: String? = null,
    val url: String? = null,
    @SerialName("ytId") val ytId: String? = null,
    val infoHash: String? = null,
    val fileIdx: Int? = null,
    val subtitles: List<StremioSubtitle> = emptyList(),
    @SerialName("behaviorHints") val behaviorHints: StremioStreamBehaviorHints? = null,
)

@Serializable
data class StremioStreamResponse(
    val streams: List<StremioStream> = emptyList(),
)

@Serializable
data class StremioAddon(
    val transportUrl: String,
    val manifest: StremioManifest,
    val enabled: Boolean = true,
    val sortIndex: Int = 0,
)


