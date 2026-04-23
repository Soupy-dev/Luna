package dev.soupy.eclipse.android.core.network

import kotlinx.serialization.json.Json

val EclipseJson: Json = Json {
    ignoreUnknownKeys = true
    explicitNulls = false
    coerceInputValues = true
    prettyPrint = false
}


