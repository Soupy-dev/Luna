package dev.soupy.eclipse.android.core.network

import java.io.IOException
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.withContext
import okhttp3.MediaType.Companion.toMediaType
import okhttp3.OkHttpClient
import okhttp3.Request
import okhttp3.RequestBody.Companion.toRequestBody

class EclipseHttpClient(
    private val client: OkHttpClient = defaultClient(),
) {
    suspend fun get(
        url: String,
        headers: Map<String, String> = emptyMap(),
    ): NetworkResult<String> = execute(
        Request.Builder()
            .url(url)
            .applyHeaders(headers)
            .get()
            .build(),
    )

    suspend fun postJson(
        url: String,
        body: String,
        headers: Map<String, String> = emptyMap(),
    ): NetworkResult<String> = execute(
        Request.Builder()
            .url(url)
            .applyHeaders(headers)
            .post(body.toRequestBody("application/json".toMediaType()))
            .build(),
    )

    private suspend fun execute(request: Request): NetworkResult<String> = withContext(Dispatchers.IO) {
        try {
            client.newCall(request).execute().use { response ->
                val body = response.body.string()
                if (response.isSuccessful) {
                    NetworkResult.Success(body)
                } else {
                    NetworkResult.Failure.Http(response.code, body)
                }
            }
        } catch (error: IOException) {
            NetworkResult.Failure.Connectivity(error)
        }
    }

    companion object {
        fun defaultClient(): OkHttpClient = OkHttpClient.Builder()
            .addInterceptor { chain ->
                val request = chain.request().newBuilder()
                    .header("User-Agent", "EclipseAndroid/1.0.1")
                    .build()
                chain.proceed(request)
            }
            .build()
    }
}

private fun Request.Builder.applyHeaders(headers: Map<String, String>): Request.Builder = apply {
    headers.forEach { (key, value) -> header(key, value) }
}


