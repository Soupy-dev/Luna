package dev.soupy.eclipse.android.feature.downloads

import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.PaddingValues
import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.fillMaxSize
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.layout.statusBarsPadding
import androidx.compose.foundation.layout.width
import androidx.compose.foundation.layout.aspectRatio
import androidx.compose.foundation.layout.Spacer
import androidx.compose.foundation.lazy.LazyColumn
import androidx.compose.foundation.lazy.items
import androidx.compose.material3.Button
import androidx.compose.material3.LinearProgressIndicator
import androidx.compose.material3.MaterialTheme
import androidx.compose.material3.OutlinedButton
import androidx.compose.material3.Text
import androidx.compose.runtime.Composable
import androidx.compose.ui.Modifier
import androidx.compose.ui.text.style.TextOverflow
import androidx.compose.ui.unit.dp
import dev.soupy.eclipse.android.core.design.ErrorPanel
import dev.soupy.eclipse.android.core.design.GlassPanel
import dev.soupy.eclipse.android.core.design.HeroBackdrop
import dev.soupy.eclipse.android.core.design.LoadingPanel
import dev.soupy.eclipse.android.core.design.PosterImage
import dev.soupy.eclipse.android.core.design.SectionHeading
import dev.soupy.eclipse.android.core.model.DetailTarget

data class DownloadMetric(
    val label: String,
    val value: String,
    val supportingText: String,
)

data class DownloadRow(
    val id: String,
    val title: String,
    val subtitle: String? = null,
    val imageUrl: String? = null,
    val backdropUrl: String? = null,
    val mediaLabel: String? = null,
    val statusLabel: String,
    val progressPercent: Float = 0f,
    val progressLabel: String? = null,
    val sourceLabel: String? = null,
    val hasDirectSource: Boolean = false,
    val subtitleCount: Int = 0,
    val detailTarget: DetailTarget,
    val canPause: Boolean = false,
    val canResume: Boolean = false,
    val canMarkComplete: Boolean = false,
)

data class DownloadsScreenState(
    val isLoading: Boolean = true,
    val errorMessage: String? = null,
    val noticeMessage: String? = null,
    val heroTitle: String = "Downloads",
    val heroSubtitle: String? = "Offline queue",
    val heroImageUrl: String? = null,
    val heroSupportingText: String? = null,
    val metrics: List<DownloadMetric> = emptyList(),
    val items: List<DownloadRow> = emptyList(),
)

@Composable
fun DownloadsRoute(
    state: DownloadsScreenState,
    onRefresh: () -> Unit,
    onSelect: (DetailTarget) -> Unit,
    onPause: (String) -> Unit,
    onResume: (String) -> Unit,
    onMarkComplete: (String) -> Unit,
    onRemove: (String) -> Unit,
    onClearCompleted: () -> Unit,
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
                title = state.heroTitle,
                subtitle = state.heroSubtitle,
                imageUrl = state.heroImageUrl,
                supportingText = state.heroSupportingText,
            )
        }

        if (state.isLoading) {
            item {
                LoadingPanel(
                    title = "Loading downloads",
                    message = "Reading the Android offline queue, direct downloads, and packaged HLS entries.",
                )
            }
        }

        state.errorMessage?.let { error ->
            item {
                ErrorPanel(
                    title = "Downloads couldn't load",
                    message = error,
                    actionLabel = "Retry",
                    onAction = onRefresh,
                )
            }
        }

        state.noticeMessage?.let { notice ->
            item {
                GlassPanel {
                    Text(
                        text = notice,
                        style = MaterialTheme.typography.bodyLarge,
                        color = MaterialTheme.colorScheme.onSurface,
                    )
                }
            }
        }

        if (state.metrics.isNotEmpty()) {
            item {
                DownloadMetrics(metrics = state.metrics)
            }
        }

        if (state.items.isNotEmpty()) {
            item {
                Row(
                    modifier = Modifier.fillMaxWidth(),
                    horizontalArrangement = Arrangement.SpaceBetween,
                ) {
                    SectionHeading(
                        title = "Queue",
                        subtitle = "Direct streams can download into app storage; unsupported sources stay visible for retry.",
                    )
                    OutlinedButton(onClick = onClearCompleted) {
                        Text("Clear Completed")
                    }
                }
            }
            items(state.items, key = { it.id }) { item ->
                DownloadCard(
                    item = item,
                    onOpen = { onSelect(item.detailTarget) },
                    onPause = { onPause(item.id) },
                    onResume = { onResume(item.id) },
                    onMarkComplete = { onMarkComplete(item.id) },
                    onRemove = { onRemove(item.id) },
                )
            }
        }

        if (!state.isLoading && state.errorMessage == null && state.items.isEmpty()) {
            item {
                GlassPanel {
                    Column(verticalArrangement = Arrangement.spacedBy(12.dp)) {
                        Text(
                            text = "No downloads queued",
                            style = MaterialTheme.typography.titleLarge,
                            color = MaterialTheme.colorScheme.onSurface,
                        )
                        Text(
                            text = "Open a detail page, resolve a direct source, and queue it for offline storage.",
                            style = MaterialTheme.typography.bodyLarge,
                            color = MaterialTheme.colorScheme.onSurface.copy(alpha = 0.78f),
                        )
                    }
                }
            }
        }
    }
}

@Composable
private fun DownloadMetrics(
    metrics: List<DownloadMetric>,
) {
    Column(verticalArrangement = Arrangement.spacedBy(12.dp)) {
        metrics.chunked(2).forEach { rowMetrics ->
            Row(
                modifier = Modifier.fillMaxWidth(),
                horizontalArrangement = Arrangement.spacedBy(12.dp),
            ) {
                rowMetrics.forEach { metric ->
                    GlassPanel(modifier = Modifier.weight(1f)) {
                        Column(verticalArrangement = Arrangement.spacedBy(8.dp)) {
                            Text(
                                text = metric.label.uppercase(),
                                style = MaterialTheme.typography.labelLarge,
                                color = MaterialTheme.colorScheme.tertiary,
                            )
                            Text(
                                text = metric.value,
                                style = MaterialTheme.typography.headlineMedium,
                                color = MaterialTheme.colorScheme.onSurface,
                            )
                            Text(
                                text = metric.supportingText,
                                style = MaterialTheme.typography.bodyMedium,
                                color = MaterialTheme.colorScheme.onSurface.copy(alpha = 0.72f),
                            )
                        }
                    }
                }
                if (rowMetrics.size == 1) {
                    Spacer(modifier = Modifier.weight(1f))
                }
            }
        }
    }
}

@Composable
private fun DownloadCard(
    item: DownloadRow,
    onOpen: () -> Unit,
    onPause: () -> Unit,
    onResume: () -> Unit,
    onMarkComplete: () -> Unit,
    onRemove: () -> Unit,
) {
    GlassPanel {
        Column(verticalArrangement = Arrangement.spacedBy(14.dp)) {
            Row(horizontalArrangement = Arrangement.spacedBy(14.dp)) {
                PosterImage(
                    imageUrl = item.imageUrl ?: item.backdropUrl,
                    contentDescription = item.title,
                    modifier = Modifier
                        .width(94.dp)
                        .aspectRatio(0.72f),
                )
                Column(
                    modifier = Modifier.weight(1f),
                    verticalArrangement = Arrangement.spacedBy(8.dp),
                ) {
                    item.mediaLabel?.let {
                        Text(
                            text = it.uppercase(),
                            style = MaterialTheme.typography.labelLarge,
                            color = MaterialTheme.colorScheme.tertiary,
                        )
                    }
                    Text(
                        text = item.title,
                        style = MaterialTheme.typography.titleLarge,
                        color = MaterialTheme.colorScheme.onSurface,
                        maxLines = 2,
                        overflow = TextOverflow.Ellipsis,
                    )
                    item.subtitle?.let {
                        Text(
                            text = it,
                            style = MaterialTheme.typography.bodyMedium,
                            color = MaterialTheme.colorScheme.onSurface.copy(alpha = 0.78f),
                            maxLines = 2,
                            overflow = TextOverflow.Ellipsis,
                        )
                    }
                    Text(
                        text = item.statusLabel,
                        style = MaterialTheme.typography.bodyMedium,
                        color = MaterialTheme.colorScheme.tertiary,
                    )
                    item.sourceLabel?.let {
                        Text(
                            text = it,
                            style = MaterialTheme.typography.bodySmall,
                            color = MaterialTheme.colorScheme.onSurface.copy(alpha = 0.66f),
                            maxLines = 2,
                            overflow = TextOverflow.Ellipsis,
                        )
                    }
                }
            }

            LinearProgressIndicator(
                progress = { item.progressPercent.coerceIn(0f, 1f) },
                modifier = Modifier.fillMaxWidth(),
            )

            if (item.hasDirectSource) {
                Text(
                    text = buildString {
                        append("Direct stream captured")
                        if (item.subtitleCount > 0) append(" with ${item.subtitleCount} subtitle track${if (item.subtitleCount == 1) "" else "s"}")
                    },
                    style = MaterialTheme.typography.bodySmall,
                    color = MaterialTheme.colorScheme.tertiary,
                )
            }

            item.progressLabel?.let {
                Text(
                    text = it,
                    style = MaterialTheme.typography.bodyMedium,
                    color = MaterialTheme.colorScheme.onSurface.copy(alpha = 0.74f),
                )
            }

            Row(horizontalArrangement = Arrangement.spacedBy(12.dp)) {
                Button(onClick = onOpen) {
                    Text("Open")
                }
                if (item.canPause) {
                    OutlinedButton(onClick = onPause) {
                        Text("Pause")
                    }
                }
                if (item.canResume) {
                    OutlinedButton(onClick = onResume) {
                        Text("Resume")
                    }
                }
                if (item.canMarkComplete) {
                    OutlinedButton(onClick = onMarkComplete) {
                        Text("Complete")
                    }
                }
                OutlinedButton(onClick = onRemove) {
                    Text("Remove")
                }
            }
        }
    }
}
