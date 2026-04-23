package dev.soupy.eclipse.android.core.network

import dev.soupy.eclipse.android.core.model.StremioManifest
import dev.soupy.eclipse.android.core.model.StremioStreamResponse
import kotlinx.serialization.SerializationException
import kotlinx.serialization.decodeFromString

class StremioService(
    private val httpClient: EclipseHttpClient = EclipseHttpClient(),
) {
    suspend fun fetchManifest(transportUrl: String): NetworkResult<StremioManifest> = decode {
        httpClient.get(transportUrl.ensureManifestUrl())
    }

    suspend fun fetchStreams(
        transportUrl: String,
        type: String,
        id: String,
    ): NetworkResult<StremioStreamResponse> = decode {
        val base = transportUrl.removeSuffix("/manifest.json")
        httpClient.get("$base/stream/$type/$id.json")
    }

    private suspend inline fun <reified T> decode(request: () -> NetworkResult<String>): NetworkResult<T> =
        when (val result = request()) {
            is NetworkResult.Success -> try {
                NetworkResult.Success(EclipseJson.decodeFromString<T>(result.value))
            } catch (error: SerializationException) {
                NetworkResult.Failure.Serialization(error)
            }

            is NetworkResult.Failure -> result
        }
}

private fun String.ensureManifestUrl(): String =
    if (endsWith("/manifest.json")) this else removeSuffix("/") + "/manifest.json"

