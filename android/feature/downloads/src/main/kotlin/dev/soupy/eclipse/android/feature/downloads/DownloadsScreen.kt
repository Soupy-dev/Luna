package dev.soupy.eclipse.android.feature.downloads

import androidx.compose.runtime.Composable
import dev.soupy.eclipse.android.core.design.FeaturePlaceholderScreen

@Composable
fun DownloadsRoute() {
    FeaturePlaceholderScreen(
        title = "Offline-first playback foundations.",
        eyebrow = "Downloads",
        description = "Downloads are being treated as a core Android capability, with room for direct files, custom HLS handling, subtitle fetching, and the next-episode behavior you care about for offline media.",
        highlights = listOf(
            "File-backed metadata stores are ready for parity-sensitive download manifests.",
            "Downloaded playback will remain operationally separate from streaming resolution, even if the UI feels unified.",
            "Resume, cancel, pause, and offline metadata hydration are planned here before alternate player backends land.",
        ),
    )
}


