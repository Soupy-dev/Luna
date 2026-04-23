package dev.soupy.eclipse.android.feature.settings

import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.PaddingValues
import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.fillMaxSize
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.layout.statusBarsPadding
import androidx.compose.foundation.lazy.LazyColumn
import androidx.compose.material3.Button
import androidx.compose.material3.MaterialTheme
import androidx.compose.material3.OutlinedButton
import androidx.compose.material3.Slider
import androidx.compose.material3.Switch
import androidx.compose.material3.Text
import androidx.compose.runtime.Composable
import androidx.compose.ui.Modifier
import androidx.compose.ui.unit.dp
import dev.soupy.eclipse.android.core.design.GlassPanel
import dev.soupy.eclipse.android.core.design.HeroBackdrop
import dev.soupy.eclipse.android.core.design.SectionHeading
import dev.soupy.eclipse.android.core.model.InAppPlayer

data class SettingsScreenState(
    val accentColor: String = "#6D8CFF",
    val tmdbLanguage: String = "en-US",
    val autoModeEnabled: Boolean = true,
    val showNextEpisodeButton: Boolean = true,
    val nextEpisodeThreshold: Int = 90,
    val inAppPlayer: InAppPlayer = InAppPlayer.NORMAL,
)

@Composable
fun SettingsRoute(
    state: SettingsScreenState,
    onAutoModeChanged: (Boolean) -> Unit,
    onShowNextEpisodeChanged: (Boolean) -> Unit,
    onNextEpisodeThresholdChanged: (Int) -> Unit,
    onPlayerSelected: (InAppPlayer) -> Unit,
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
                title = "Settings",
                subtitle = "Playback and discovery",
                imageUrl = null,
                supportingText = "Android settings are now backed by DataStore. The auto mode warning is explicit here too: it may not always be accurate.",
            )
        }

        item {
            SectionHeading(
                title = "Discovery",
                subtitle = "Service behavior and catalog matching.",
            )
        }

        item {
            SettingToggleCard(
                title = "Auto Mode",
                description = "Let Eclipse choose the best provider order automatically. This may not always be accurate.",
                checked = state.autoModeEnabled,
                onCheckedChange = onAutoModeChanged,
            )
        }

        item {
            GlassPanel {
                Column(verticalArrangement = Arrangement.spacedBy(10.dp)) {
                    Text(
                        text = "Metadata Language",
                        style = MaterialTheme.typography.titleLarge,
                        color = MaterialTheme.colorScheme.onSurface,
                    )
                    Text(
                        text = state.tmdbLanguage,
                        style = MaterialTheme.typography.bodyLarge,
                        color = MaterialTheme.colorScheme.tertiary,
                    )
                    Text(
                        text = "This is already flowing from persisted settings, even before the full Android service stack lands.",
                        style = MaterialTheme.typography.bodyMedium,
                        color = MaterialTheme.colorScheme.onSurface.copy(alpha = 0.74f),
                    )
                }
            }
        }

        item {
            SectionHeading(
                title = "Playback",
                subtitle = "Player defaults and next-episode behavior.",
            )
        }

        item {
            GlassPanel {
                Column(verticalArrangement = Arrangement.spacedBy(14.dp)) {
                    Text(
                        text = "Preferred Player",
                        style = MaterialTheme.typography.titleLarge,
                        color = MaterialTheme.colorScheme.onSurface,
                    )
                    PlayerButtons(
                        selected = state.inAppPlayer,
                        onSelected = onPlayerSelected,
                    )
                }
            }
        }

        item {
            SettingToggleCard(
                title = "Next Episode Button",
                description = "Keep the next-episode CTA visible near the end of playback when we have enough context to offer it.",
                checked = state.showNextEpisodeButton,
                onCheckedChange = onShowNextEpisodeChanged,
            )
        }

        item {
            GlassPanel {
                Column(verticalArrangement = Arrangement.spacedBy(12.dp)) {
                    Text(
                        text = "Next Episode Threshold",
                        style = MaterialTheme.typography.titleLarge,
                        color = MaterialTheme.colorScheme.onSurface,
                    )
                    Text(
                        text = "${state.nextEpisodeThreshold}% watched",
                        style = MaterialTheme.typography.bodyLarge,
                        color = MaterialTheme.colorScheme.tertiary,
                    )
                    Slider(
                        value = state.nextEpisodeThreshold.toFloat(),
                        onValueChange = { onNextEpisodeThresholdChanged(it.toInt()) },
                        valueRange = 70f..98f,
                    )
                    Text(
                        text = "When playback reporting is connected, Android will use this same threshold to decide when to surface next-episode actions.",
                        style = MaterialTheme.typography.bodyMedium,
                        color = MaterialTheme.colorScheme.onSurface.copy(alpha = 0.74f),
                    )
                }
            }
        }

        item {
            GlassPanel {
                Column(verticalArrangement = Arrangement.spacedBy(10.dp)) {
                    Text(
                        text = "Appearance Snapshot",
                        style = MaterialTheme.typography.titleLarge,
                        color = MaterialTheme.colorScheme.onSurface,
                    )
                    Text(
                        text = "Accent ${state.accentColor}",
                        style = MaterialTheme.typography.bodyLarge,
                        color = MaterialTheme.colorScheme.tertiary,
                    )
                    Text(
                        text = "The Android design system is already reading the same class of persisted appearance values we'll need for closer Luna parity.",
                        style = MaterialTheme.typography.bodyMedium,
                        color = MaterialTheme.colorScheme.onSurface.copy(alpha = 0.74f),
                    )
                }
            }
        }
    }
}

@Composable
private fun SettingToggleCard(
    title: String,
    description: String,
    checked: Boolean,
    onCheckedChange: (Boolean) -> Unit,
) {
    GlassPanel {
        Row(
            modifier = Modifier.fillMaxWidth(),
            horizontalArrangement = Arrangement.spacedBy(16.dp),
        ) {
            Column(
                modifier = Modifier.weight(1f),
                verticalArrangement = Arrangement.spacedBy(8.dp),
            ) {
                Text(
                    text = title,
                    style = MaterialTheme.typography.titleLarge,
                    color = MaterialTheme.colorScheme.onSurface,
                )
                Text(
                    text = description,
                    style = MaterialTheme.typography.bodyMedium,
                    color = MaterialTheme.colorScheme.onSurface.copy(alpha = 0.75f),
                )
            }
            Switch(
                checked = checked,
                onCheckedChange = onCheckedChange,
            )
        }
    }
}

@Composable
private fun PlayerButtons(
    selected: InAppPlayer,
    onSelected: (InAppPlayer) -> Unit,
) {
    Column(verticalArrangement = Arrangement.spacedBy(10.dp)) {
        PlayerButtonRow(
            left = InAppPlayer.NORMAL,
            right = InAppPlayer.VLC,
            selected = selected,
            onSelected = onSelected,
        )
        PlayerButtonRow(
            left = InAppPlayer.MPV,
            right = InAppPlayer.EXTERNAL,
            selected = selected,
            onSelected = onSelected,
        )
    }
}

@Composable
private fun PlayerButtonRow(
    left: InAppPlayer,
    right: InAppPlayer,
    selected: InAppPlayer,
    onSelected: (InAppPlayer) -> Unit,
) {
    Row(
        modifier = Modifier.fillMaxWidth(),
        horizontalArrangement = Arrangement.spacedBy(12.dp),
    ) {
        PlayerChoiceButton(
            player = left,
            selected = left == selected,
            onSelected = onSelected,
            modifier = Modifier.weight(1f),
        )
        PlayerChoiceButton(
            player = right,
            selected = right == selected,
            onSelected = onSelected,
            modifier = Modifier.weight(1f),
        )
    }
}

@Composable
private fun PlayerChoiceButton(
    player: InAppPlayer,
    selected: Boolean,
    onSelected: (InAppPlayer) -> Unit,
    modifier: Modifier = Modifier,
) {
    val label = when (player) {
        InAppPlayer.NORMAL -> "Normal"
        InAppPlayer.VLC -> "VLC"
        InAppPlayer.MPV -> "mpv"
        InAppPlayer.EXTERNAL -> "External"
    }

    if (selected) {
        Button(
            onClick = { onSelected(player) },
            modifier = modifier,
        ) {
            Text(label)
        }
    } else {
        OutlinedButton(
            onClick = { onSelected(player) },
            modifier = modifier,
        ) {
            Text(label)
        }
    }
}
