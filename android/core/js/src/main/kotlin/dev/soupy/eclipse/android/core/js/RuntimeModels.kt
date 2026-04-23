package dev.soupy.eclipse.android.core.js

import kotlinx.serialization.SerialName
import kotlinx.serialization.Serializable
import kotlinx.serialization.json.JsonElement
import kotlinx.serialization.json.JsonObject

@Serializable
data class ServiceManifest(
    val id: String,
    val name: String,
    val version: String,
    @SerialName("scriptUrl") val scriptUrl: String? = null,
    @SerialName("baseUrl") val baseUrl: String? = null,
    @SerialName("configSchema") val configSchema: JsonObject? = null,
)

@Serializable
data class ModuleManifest(
    val id: String,
    val name: String,
    val version: String,
    @SerialName("entrypoint") val entrypoint: String? = null,
    @SerialName("permissions") val permissions: List<String> = emptyList(),
)

@Serializable
data class ScriptExecutionRequest(
    val source: String,
    val entrypoint: String? = null,
    val context: JsonObject = JsonObject(emptyMap()),
)

@Serializable
data class ScriptExecutionResult(
    val value: JsonElement? = null,
    val logs: List<String> = emptyList(),
)

@Serializable
data class WebViewBridgeRequest(
    val url: String,
    val method: String = "GET",
    val headers: Map<String, String> = emptyMap(),
    val body: String? = null,
)

@Serializable
data class WebViewBridgeResponse(
    val statusCode: Int,
    val body: String,
    val headers: Map<String, String> = emptyMap(),
)


