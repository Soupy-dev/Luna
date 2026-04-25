package dev.soupy.eclipse.android.feature.search

import android.content.res.Configuration
import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.PaddingValues
import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.fillMaxSize
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.statusBarsPadding
import androidx.compose.foundation.lazy.LazyColumn
import androidx.compose.foundation.lazy.LazyRow
import androidx.compose.foundation.lazy.items
import androidx.compose.foundation.text.KeyboardActions
import androidx.compose.foundation.text.KeyboardOptions
import androidx.compose.material3.Button
import androidx.compose.material3.MaterialTheme
import androidx.compose.material3.OutlinedTextField
import androidx.compose.material3.Text
import androidx.compose.runtime.Composable
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.saveable.rememberSaveable
import androidx.compose.runtime.setValue
import androidx.compose.ui.Modifier
import androidx.compose.ui.platform.LocalConfiguration
import androidx.compose.ui.text.input.ImeAction
import androidx.compose.ui.unit.dp
import dev.soupy.eclipse.android.core.design.ErrorPanel
import dev.soupy.eclipse.android.core.design.LoadingPanel
import dev.soupy.eclipse.android.core.design.MediaPosterCard
import dev.soupy.eclipse.android.core.design.SectionHeading
import dev.soupy.eclipse.android.core.model.DetailTarget
import dev.soupy.eclipse.android.core.model.MediaCarouselSection

private enum class SearchFilter(val label: String) {
    ALL("All"),
    MOVIES("Movies"),
    TV("TV Shows"),
}

data class SearchScreenState(
    val query: String = "",
    val isSearching: Boolean = false,
    val errorMessage: String? = null,
    val recentQueries: List<String> = emptyList(),
    val sections: List<MediaCarouselSection> = emptyList(),
    val mediaColumnsPortrait: Int = 3,
    val mediaColumnsLandscape: Int = 5,
)

@Composable
fun SearchRoute(
    state: SearchScreenState,
    onQueryChange: (String) -> Unit,
    onSearch: () -> Unit,
    onRecentQuery: (String) -> Unit,
    onSelect: (DetailTarget) -> Unit,
) {
    val configuration = LocalConfiguration.current
    val columnCount = if (configuration.orientation == Configuration.ORIENTATION_LANDSCAPE) {
        state.mediaColumnsLandscape
    } else {
        state.mediaColumnsPortrait
    }.coerceIn(2, 8)
    var selectedFilter by rememberSaveable { mutableStateOf(SearchFilter.ALL) }
    val results = state.sections.flatMap { it.items }
    val filteredResults = when (selectedFilter) {
        SearchFilter.ALL -> results
        SearchFilter.MOVIES -> results.filter { it.detailTarget is DetailTarget.TmdbMovie }
        SearchFilter.TV -> results.filter { it.detailTarget is DetailTarget.TmdbShow }
    }

    LazyColumn(
        modifier = Modifier
            .fillMaxSize()
            .statusBarsPadding(),
        verticalArrangement = Arrangement.spacedBy(18.dp),
        contentPadding = PaddingValues(horizontal = 20.dp, vertical = 18.dp),
    ) {
        item {
            Column(verticalArrangement = Arrangement.spacedBy(6.dp)) {
                Text(
                    text = "SEARCH",
                    style = MaterialTheme.typography.labelLarge,
                    color = MaterialTheme.colorScheme.tertiary,
                )
                Text(
                    text = "Search Movies & TV Shows",
                    style = MaterialTheme.typography.displayMedium,
                    color = MaterialTheme.colorScheme.onBackground,
                )
            }
        }

        item {
            Column(verticalArrangement = Arrangement.spacedBy(12.dp)) {
                OutlinedTextField(
                    value = state.query,
                    onValueChange = onQueryChange,
                    label = { Text("Movie, show, or anime title") },
                    modifier = Modifier.fillMaxWidth(),
                    singleLine = true,
                    keyboardOptions = KeyboardOptions(imeAction = ImeAction.Search),
                    keyboardActions = KeyboardActions(onSearch = { onSearch() }),
                )
                Button(
                    onClick = onSearch,
                    enabled = state.query.isNotBlank() && !state.isSearching,
                    modifier = Modifier.fillMaxWidth(),
                ) {
                    Text("Search")
                }
            }
        }

        if (results.isNotEmpty()) {
            item {
                LazyRow(horizontalArrangement = Arrangement.spacedBy(10.dp)) {
                    items(SearchFilter.entries, key = { it.name }) { filter ->
                        if (filter == selectedFilter) {
                            Button(onClick = { selectedFilter = filter }) {
                                Text(filter.label)
                            }
                        } else {
                            androidx.compose.material3.OutlinedButton(onClick = { selectedFilter = filter }) {
                                Text(filter.label)
                            }
                        }
                    }
                }
            }
        }

        if (state.query.isBlank() && state.recentQueries.isNotEmpty()) {
            item {
                Column(verticalArrangement = Arrangement.spacedBy(12.dp)) {
                    SectionHeading(
                        title = "Recent Searches",
                        subtitle = "Saved locally on Android so repeated searches feel closer to Luna.",
                    )
                    LazyRow(horizontalArrangement = Arrangement.spacedBy(10.dp)) {
                        items(state.recentQueries, key = { it }) { query ->
                            Button(onClick = { onRecentQuery(query) }) {
                                Text(query)
                            }
                        }
                    }
                }
            }
        }

        if (state.isSearching) {
            item {
                LoadingPanel(
                    title = "Searching",
                    message = "Looking across TMDB movies and TV shows.",
                )
            }
        }

        state.errorMessage?.let { error ->
            item {
                ErrorPanel(
                    title = "Search hit a snag",
                    message = error,
                    actionLabel = "Retry",
                    onAction = onSearch,
                )
            }
        }

        if (state.query.isBlank() && state.sections.isEmpty()) {
            item {
                ErrorPanel(
                    title = "Start with a title",
                    message = "Search for a movie or TV show, then filter the results like Luna on iOS.",
                )
            }
        }

        if (results.isNotEmpty() && filteredResults.isEmpty()) {
            item {
                ErrorPanel(
                    title = "No ${selectedFilter.label.lowercase()} found",
                    message = "Try another filter or search for something else.",
                )
            }
        }

        if (filteredResults.isNotEmpty()) {
            item {
            Column(verticalArrangement = Arrangement.spacedBy(12.dp)) {
                SectionHeading(
                    title = "Search Results",
                    subtitle = "${filteredResults.size} ${selectedFilter.label.lowercase()} result${if (filteredResults.size == 1) "" else "s"}",
                )
                filteredResults.chunked(columnCount).forEach { rowItems ->
                    Row(
                        modifier = Modifier.fillMaxWidth(),
                        horizontalArrangement = Arrangement.spacedBy(12.dp),
                    ) {
                        rowItems.forEach { item ->
                            MediaPosterCard(
                                item = item,
                                onClick = { onSelect(item.detailTarget) },
                                modifier = Modifier.weight(1f),
                            )
                        }
                        repeat(columnCount - rowItems.size) {
                            Column(modifier = Modifier.weight(1f)) {}
                        }
                    }
                }
            }
            }
        }
    }
}

