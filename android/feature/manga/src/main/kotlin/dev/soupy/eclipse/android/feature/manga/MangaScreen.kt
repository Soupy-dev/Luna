package dev.soupy.eclipse.android.feature.manga

import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.PaddingValues
import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.aspectRatio
import androidx.compose.foundation.layout.fillMaxSize
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.statusBarsPadding
import androidx.compose.foundation.lazy.LazyColumn
import androidx.compose.foundation.lazy.items
import androidx.compose.material3.Button
import androidx.compose.material3.MaterialTheme
import androidx.compose.material3.Text
import androidx.compose.runtime.Composable
import androidx.compose.ui.Modifier
import androidx.compose.ui.unit.dp
import dev.soupy.eclipse.android.core.design.GlassPanel
import dev.soupy.eclipse.android.core.design.HeroBackdrop
import dev.soupy.eclipse.android.core.design.PosterImage
import dev.soupy.eclipse.android.core.design.SectionHeading

data class MangaScreenState(
    val isLoading: Boolean = false,
    val errorMessage: String? = null,
    val savedCount: Int = 0,
    val readChapterCount: Int = 0,
    val novelCount: Int = 0,
    val importedFromBackup: Boolean = false,
    val collections: List<MangaCollectionRow> = emptyList(),
    val recent: List<MangaProgressRow> = emptyList(),
    val modules: List<MangaModuleRow> = emptyList(),
)

data class MangaCollectionRow(
    val id: String,
    val name: String,
    val subtitle: String,
)

data class MangaProgressRow(
    val id: String,
    val title: String,
    val subtitle: String,
    val coverUrl: String? = null,
)

data class MangaModuleRow(
    val id: String,
    val name: String,
    val subtitle: String,
    val isActive: Boolean,
)

@Composable
fun MangaRoute(
    state: MangaScreenState,
    onRefresh: () -> Unit,
) {
    LazyColumn(
        modifier = Modifier
            .fillMaxSize()
            .statusBarsPadding(),
        verticalArrangement = Arrangement.spacedBy(18.dp),
        contentPadding = PaddingValues(horizontal = 20.dp, vertical = 18.dp),
    ) {
        item {
            HeroBackdrop(
                title = "Manga",
                subtitle = "${state.savedCount} saved - ${state.readChapterCount} chapters read",
                imageUrl = state.recent.firstOrNull()?.coverUrl,
                supportingText = if (state.novelCount > 0) {
                    "${state.novelCount} novel progress ${if (state.novelCount == 1) "entry" else "entries"} restored with manga history."
                } else {
                    "Kanzen library, progress, module, and catalog data now load from Android storage and Luna backups."
                },
            )
        }

        if (state.importedFromBackup) {
            item {
                GlassPanel {
                    Text(
                        text = "Imported staged manga data from the local Luna backup.",
                        style = MaterialTheme.typography.bodyMedium,
                        color = MaterialTheme.colorScheme.tertiary,
                    )
                }
            }
        }

        state.errorMessage?.let { message ->
            item {
                GlassPanel {
                    Column(verticalArrangement = Arrangement.spacedBy(12.dp)) {
                        Text(
                            text = message,
                            style = MaterialTheme.typography.bodyLarge,
                            color = MaterialTheme.colorScheme.error,
                        )
                        Button(onClick = onRefresh) {
                            Text("Retry")
                        }
                    }
                }
            }
        }

        item {
            Row(
                modifier = Modifier.fillMaxWidth(),
                horizontalArrangement = Arrangement.spacedBy(12.dp),
            ) {
                StatPanel("Collections", state.collections.size.toString(), Modifier.weight(1f))
                StatPanel("Modules", state.modules.size.toString(), Modifier.weight(1f))
            }
        }

        if (state.recent.isNotEmpty()) {
            item {
                SectionHeading(
                    title = "Reading",
                    subtitle = "Recent manga and novel progress restored on Android.",
                )
            }
            items(state.recent, key = { it.id }) { row ->
                MangaProgressCard(row)
            }
        }

        if (state.collections.isNotEmpty()) {
            item {
                SectionHeading(
                    title = "Collections",
                    subtitle = "Kanzen library collections from Android storage.",
                )
            }
            items(state.collections, key = { it.id }) { row ->
                TextRowCard(title = row.name, subtitle = row.subtitle)
            }
        }

        if (state.modules.isNotEmpty()) {
            item {
                SectionHeading(
                    title = "Modules",
                    subtitle = "Installed Kanzen module records ready for the runtime.",
                )
            }
            items(state.modules, key = { it.id }) { row ->
                TextRowCard(
                    title = row.name,
                    subtitle = listOf(
                        row.subtitle,
                        if (row.isActive) "Active" else "Inactive",
                    ).filter(String::isNotBlank).joinToString(" - "),
                )
            }
        }

        if (!state.isLoading && state.errorMessage == null && state.collections.isEmpty() && state.recent.isEmpty() && state.modules.isEmpty()) {
            item {
                GlassPanel {
                    Column(verticalArrangement = Arrangement.spacedBy(12.dp)) {
                        Text(
                            text = "No manga library data yet",
                            style = MaterialTheme.typography.titleLarge,
                            color = MaterialTheme.colorScheme.onSurface,
                        )
                        Text(
                            text = "Import a Luna backup or add Kanzen modules as the Android reader runtime lands.",
                            style = MaterialTheme.typography.bodyMedium,
                            color = MaterialTheme.colorScheme.onSurface.copy(alpha = 0.74f),
                        )
                        Button(onClick = onRefresh) {
                            Text("Refresh")
                        }
                    }
                }
            }
        }
    }
}

@Composable
private fun StatPanel(
    title: String,
    value: String,
    modifier: Modifier = Modifier,
) {
    GlassPanel(modifier = modifier) {
        Column(verticalArrangement = Arrangement.spacedBy(8.dp)) {
            Text(
                text = value,
                style = MaterialTheme.typography.headlineMedium,
                color = MaterialTheme.colorScheme.onSurface,
            )
            Text(
                text = title,
                style = MaterialTheme.typography.bodyMedium,
                color = MaterialTheme.colorScheme.tertiary,
            )
        }
    }
}

@Composable
private fun MangaProgressCard(row: MangaProgressRow) {
    GlassPanel {
        Row(
            modifier = Modifier.fillMaxWidth(),
            horizontalArrangement = Arrangement.spacedBy(14.dp),
        ) {
            row.coverUrl?.let { cover ->
                PosterImage(
                    imageUrl = cover,
                    contentDescription = row.title,
                    modifier = Modifier
                        .weight(0.34f)
                        .aspectRatio(2f / 3f),
                )
            }
            Column(
                modifier = Modifier.weight(1f),
                verticalArrangement = Arrangement.spacedBy(8.dp),
            ) {
                Text(
                    text = row.title,
                    style = MaterialTheme.typography.titleLarge,
                    color = MaterialTheme.colorScheme.onSurface,
                )
                if (row.subtitle.isNotBlank()) {
                    Text(
                        text = row.subtitle,
                        style = MaterialTheme.typography.bodyMedium,
                        color = MaterialTheme.colorScheme.tertiary,
                    )
                }
            }
        }
    }
}

@Composable
private fun TextRowCard(
    title: String,
    subtitle: String,
) {
    GlassPanel {
        Column(verticalArrangement = Arrangement.spacedBy(8.dp)) {
            Text(
                text = title,
                style = MaterialTheme.typography.titleLarge,
                color = MaterialTheme.colorScheme.onSurface,
            )
            if (subtitle.isNotBlank()) {
                Text(
                    text = subtitle,
                    style = MaterialTheme.typography.bodyMedium,
                    color = MaterialTheme.colorScheme.tertiary,
                )
            }
        }
    }
}
