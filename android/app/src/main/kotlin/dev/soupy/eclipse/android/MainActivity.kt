package dev.soupy.eclipse.android

import android.content.Intent
import android.os.Bundle
import androidx.activity.ComponentActivity
import androidx.activity.compose.setContent
import androidx.activity.enableEdgeToEdge
import androidx.compose.runtime.mutableStateOf

class MainActivity : ComponentActivity() {
    private val trackerCallbackUri = mutableStateOf<String?>(null)

    override fun onCreate(savedInstanceState: Bundle?) {
        super.onCreate(savedInstanceState)
        trackerCallbackUri.value = intent?.dataString
        enableEdgeToEdge()
        setContent {
            EclipseAndroidApp(
                trackerCallbackUri = trackerCallbackUri.value,
                onTrackerCallbackConsumed = {
                    trackerCallbackUri.value = null
                },
            )
        }
    }

    override fun onNewIntent(intent: Intent) {
        super.onNewIntent(intent)
        setIntent(intent)
        trackerCallbackUri.value = intent.dataString
    }
}


