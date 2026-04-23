package dev.soupy.eclipse.android.feature.manga

import androidx.compose.runtime.Composable
import dev.soupy.eclipse.android.core.design.FeaturePlaceholderScreen

@Composable
fun MangaRoute() {
    FeaturePlaceholderScreen(
        title = "Reader-focused manga support.",
        eyebrow = "Manga",
        description = "Manga is carved out as its own feature module so it can grow into the Kanzen-backed reader, progress syncing, and module ecosystem without cluttering the video surface area.",
        highlights = listOf(
            "Collections, catalogs, and reader state are part of the Android backup shape from the start.",
            "This route is intentionally modular so Kanzen runtime support can slot in later.",
            "Tablet reading ergonomics are considered up front instead of bolted on near release.",
        ),
    )
}


