package dev.soupy.eclipse.android.data

import android.content.Context
import androidx.compose.runtime.Composable
import androidx.compose.runtime.remember
import androidx.compose.ui.platform.LocalContext
import dev.soupy.eclipse.android.BuildConfig
import dev.soupy.eclipse.android.core.network.EclipseJson
import dev.soupy.eclipse.android.core.network.AniListService
import dev.soupy.eclipse.android.core.network.TmdbService
import dev.soupy.eclipse.android.core.storage.LibraryStore
import dev.soupy.eclipse.android.core.storage.SettingsStore

class EclipseAppContainer(
    context: Context,
) {
    private val tmdbApiKey = BuildConfig.TMDB_API_KEY

    val tmdbService: TmdbService = TmdbService(apiKey = tmdbApiKey)
    val aniListService: AniListService = AniListService()
    val settingsStore: SettingsStore = SettingsStore(context)
    private val libraryStore: LibraryStore = LibraryStore(
        context = context,
        json = EclipseJson,
    )

    val homeRepository: HomeRepository = HomeRepository(
        tmdbService = tmdbService,
        aniListService = aniListService,
        tmdbEnabled = tmdbApiKey.isNotBlank(),
    )
    val searchRepository: SearchRepository = SearchRepository(
        tmdbService = tmdbService,
        aniListService = aniListService,
        tmdbEnabled = tmdbApiKey.isNotBlank(),
    )
    val detailRepository: DetailRepository = DetailRepository(
        tmdbService = tmdbService,
        aniListService = aniListService,
    )
    val scheduleRepository: ScheduleRepository = ScheduleRepository(
        aniListService = aniListService,
    )
    val libraryRepository: LibraryRepository = LibraryRepository(
        libraryStore = libraryStore,
    )
}

@Composable
fun rememberAppContainer(): EclipseAppContainer {
    val context = LocalContext.current.applicationContext
    return remember(context) {
        EclipseAppContainer(context)
    }
}

