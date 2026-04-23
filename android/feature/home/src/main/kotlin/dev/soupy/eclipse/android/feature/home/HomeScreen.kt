package dev.soupy.eclipse.android.feature.home

import androidx.compose.foundation.clickable
import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.PaddingValues
import androidx.compose.foundation.layout.fillMaxSize
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.layout.statusBarsPadding
import androidx.compose.foundation.layout.width
import androidx.compose.foundation.lazy.LazyColumn
import androidx.compose.foundation.lazy.LazyRow
import androidx.compose.foundation.lazy.items
import androidx.compose.material3.MaterialTheme
import androidx.compose.material3.Text
import androidx.compose.runtime.Composable
import androidx.compose.ui.Modifier
import androidx.compose.ui.unit.dp
import dev.soupy.eclipse.android.core.design.ErrorPanel
import dev.soupy.eclipse.android.core.design.HeroBackdrop
import dev.soupy.eclipse.android.core.design.LoadingPanel
import dev.soupy.eclipse.android.core.design.MediaPosterCard
import dev.soupy.eclipse.android.core.design.SectionHeading
import dev.soupy.eclipse.android.core.model.DetailTarget
import dev.soupy.eclipse.android.core.model.ExploreMediaCard
import dev.soupy.eclipse.android.core.model.MediaCarouselSection

data class HomeScreenState(
    val isLoading: Boolean = false,
    val errorMessage: String? = null,
    val hero: ExploreMediaCard? = null,
    val sections: List<MediaCarouselSection> = emptyList(),
)

@Composable
fun HomeRoute(
    state: HomeScreenState,
    onRefresh: () -> Unit,
    onSelect: (DetailTarget) -> Unit,
) {
    LazyColumn(
        modifier = Modifier
            .fillMaxSize()
            .statusBarsPadding(),
        verticalArrangement = Arrangement.spacedBy(20.dp),
        contentPadding = PaddingValues(horizontal = 20.dp, vertical = 18.dp),
    ) {
        item {
            Column(verticalArrangement = Arrangement.spacedBy(6.dp)) {
                Text(
                    text = "HOME",
                    style = MaterialTheme.typography.labelLarge,
                    color = MaterialTheme.colorScheme.tertiary,
                )
                Text(
                    text = "Luna's browse-first Android surface is live.",
                    style = MaterialTheme.typography.displayMedium,
                    color = MaterialTheme.colorScheme.onBackground,
                )
            }
        }

        state.hero?.let { hero ->
            item {
                HeroBackdrop(
                    title = hero.title,
                    subtitle = hero.badge ?: hero.subtitle,
                    imageUrl = hero.backdropUrl ?: hero.imageUrl,
                    supportingText = hero.overview,
                    modifier = Modifier.clickable { onSelect(hero.detailTarget) },
                )
            }
        }

        if (state.isLoading && state.sections.isEmpty()) {
            item {
                LoadingPanel(
                    title = "Loading discovery",
                    message = "Fetching TMDB and AniList rows for the new Android home screen.",
                )
            }
        }

        state.errorMessage?.let { error ->
            item {
                ErrorPanel(
                    title = "Home couldn't finish loading",
                    message = error,
                    actionLabel = "Try Again",
                    onAction = onRefresh,
                )
            }
        }

        items(state.sections, key = { it.id }) { section ->
            Column(verticalArrangement = Arrangement.spacedBy(12.dp)) {
                SectionHeading(
                    title = section.title,
                    subtitle = section.subtitle,
                )
                LazyRow(horizontalArrangement = Arrangement.spacedBy(14.dp)) {
                    items(section.items, key = { it.id }) { item ->
                        MediaPosterCard(
                            item = item,
                            onClick = { onSelect(it.detailTarget) },
                            modifier = Modifier.width(208.dp),
                        )
                    }
                }
            }
        }

        if (!state.isLoading && state.errorMessage == null && state.sections.isEmpty()) {
            item {
                ErrorPanel(
                    title = "Nothing landed yet",
                    message = "The Android home route is ready, but there were no browse sections to show.",
                    actionLabel = "Refresh",
                    onAction = onRefresh,
                )
            }
        }
    }
}

