package dev.soupy.eclipse.android.core.network

sealed interface NetworkResult<out T> {
    data class Success<T>(val value: T) : NetworkResult<T>

    sealed interface Failure : NetworkResult<Nothing> {
        data class Http(val code: Int, val body: String?) : Failure
        data class Connectivity(val throwable: Throwable) : Failure
        data class Serialization(val throwable: Throwable) : Failure
    }
}


