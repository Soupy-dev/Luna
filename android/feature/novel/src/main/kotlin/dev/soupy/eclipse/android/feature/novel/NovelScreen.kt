package dev.soupy.eclipse.android.feature.novel

import androidx.compose.runtime.Composable
import dev.soupy.eclipse.android.core.design.FeaturePlaceholderScreen

@Composable
fun NovelRoute() {
    FeaturePlaceholderScreen(
        title = "Light novels with the same product language.",
        eyebrow = "Novel",
        description = "The Android novel surface is ready to evolve into a dedicated reading mode that still feels like Luna, instead of a generic embedded web view or a detached reader app.",
        highlights = listOf(
            "Reader settings and progress serialization are already accounted for in the Android backup layer.",
            "This module will share visual tokens with the rest of the app while keeping reader interactions purpose-built.",
            "It stays isolated enough that future Kanzen novel integrations won't force a redesign of the media app shell.",
        ),
    )
}

