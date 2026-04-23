package dev.soupy.eclipse.android.core.js

interface JsEngine {
    suspend fun execute(request: ScriptExecutionRequest): Result<ScriptExecutionResult>
}

interface WebViewSessionBroker {
    suspend fun fetch(request: WebViewBridgeRequest): Result<WebViewBridgeResponse>
}

class NoopJsEngine : JsEngine {
    override suspend fun execute(request: ScriptExecutionRequest): Result<ScriptExecutionResult> =
        Result.success(
            ScriptExecutionResult(
                logs = listOf(
                    "No JS runtime has been plugged in yet.",
                    "This boundary is ready for a sideload-first runtime such as QuickJS plus a dedicated WebView helper layer.",
                ),
            ),
        )
}

