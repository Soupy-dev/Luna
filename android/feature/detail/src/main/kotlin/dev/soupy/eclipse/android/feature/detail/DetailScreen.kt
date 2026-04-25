package dev.soupy.eclipse.android.feature.detail

import androidx.compose.foundation.background
import androidx.compose.foundation.border
import androidx.compose.foundation.clickable
import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Box
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.PaddingValues
import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.Spacer
import androidx.compose.foundation.layout.fillMaxSize
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.height
import androidx.compose.foundation.layout.heightIn
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.layout.size
import androidx.compose.foundation.layout.statusBarsPadding
import androidx.compose.foundation.layout.width
import androidx.compose.foundation.lazy.LazyColumn
import androidx.compose.foundation.lazy.LazyRow
import androidx.compose.foundation.lazy.items
import androidx.compose.foundation.shape.CircleShape
import androidx.compose.foundation.shape.RoundedCornerShape
import androidx.compose.material3.Button
import androidx.compose.material3.ButtonDefaults
import androidx.compose.material3.DropdownMenu
import androidx.compose.material3.DropdownMenuItem
import androidx.compose.material3.MaterialTheme
import androidx.compose.material3.OutlinedButton
import androidx.compose.material3.Text
import androidx.compose.material3.TextButton
import androidx.compose.runtime.Composable
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.remember
import androidx.compose.runtime.setValue
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.draw.clip
import androidx.compose.ui.graphics.Brush
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.text.font.FontWeight
import androidx.compose.ui.text.style.TextAlign
import androidx.compose.ui.text.style.TextOverflow
import androidx.compose.ui.unit.dp
import dev.soupy.eclipse.android.core.design.ErrorPanel
import dev.soupy.eclipse.android.core.design.GlassPanel
import dev.soupy.eclipse.android.core.design.LoadingPanel
import dev.soupy.eclipse.android.core.design.MediaPosterCard
import dev.soupy.eclipse.android.core.design.PosterImage
import dev.soupy.eclipse.android.core.design.SectionHeading
import dev.soupy.eclipse.android.core.model.ExploreMediaCard
import dev.soupy.eclipse.android.core.model.InAppPlayer
import dev.soupy.eclipse.android.core.model.PlaybackSettingsSnapshot
import dev.soupy.eclipse.android.core.model.PlayerSource
import dev.soupy.eclipse.android.core.model.SkipSegment
import dev.soupy.eclipse.android.core.player.EclipsePlayerSurface
import dev.soupy.eclipse.android.core.player.PlaybackProgressSnapshot

data class DetailEpisodeRow(
    val id: String,
    val title: String,
    val subtitle: String? = null,
    val imageUrl: String? = null,
    val overview: String? = null,
    val seasonNumber: Int? = null,
    val episodeNumber: Int? = null,
    val runtimeMinutes: Int? = null,
    val tmdbSeasonNumber: Int? = null,
    val tmdbEpisodeNumber: Int? = null,
)

data class DetailCastRow(
    val id: String,
    val name: String,
    val role: String? = null,
    val imageUrl: String? = null,
)

data class DetailFactRow(
    val label: String,
    val value: String,
)

data class DetailStreamRow(
    val id: String,
    val title: String,
    val subtitle: String? = null,
    val supportingText: String? = null,
    val playable: Boolean = false,
    val playerSource: PlayerSource? = null,
)

data class DetailCollectionRow(
    val id: String,
    val name: String,
    val isSelected: Boolean = false,
)

data class DetailScreenState(
    val hasSelection: Boolean = false,
    val isLoading: Boolean = false,
    val errorMessage: String? = null,
    val title: String = "",
    val subtitle: String? = null,
    val overview: String? = null,
    val posterUrl: String? = null,
    val backdropUrl: String? = null,
    val metadataChips: List<String> = emptyList(),
    val detailFacts: List<DetailFactRow> = emptyList(),
    val contentRating: String? = null,
    val userRating: Int? = null,
    val cast: List<DetailCastRow> = emptyList(),
    val recommendations: List<ExploreMediaCard> = emptyList(),
    val episodesTitle: String? = null,
    val episodes: List<DetailEpisodeRow> = emptyList(),
    val isResolvingStreams: Boolean = false,
    val streamStatusMessage: String? = null,
    val streamCandidates: List<DetailStreamRow> = emptyList(),
    val playerSource: PlayerSource? = null,
    val skipSegments: List<SkipSegment> = emptyList(),
    val skipStatusMessage: String? = null,
    val selectedEpisodeId: String? = null,
    val selectedEpisodeLabel: String? = null,
    val seasonMenu: Boolean = false,
    val horizontalEpisodeList: Boolean = false,
    val collections: List<DetailCollectionRow> = emptyList(),
)

@Composable
fun DetailRoute(
    state: DetailScreenState,
    onRetry: () -> Unit,
    onSaveToLibrary: () -> Unit,
    onAddToCollection: (String) -> Unit,
    onQueueResume: () -> Unit,
    onQueueDownload: () -> Unit,
    onSetRating: (Int) -> Unit,
    onClearRating: () -> Unit,
    onMarkWatched: () -> Unit,
    onMarkUnwatched: () -> Unit,
    onResolveStreams: () -> Unit,
    onResolveEpisodeStreams: (String) -> Unit,
    onMarkEpisodeWatched: (String) -> Unit,
    onMarkEpisodeUnwatched: (String) -> Unit,
    onMarkPreviousEpisodesWatched: (String) -> Unit,
    onPlayStream: (String) -> Unit,
    onPlayNextEpisode: () -> Unit,
    onSelectRecommendation: (ExploreMediaCard) -> Unit,
    onPlaybackProgress: (PlaybackProgressSnapshot) -> Unit,
    preferredPlayer: InAppPlayer = InAppPlayer.NORMAL,
    playbackSettings: PlaybackSettingsSnapshot = PlaybackSettingsSnapshot(),
) {
    val episodeSeasons = state.episodes
        .mapNotNull { it.seasonNumber ?: it.tmdbSeasonNumber }
        .distinct()
        .sorted()
    var selectedSeason by remember(state.title, episodeSeasons) {
        mutableStateOf(episodeSeasons.firstOrNull())
    }
    val isSeasonedShow = episodeSeasons.size > 1
    val visibleEpisodes = if (isSeasonedShow && selectedSeason != null) {
        state.episodes.filter { episode ->
            (episode.seasonNumber ?: episode.tmdbSeasonNumber) == selectedSeason
        }
    } else {
        state.episodes
    }

    if (!state.hasSelection && !state.isLoading) {
        ErrorPanel(
            title = "Open something first",
            message = "Pick a movie, show, or anime card to view details.",
            modifier = Modifier
                .fillMaxSize()
                .statusBarsPadding()
                .padding(horizontal = 20.dp, vertical = 18.dp),
        )
        return
    }

    LazyColumn(
        modifier = Modifier.fillMaxSize(),
        verticalArrangement = Arrangement.spacedBy(16.dp),
        contentPadding = PaddingValues(bottom = 28.dp),
    ) {
        if (state.isLoading) {
            item {
                LoadingPanel(
                    title = "Loading",
                    message = "Fetching details.",
                    modifier = Modifier
                        .statusBarsPadding()
                        .padding(horizontal = 20.dp, vertical = 18.dp),
                )
            }
        }

        state.errorMessage?.let { error ->
            item {
                ErrorPanel(
                    title = "Detail couldn't finish loading",
                    message = error,
                    actionLabel = "Retry",
                    onAction = onRetry,
                    modifier = Modifier
                        .statusBarsPadding()
                        .padding(horizontal = 20.dp, vertical = 18.dp),
                )
            }
        }

        if (state.title.isNotBlank()) {
            item {
                DetailHero(
                    title = state.title,
                    subtitle = state.subtitle,
                    imageUrl = state.backdropUrl ?: state.posterUrl,
                )
            }
        }

        if (!state.overview.isNullOrBlank()) {
            item {
                SynopsisBlock(
                    text = state.overview,
                    modifier = Modifier.padding(horizontal = 20.dp),
                )
            }
        }

        if (state.metadataChips.isNotEmpty()) {
            item {
                MetadataStrip(
                    values = state.metadataChips,
                    modifier = Modifier.padding(horizontal = 20.dp),
                )
            }
        }

        if (state.title.isNotBlank()) {
            item {
                DetailActions(
                    isResolvingStreams = state.isResolvingStreams,
                    selectedEpisodeLabel = state.selectedEpisodeLabel,
                    userRating = state.userRating,
                    onResolveStreams = onResolveStreams,
                    onSaveToLibrary = onSaveToLibrary,
                    onQueueResume = onQueueResume,
                    onQueueDownload = onQueueDownload,
                    onMarkWatched = onMarkWatched,
                    onMarkUnwatched = onMarkUnwatched,
                    onSetRating = onSetRating,
                    onClearRating = onClearRating,
                    modifier = Modifier.padding(horizontal = 16.dp),
                )
            }
        }

        if (state.collections.isNotEmpty()) {
            item {
                CollectionRow(
                    collections = state.collections,
                    onAddToCollection = onAddToCollection,
                    modifier = Modifier.padding(horizontal = 20.dp),
                )
            }
        }

        if (state.detailFacts.isNotEmpty()) {
            item {
                DetailFactsCard(
                    facts = state.detailFacts,
                    modifier = Modifier.padding(horizontal = 20.dp),
                )
            }
        }

        if (state.streamStatusMessage != null || state.streamCandidates.isNotEmpty()) {
            item {
                SectionHeading(
                    title = "Streams",
                    subtitle = state.streamStatusMessage,
                    modifier = Modifier.padding(horizontal = 20.dp),
                )
            }
        }

        if (state.streamStatusMessage != null && state.streamCandidates.isEmpty()) {
            item {
                GlassPanel(modifier = Modifier.padding(horizontal = 20.dp)) {
                    Text(
                        text = state.streamStatusMessage,
                        style = MaterialTheme.typography.bodyMedium,
                        color = MaterialTheme.colorScheme.onSurface.copy(alpha = 0.78f),
                    )
                }
            }
        }

        if (state.streamCandidates.isNotEmpty()) {
            items(state.streamCandidates, key = { it.id }) { stream ->
                StreamCandidateCard(
                    stream = stream,
                    onPlayStream = onPlayStream,
                    modifier = Modifier.padding(horizontal = 20.dp),
                )
            }
        }

        state.playerSource?.let { playerSource ->
            item {
                EclipsePlayerSurface(
                    source = playerSource,
                    preferredPlayer = preferredPlayer,
                    settings = playbackSettings,
                    skipSegments = state.skipSegments,
                    nextEpisodeLabel = state.nextEpisodeLabel(),
                    onNextEpisode = onPlayNextEpisode,
                    onProgress = onPlaybackProgress,
                    modifier = Modifier.padding(horizontal = 20.dp),
                )
            }
        }

        state.skipStatusMessage?.let { message ->
            item {
                GlassPanel(modifier = Modifier.padding(horizontal = 20.dp)) {
                    Text(
                        text = message,
                        style = MaterialTheme.typography.bodyMedium,
                        color = MaterialTheme.colorScheme.onSurface.copy(alpha = 0.78f),
                    )
                }
            }
        }

        if (state.cast.isNotEmpty()) {
            item {
                SectionHeading(
                    title = "Cast",
                    modifier = Modifier.padding(horizontal = 20.dp),
                )
            }
            item {
                LazyRow(
                    horizontalArrangement = Arrangement.spacedBy(14.dp),
                    contentPadding = PaddingValues(horizontal = 20.dp),
                ) {
                    items(state.cast, key = { it.id }) { cast ->
                        CastMember(cast = cast)
                    }
                }
            }
        }

        state.episodesTitle?.let { title ->
            if (state.episodes.isNotEmpty()) {
                item {
                    EpisodesHeader(
                        title = title,
                        isSeasonedShow = isSeasonedShow,
                        seasonMenu = state.seasonMenu,
                        episodeSeasons = episodeSeasons,
                        selectedSeason = selectedSeason,
                        onSelectSeason = { selectedSeason = it },
                        modifier = Modifier.padding(horizontal = 20.dp),
                    )
                }

                if (isSeasonedShow && !state.seasonMenu) {
                    item {
                        StyledSeasonSelector(
                            episodeSeasons = episodeSeasons,
                            selectedSeason = selectedSeason,
                            onSelectSeason = { selectedSeason = it },
                        )
                    }
                }

                if (state.horizontalEpisodeList) {
                    item {
                        LazyRow(
                            horizontalArrangement = Arrangement.spacedBy(14.dp),
                            contentPadding = PaddingValues(horizontal = 20.dp),
                        ) {
                            items(visibleEpisodes, key = { it.id }) { episode ->
                                EpisodeCard(
                                    episode = episode,
                                    onResolveEpisodeStreams = onResolveEpisodeStreams,
                                    onMarkEpisodeWatched = onMarkEpisodeWatched,
                                    onMarkEpisodeUnwatched = onMarkEpisodeUnwatched,
                                    onMarkPreviousEpisodesWatched = onMarkPreviousEpisodesWatched,
                                    modifier = Modifier.width(320.dp),
                                )
                            }
                        }
                    }
                } else {
                    items(visibleEpisodes, key = { it.id }) { episode ->
                        EpisodeCard(
                            episode = episode,
                            onResolveEpisodeStreams = onResolveEpisodeStreams,
                            onMarkEpisodeWatched = onMarkEpisodeWatched,
                            onMarkEpisodeUnwatched = onMarkEpisodeUnwatched,
                            onMarkPreviousEpisodesWatched = onMarkPreviousEpisodesWatched,
                            modifier = Modifier.padding(horizontal = 20.dp),
                        )
                    }
                }
            }
        }

        if (state.recommendations.isNotEmpty()) {
            item {
                SectionHeading(
                    title = "Recommendations",
                    modifier = Modifier.padding(horizontal = 20.dp),
                )
            }
            item {
                LazyRow(
                    horizontalArrangement = Arrangement.spacedBy(14.dp),
                    contentPadding = PaddingValues(horizontal = 20.dp),
                ) {
                    items(state.recommendations, key = { it.id }) { item ->
                        MediaPosterCard(
                            item = item,
                            onClick = onSelectRecommendation,
                            modifier = Modifier.width(150.dp),
                        )
                    }
                }
            }
        }
    }
}

@Composable
private fun DetailHero(
    title: String,
    subtitle: String?,
    imageUrl: String?,
    modifier: Modifier = Modifier,
) {
    Box(
        modifier = modifier
            .fillMaxWidth()
            .height(390.dp),
    ) {
        PosterImage(
            imageUrl = imageUrl,
            contentDescription = title,
            modifier = Modifier.fillMaxSize(),
        )
        Box(
            modifier = Modifier
                .fillMaxSize()
                .background(
                    Brush.verticalGradient(
                        colors = listOf(
                            Color.Transparent,
                            Color(0x44200E34),
                            Color(0xFF15081F),
                        ),
                    ),
                ),
        )
        Column(
            modifier = Modifier
                .align(Alignment.BottomCenter)
                .padding(horizontal = 20.dp, vertical = 18.dp),
            horizontalAlignment = Alignment.CenterHorizontally,
            verticalArrangement = Arrangement.spacedBy(8.dp),
        ) {
            subtitle?.takeIf { it.isNotBlank() }?.let {
                Text(
                    text = it.uppercase(),
                    style = MaterialTheme.typography.labelLarge,
                    color = MaterialTheme.colorScheme.tertiary,
                    textAlign = TextAlign.Center,
                    maxLines = 1,
                    overflow = TextOverflow.Ellipsis,
                )
            }
            Text(
                text = title,
                style = MaterialTheme.typography.displaySmall,
                fontWeight = FontWeight.Bold,
                color = Color.White,
                textAlign = TextAlign.Center,
                maxLines = 3,
                overflow = TextOverflow.Ellipsis,
            )
        }
    }
}

@Composable
private fun SynopsisBlock(
    text: String,
    modifier: Modifier = Modifier,
) {
    var expanded by remember(text) { mutableStateOf(false) }
    Text(
        text = text,
        modifier = modifier
            .fillMaxWidth()
            .clickable { expanded = !expanded },
        style = MaterialTheme.typography.bodyLarge,
        color = MaterialTheme.colorScheme.onBackground.copy(alpha = 0.9f),
        maxLines = if (expanded) Int.MAX_VALUE else 3,
        overflow = TextOverflow.Ellipsis,
    )
}

@Composable
private fun MetadataStrip(
    values: List<String>,
    modifier: Modifier = Modifier,
) {
    LazyRow(
        modifier = modifier.fillMaxWidth(),
        horizontalArrangement = Arrangement.spacedBy(8.dp),
    ) {
        items(values, key = { it }) { value ->
            Box(
                modifier = Modifier
                    .clip(RoundedCornerShape(100.dp))
                    .background(Color.White.copy(alpha = 0.12f))
                    .padding(horizontal = 12.dp, vertical = 7.dp),
            ) {
                Text(
                    text = value,
                    style = MaterialTheme.typography.labelMedium,
                    color = MaterialTheme.colorScheme.onBackground,
                    maxLines = 1,
                    overflow = TextOverflow.Ellipsis,
                )
            }
        }
    }
}

@Composable
private fun DetailActions(
    isResolvingStreams: Boolean,
    selectedEpisodeLabel: String?,
    userRating: Int?,
    onResolveStreams: () -> Unit,
    onSaveToLibrary: () -> Unit,
    onQueueResume: () -> Unit,
    onQueueDownload: () -> Unit,
    onMarkWatched: () -> Unit,
    onMarkUnwatched: () -> Unit,
    onSetRating: (Int) -> Unit,
    onClearRating: () -> Unit,
    modifier: Modifier = Modifier,
) {
    GlassPanel(
        modifier = modifier,
        contentPadding = PaddingValues(14.dp),
    ) {
        Column(verticalArrangement = Arrangement.spacedBy(10.dp)) {
            Row(
                modifier = Modifier.fillMaxWidth(),
                horizontalArrangement = Arrangement.spacedBy(8.dp),
            ) {
                Button(
                    onClick = onResolveStreams,
                    modifier = Modifier
                        .weight(1f)
                        .height(46.dp),
                    colors = ButtonDefaults.buttonColors(
                        containerColor = Color.White,
                        contentColor = Color(0xFF160A21),
                    ),
                ) {
                    Text(
                        text = when {
                            isResolvingStreams -> "Resolving"
                            selectedEpisodeLabel != null -> "Play $selectedEpisodeLabel"
                            else -> "Play"
                        },
                        maxLines = 1,
                        overflow = TextOverflow.Ellipsis,
                    )
                }
                OutlinedButton(
                    onClick = onSaveToLibrary,
                    modifier = Modifier.height(46.dp),
                ) {
                    Text("Save")
                }
                OutlinedButton(
                    onClick = onQueueDownload,
                    modifier = Modifier.height(46.dp),
                ) {
                    Text("Download")
                }
            }
            Row(
                modifier = Modifier.fillMaxWidth(),
                horizontalArrangement = Arrangement.spacedBy(8.dp),
            ) {
                OutlinedButton(
                    onClick = onQueueResume,
                    modifier = Modifier.weight(1f),
                ) {
                    Text("Resume")
                }
                OutlinedButton(
                    onClick = onMarkWatched,
                    modifier = Modifier.weight(1f),
                ) {
                    Text("Watched")
                }
                OutlinedButton(
                    onClick = onMarkUnwatched,
                    modifier = Modifier.weight(1f),
                ) {
                    Text("Reset")
                }
            }
            RatingRow(
                rating = userRating,
                onSetRating = onSetRating,
                onClearRating = onClearRating,
            )
        }
    }
}

@Composable
private fun RatingRow(
    rating: Int?,
    onSetRating: (Int) -> Unit,
    onClearRating: () -> Unit,
) {
    Row(
        modifier = Modifier.fillMaxWidth(),
        horizontalArrangement = Arrangement.spacedBy(6.dp),
        verticalAlignment = Alignment.CenterVertically,
    ) {
        Text(
            text = "Rating",
            style = MaterialTheme.typography.labelLarge,
            color = MaterialTheme.colorScheme.onSurface.copy(alpha = 0.78f),
            modifier = Modifier.width(52.dp),
        )
        (1..5).forEach { value ->
            if (rating == value) {
                Button(
                    onClick = { onSetRating(value) },
                    contentPadding = PaddingValues(horizontal = 0.dp),
                    modifier = Modifier
                        .weight(1f)
                        .height(38.dp),
                ) {
                    Text(value.toString())
                }
            } else {
                OutlinedButton(
                    onClick = { onSetRating(value) },
                    contentPadding = PaddingValues(horizontal = 0.dp),
                    modifier = Modifier
                        .weight(1f)
                        .height(38.dp),
                ) {
                    Text(value.toString())
                }
            }
        }
        if (rating != null) {
            TextButton(onClick = onClearRating) {
                Text("Clear")
            }
        }
    }
}

@Composable
private fun CollectionRow(
    collections: List<DetailCollectionRow>,
    onAddToCollection: (String) -> Unit,
    modifier: Modifier = Modifier,
) {
    Column(
        modifier = modifier,
        verticalArrangement = Arrangement.spacedBy(10.dp),
    ) {
        Text(
            text = "Collections",
            style = MaterialTheme.typography.titleMedium,
            color = MaterialTheme.colorScheme.onBackground,
        )
        LazyRow(horizontalArrangement = Arrangement.spacedBy(8.dp)) {
            items(collections, key = { it.id }) { collection ->
                if (collection.isSelected) {
                    Button(onClick = { onAddToCollection(collection.id) }) {
                        Text(collection.name, maxLines = 1, overflow = TextOverflow.Ellipsis)
                    }
                } else {
                    OutlinedButton(onClick = { onAddToCollection(collection.id) }) {
                        Text(collection.name, maxLines = 1, overflow = TextOverflow.Ellipsis)
                    }
                }
            }
        }
    }
}

@Composable
private fun DetailFactsCard(
    facts: List<DetailFactRow>,
    modifier: Modifier = Modifier,
) {
    Column(
        modifier = modifier,
        verticalArrangement = Arrangement.spacedBy(10.dp),
    ) {
        Text(
            text = "Details",
            style = MaterialTheme.typography.titleLarge,
            color = MaterialTheme.colorScheme.onBackground,
        )
        GlassPanel(contentPadding = PaddingValues(16.dp)) {
            Column(verticalArrangement = Arrangement.spacedBy(12.dp)) {
                facts.forEach { fact ->
                    Row(
                        modifier = Modifier.fillMaxWidth(),
                        horizontalArrangement = Arrangement.spacedBy(16.dp),
                    ) {
                        Text(
                            text = fact.label,
                            style = MaterialTheme.typography.bodyMedium,
                            color = MaterialTheme.colorScheme.onSurface.copy(alpha = 0.68f),
                            modifier = Modifier.width(92.dp),
                        )
                        Text(
                            text = fact.value,
                            style = MaterialTheme.typography.bodyMedium,
                            color = MaterialTheme.colorScheme.onSurface,
                            modifier = Modifier.weight(1f),
                        )
                    }
                }
            }
        }
    }
}

@Composable
private fun StreamCandidateCard(
    stream: DetailStreamRow,
    onPlayStream: (String) -> Unit,
    modifier: Modifier = Modifier,
) {
    GlassPanel(
        modifier = modifier,
        contentPadding = PaddingValues(16.dp),
    ) {
        Column(verticalArrangement = Arrangement.spacedBy(8.dp)) {
            Text(
                text = stream.title,
                style = MaterialTheme.typography.titleMedium,
                color = MaterialTheme.colorScheme.onSurface,
            )
            stream.subtitle?.let {
                Text(
                    text = it,
                    style = MaterialTheme.typography.bodyMedium,
                    color = MaterialTheme.colorScheme.tertiary,
                )
            }
            stream.supportingText?.let {
                Text(
                    text = it,
                    style = MaterialTheme.typography.bodyMedium,
                    color = MaterialTheme.colorScheme.onSurface.copy(alpha = 0.76f),
                )
            }
            if (stream.playable) {
                Button(onClick = { onPlayStream(stream.id) }) {
                    Text("Play Stream")
                }
            } else {
                Text(
                    text = "Only direct HTTP(S) stream URLs are accepted for playback.",
                    style = MaterialTheme.typography.bodySmall,
                    color = MaterialTheme.colorScheme.onSurface.copy(alpha = 0.7f),
                )
            }
        }
    }
}

@Composable
private fun CastMember(
    cast: DetailCastRow,
    modifier: Modifier = Modifier,
) {
    Column(
        modifier = modifier.width(92.dp),
        horizontalAlignment = Alignment.CenterHorizontally,
        verticalArrangement = Arrangement.spacedBy(8.dp),
    ) {
        PosterImage(
            imageUrl = cast.imageUrl,
            contentDescription = cast.name,
            modifier = Modifier
                .size(78.dp)
                .clip(CircleShape),
        )
        Text(
            text = cast.name,
            style = MaterialTheme.typography.labelLarge,
            color = MaterialTheme.colorScheme.onBackground,
            maxLines = 2,
            overflow = TextOverflow.Ellipsis,
            textAlign = TextAlign.Center,
        )
        cast.role?.let {
            Text(
                text = it,
                style = MaterialTheme.typography.labelSmall,
                color = MaterialTheme.colorScheme.onBackground.copy(alpha = 0.68f),
                maxLines = 2,
                overflow = TextOverflow.Ellipsis,
                textAlign = TextAlign.Center,
            )
        }
    }
}

@Composable
private fun EpisodesHeader(
    title: String,
    isSeasonedShow: Boolean,
    seasonMenu: Boolean,
    episodeSeasons: List<Int>,
    selectedSeason: Int?,
    onSelectSeason: (Int) -> Unit,
    modifier: Modifier = Modifier,
) {
    Row(
        modifier = modifier.fillMaxWidth(),
        horizontalArrangement = Arrangement.SpaceBetween,
        verticalAlignment = Alignment.CenterVertically,
    ) {
        Text(
            text = title,
            style = MaterialTheme.typography.titleLarge,
            color = MaterialTheme.colorScheme.onBackground,
        )
        if (isSeasonedShow && seasonMenu) {
            SeasonDropdown(
                episodeSeasons = episodeSeasons,
                selectedSeason = selectedSeason,
                onSelectSeason = onSelectSeason,
            )
        }
    }
}

@Composable
private fun SeasonDropdown(
    episodeSeasons: List<Int>,
    selectedSeason: Int?,
    onSelectSeason: (Int) -> Unit,
) {
    var expanded by remember(episodeSeasons, selectedSeason) { mutableStateOf(false) }
    Box {
        OutlinedButton(onClick = { expanded = true }) {
            Text("Season ${selectedSeason ?: episodeSeasons.firstOrNull() ?: 1}")
        }
        DropdownMenu(
            expanded = expanded,
            onDismissRequest = { expanded = false },
        ) {
            episodeSeasons.forEach { season ->
                DropdownMenuItem(
                    text = { Text("Season $season") },
                    onClick = {
                        onSelectSeason(season)
                        expanded = false
                    },
                )
            }
        }
    }
}

@Composable
private fun StyledSeasonSelector(
    episodeSeasons: List<Int>,
    selectedSeason: Int?,
    onSelectSeason: (Int) -> Unit,
) {
    LazyRow(
        horizontalArrangement = Arrangement.spacedBy(12.dp),
        contentPadding = PaddingValues(horizontal = 20.dp),
    ) {
        items(episodeSeasons, key = { it }) { season ->
            val selected = season == selectedSeason
            Column(
                modifier = Modifier
                    .width(82.dp)
                    .clickable { onSelectSeason(season) },
                horizontalAlignment = Alignment.CenterHorizontally,
                verticalArrangement = Arrangement.spacedBy(8.dp),
            ) {
                Box(
                    modifier = Modifier
                        .size(width = 82.dp, height = 122.dp)
                        .clip(RoundedCornerShape(12.dp))
                        .background(
                            Brush.linearGradient(
                                colors = listOf(
                                    Color(0xFF5F2EA0),
                                    Color(0xFF21102F),
                                    Color(0xFF0C0711),
                                ),
                            ),
                        )
                        .border(
                            width = if (selected) 2.dp else 0.dp,
                            color = if (selected) MaterialTheme.colorScheme.tertiary else Color.Transparent,
                            shape = RoundedCornerShape(12.dp),
                        ),
                    contentAlignment = Alignment.Center,
                ) {
                    Text(
                        text = "S$season",
                        style = MaterialTheme.typography.titleLarge,
                        fontWeight = FontWeight.Bold,
                        color = Color.White,
                    )
                }
                Text(
                    text = "Season $season",
                    style = MaterialTheme.typography.labelMedium,
                    color = if (selected) MaterialTheme.colorScheme.tertiary else MaterialTheme.colorScheme.onBackground,
                    maxLines = 1,
                    overflow = TextOverflow.Ellipsis,
                    textAlign = TextAlign.Center,
                )
            }
        }
    }
}

@Composable
private fun EpisodeCard(
    episode: DetailEpisodeRow,
    onResolveEpisodeStreams: (String) -> Unit,
    onMarkEpisodeWatched: (String) -> Unit,
    onMarkEpisodeUnwatched: (String) -> Unit,
    onMarkPreviousEpisodesWatched: (String) -> Unit,
    modifier: Modifier = Modifier,
) {
    GlassPanel(
        modifier = modifier,
        contentPadding = PaddingValues(12.dp),
    ) {
        Row(
            modifier = Modifier.fillMaxWidth(),
            horizontalArrangement = Arrangement.spacedBy(12.dp),
        ) {
            PosterImage(
                imageUrl = episode.imageUrl,
                contentDescription = episode.title,
                modifier = Modifier
                    .width(126.dp)
                    .height(74.dp)
                    .clip(RoundedCornerShape(10.dp)),
            )
            Column(
                modifier = Modifier.weight(1f),
                verticalArrangement = Arrangement.spacedBy(6.dp),
            ) {
                Text(
                    text = episode.title,
                    style = MaterialTheme.typography.titleMedium,
                    color = MaterialTheme.colorScheme.onSurface,
                    maxLines = 2,
                    overflow = TextOverflow.Ellipsis,
                )
                episode.subtitle?.let {
                    Text(
                        text = it,
                        style = MaterialTheme.typography.bodySmall,
                        color = MaterialTheme.colorScheme.tertiary,
                        maxLines = 1,
                        overflow = TextOverflow.Ellipsis,
                    )
                }
                episode.overview?.takeIf { it.isNotBlank() }?.let {
                    Text(
                        text = it,
                        style = MaterialTheme.typography.bodySmall,
                        color = MaterialTheme.colorScheme.onSurface.copy(alpha = 0.72f),
                        maxLines = 2,
                        overflow = TextOverflow.Ellipsis,
                    )
                }
                if (episode.seasonNumber != null && episode.episodeNumber != null) {
                    EpisodeActionRow(
                        episode = episode,
                        onResolveEpisodeStreams = onResolveEpisodeStreams,
                        onMarkEpisodeWatched = onMarkEpisodeWatched,
                        onMarkEpisodeUnwatched = onMarkEpisodeUnwatched,
                        onMarkPreviousEpisodesWatched = onMarkPreviousEpisodesWatched,
                    )
                }
            }
        }
    }
}

@Composable
private fun EpisodeActionRow(
    episode: DetailEpisodeRow,
    onResolveEpisodeStreams: (String) -> Unit,
    onMarkEpisodeWatched: (String) -> Unit,
    onMarkEpisodeUnwatched: (String) -> Unit,
    onMarkPreviousEpisodesWatched: (String) -> Unit,
) {
    Row(
        modifier = Modifier
            .fillMaxWidth()
            .heightIn(min = 36.dp),
        horizontalArrangement = Arrangement.spacedBy(2.dp),
        verticalAlignment = Alignment.CenterVertically,
    ) {
        TextButton(
            onClick = { onResolveEpisodeStreams(episode.id) },
            contentPadding = PaddingValues(horizontal = 8.dp),
        ) {
            Text("Play")
        }
        TextButton(
            onClick = { onMarkEpisodeWatched(episode.id) },
            contentPadding = PaddingValues(horizontal = 8.dp),
        ) {
            Text("Watched")
        }
        TextButton(
            onClick = { onMarkEpisodeUnwatched(episode.id) },
            contentPadding = PaddingValues(horizontal = 8.dp),
        ) {
            Text("Reset")
        }
        Spacer(modifier = Modifier.weight(1f))
        TextButton(
            onClick = { onMarkPreviousEpisodesWatched(episode.id) },
            contentPadding = PaddingValues(horizontal = 8.dp),
        ) {
            Text("Previous")
        }
    }
}

private fun DetailScreenState.nextEpisodeLabel(): String? {
    val playableEpisodes = episodes.filter {
        it.seasonNumber != null && it.episodeNumber != null
    }
    if (playableEpisodes.size < 2) return null
    val currentIndex = selectedEpisodeId
        ?.let { id -> playableEpisodes.indexOfFirst { it.id == id } }
        ?.takeIf { it >= 0 }
        ?: 0
    val nextEpisode = playableEpisodes.getOrNull(currentIndex + 1) ?: return null
    return nextEpisode.subtitle?.let { "Next $it" } ?: "Next Episode"
}
