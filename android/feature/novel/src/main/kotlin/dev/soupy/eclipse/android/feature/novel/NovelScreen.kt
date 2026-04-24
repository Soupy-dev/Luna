package dev.soupy.eclipse.android.feature.novel

import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.PaddingValues
import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.aspectRatio
import androidx.compose.foundation.layout.fillMaxSize
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.statusBarsPadding
import androidx.compose.foundation.layout.width
import androidx.compose.foundation.lazy.LazyColumn
import androidx.compose.foundation.lazy.items
import androidx.compose.material3.Button
import androidx.compose.material3.MaterialTheme
import androidx.compose.material3.Text
import androidx.compose.runtime.Composable
import androidx.compose.ui.Modifier
import androidx.compose.ui.text.style.TextOverflow
import androidx.compose.ui.unit.dp
import dev.soupy.eclipse.android.core.design.GlassPanel
import dev.soupy.eclipse.android.core.design.HeroBackdrop
import dev.soupy.eclipse.android.core.design.PosterImage
import dev.soupy.eclipse.android.core.design.SectionHeading

data class NovelScreenState(
    val isLoading: Boolean = false,
    val errorMessage: String? = null,
    val novelCount: Int = 0,
    val readChapterCount: Int = 0,
    val importedFromBackup: Boolean = false,
    val recent: List<NovelProgressRow> = emptyList(),
    val modules: List<NovelModuleRow> = emptyList(),
)

data class NovelProgressRow(
    val id: String,
    val title: String,
    val subtitle: String,
    val coverUrl: String? = null,
)

data class NovelModuleRow(
    val id: String,
    val name: String,
    val subtitle: String,
    val isActive: Boolean,
)

@Composable
fun NovelRoute(
    state: NovelScreenState,
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
                title = "Novels",
                subtitle = "${state.novelCount} saved - ${state.readChapterCount} chapters read",
                imageUrl = state.recent.firstOrNull()?.coverUrl,
                supportingText = "Light novel progress, reader history, and novel-capable Kanzen modules now hydrate from Android storage and Luna backups.",
            )
        }

        if (state.importedFromBackup) {
            item {
                GlassPanel {
                    Text(
                        text = "Imported staged novel data from the local Luna backup.",
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
                StatPanel("Novels", state.novelCount.toString(), Modifier.weight(1f))
                StatPanel("Modules", state.modules.size.toString(), Modifier.weight(1f))
            }
        }

        if (state.recent.isNotEmpty()) {
            item {
                SectionHeading(
                    title = "Reading",
                    subtitle = "Recent novel progress restored on Android.",
                )
            }
            items(state.recent, key = { it.id }) { row ->
                NovelProgressCard(row)
            }
        }

        if (state.modules.isNotEmpty()) {
            item {
                SectionHeading(
                    title = "Novel Modules",
                    subtitle = "Installed Kanzen modules marked for novel reading.",
                )
            }
            items(state.modules, key = { it.id }) { row ->
                GlassPanel {
                    Column(verticalArrangement = Arrangement.spacedBy(8.dp)) {
                        Text(
                            text = row.name,
                            style = MaterialTheme.typography.titleLarge,
                            color = MaterialTheme.colorScheme.onSurface,
                            maxLines = 2,
                            overflow = TextOverflow.Ellipsis,
                        )
                        Text(
                            text = listOf(
                                row.subtitle,
                                if (row.isActive) "Active" else "Inactive",
                            ).filter(String::isNotBlank).joinToString(" - "),
                            style = MaterialTheme.typography.bodyMedium,
                            color = MaterialTheme.colorScheme.tertiary,
                        )
                    }
                }
            }
        }

        if (!state.isLoading && state.errorMessage == null && state.recent.isEmpty() && state.modules.isEmpty()) {
            item {
                GlassPanel {
                    Column(verticalArrangement = Arrangement.spacedBy(12.dp)) {
                        Text(
                            text = "No novel data yet",
                            style = MaterialTheme.typography.titleLarge,
                            color = MaterialTheme.colorScheme.onSurface,
                        )
                        Text(
                            text = "Import a Luna backup with novel progress or install novel-capable Kanzen modules as the Android reader runtime lands.",
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
private fun NovelProgressCard(row: NovelProgressRow) {
    GlassPanel {
        Row(
            modifier = Modifier.fillMaxWidth(),
            horizontalArrangement = Arrangement.spacedBy(14.dp),
        ) {
            PosterImage(
                imageUrl = row.coverUrl,
                contentDescription = row.title,
                modifier = Modifier
                    .width(92.dp)
                    .aspectRatio(2f / 3f),
            )
            Column(
                modifier = Modifier.weight(1f),
                verticalArrangement = Arrangement.spacedBy(8.dp),
            ) {
                Text(
                    text = row.title,
                    style = MaterialTheme.typography.titleLarge,
                    color = MaterialTheme.colorScheme.onSurface,
                    maxLines = 2,
                    overflow = TextOverflow.Ellipsis,
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
