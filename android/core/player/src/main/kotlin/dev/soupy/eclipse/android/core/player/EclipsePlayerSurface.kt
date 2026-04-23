package dev.soupy.eclipse.android.core.player

import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.aspectRatio
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.material3.MaterialTheme
import androidx.compose.material3.Text
import androidx.compose.runtime.Composable
import androidx.compose.runtime.DisposableEffect
import androidx.compose.runtime.remember
import androidx.compose.ui.Modifier
import androidx.compose.ui.platform.LocalContext
import androidx.compose.ui.viewinterop.AndroidView
import androidx.compose.ui.unit.dp
import androidx.media3.common.MediaItem
import androidx.media3.datasource.DefaultDataSource
import androidx.media3.datasource.DefaultHttpDataSource
import androidx.media3.exoplayer.ExoPlayer
import androidx.media3.exoplayer.source.DefaultMediaSourceFactory
import androidx.media3.ui.PlayerView
import dev.soupy.eclipse.android.core.design.GlassPanel
import dev.soupy.eclipse.android.core.model.InAppPlayer
import dev.soupy.eclipse.android.core.model.PlayerSource

@Composable
fun EclipsePlayerSurface(
    modifier: Modifier = Modifier,
    source: PlayerSource? = null,
) {
    if (source == null) {
        GlassPanel(
            modifier = modifier
                .fillMaxWidth()
                .aspectRatio(16 / 9f),
        ) {
            Column(verticalArrangement = Arrangement.spacedBy(10.dp)) {
                Text(
                    text = "Normal player foundation",
                    style = MaterialTheme.typography.titleLarge,
                    color = MaterialTheme.colorScheme.onSurface,
                )
                Text(
                    text = "Media3/ExoPlayer is wired here for Milestone 1. VLC, mpv, external-player handoff, AniSkip, and next-episode orchestration will hang off this boundary later.",
                    style = MaterialTheme.typography.bodyMedium,
                    color = MaterialTheme.colorScheme.onSurface.copy(alpha = 0.8f),
                )
            }
        }
        return
    }

    val context = LocalContext.current
    val exoPlayer = remember(source.uri, source.headers) {
        val httpFactory = DefaultHttpDataSource.Factory()
            .setDefaultRequestProperties(source.headers)
        val mediaSourceFactory = DefaultMediaSourceFactory(
            DefaultDataSource.Factory(context, httpFactory),
        )

        ExoPlayer.Builder(context)
            .setMediaSourceFactory(mediaSourceFactory)
            .build()
            .apply {
                setMediaItem(MediaItem.fromUri(source.uri))
                prepare()
                playWhenReady = false
            }
    }

    DisposableEffect(exoPlayer) {
        onDispose {
            exoPlayer.release()
        }
    }

    AndroidView(
        modifier = modifier
            .fillMaxWidth()
            .aspectRatio(16 / 9f),
        factory = { viewContext ->
            PlayerView(viewContext).apply {
                player = exoPlayer
                useController = true
            }
        },
        update = { playerView ->
            playerView.player = exoPlayer
        },
    )
}

enum class PlayerBackend {
    NORMAL,
    VLC,
    MPV,
    EXTERNAL,
}

data class PlaybackSessionState(
    val backend: PlayerBackend = PlayerBackend.NORMAL,
    val preferredInAppPlayer: InAppPlayer = InAppPlayer.NORMAL,
    val currentSource: PlayerSource? = null,
)

