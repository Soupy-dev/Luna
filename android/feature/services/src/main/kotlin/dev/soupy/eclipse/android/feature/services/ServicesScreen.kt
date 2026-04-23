package dev.soupy.eclipse.android.feature.services

import androidx.compose.runtime.Composable
import dev.soupy.eclipse.android.core.design.FeaturePlaceholderScreen

@Composable
fun ServicesRoute() {
    FeaturePlaceholderScreen(
        title = "Runtime-loaded services and Stremio addons.",
        eyebrow = "Services",
        description = "This route is the Android home for service ordering, addon configuration, auto mode, and the JS-backed provider ecosystem that makes Luna flexible.",
        highlights = listOf(
            "Auto mode will carry the same warning that it may not always be accurate.",
            "Service ordering, enablement, and configuration are already represented in the Android storage and model layers.",
            "Stremio manual URLs, manifests, and configured addons are planned as first-class sideload features, not afterthoughts.",
        ),
    )
}


