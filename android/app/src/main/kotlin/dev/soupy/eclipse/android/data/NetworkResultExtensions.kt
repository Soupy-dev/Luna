package dev.soupy.eclipse.android.data

import dev.soupy.eclipse.android.core.network.NetworkResult

internal fun <T> NetworkResult<T>.orThrow(): T = when (this) {
    is NetworkResult.Success -> value
    is NetworkResult.Failure.Http -> error("HTTP ${code}${body?.let { ": $it" } ?: ""}")
    is NetworkResult.Failure.Connectivity -> throw throwable
    is NetworkResult.Failure.Serialization -> throw throwable
}

internal fun <T> NetworkResult<T>.orNull(): T? = when (this) {
    is NetworkResult.Success -> value
    is NetworkResult.Failure -> null
}

internal fun <T> NetworkResult<List<T>>.orEmptyList(): List<T> = when (this) {
    is NetworkResult.Success -> value
    is NetworkResult.Failure -> emptyList()
}

