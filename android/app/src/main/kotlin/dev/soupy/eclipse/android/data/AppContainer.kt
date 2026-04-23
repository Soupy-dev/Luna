package dev.soupy.eclipse.android.data

import android.content.Context
import androidx.compose.runtime.Composable
import androidx.compose.runtime.remember
import androidx.compose.ui.platform.LocalContext
import dev.soupy.eclipse.android.BuildConfig
import dev.soupy.eclipse.android.core.network.EclipseJson
import dev.soupy.eclipse.android.core.network.AniListService
import dev.soupy.eclipse.android.core.network.StremioService
import dev.soupy.eclipse.android.core.network.TmdbService
import dev.soupy.eclipse.android.core.storage.BackupFileStore
import dev.soupy.eclipse.android.core.storage.DownloadsStore
import dev.soupy.eclipse.android.core.storage.EclipseDatabase
import dev.soupy.eclipse.android.core.storage.LibraryStore
import dev.soupy.eclipse.android.core.storage.SettingsStore

class EclipseAppContainer(
    context: Context,
) {
    private val tmdbApiKey = BuildConfig.TMDB_API_KEY
    private val database: EclipseDatabase = EclipseDatabase.build(context)

    val tmdbService: TmdbService = TmdbService(apiKey = tmdbApiKey)
    val aniListService: AniListService = AniListService()
    val stremioService: StremioService = StremioService()
    val settingsStore: SettingsStore = SettingsStore(context)
    private val libraryStore: LibraryStore = LibraryStore(
        context = context,
        json = EclipseJson,
    )
    private val backupFileStore: BackupFileStore = BackupFileStore(
        context = context,
        json = EclipseJson,
    )
    private val downloadsStore: DownloadsStore = DownloadsStore(
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
    val streamResolutionRepository: StreamResolutionRepository = StreamResolutionRepository(
        tmdbService = tmdbService,
        stremioService = stremioService,
        stremioAddonDao = database.stremioAddonDao(),
        settingsStore = settingsStore,
    )
    val scheduleRepository: ScheduleRepository = ScheduleRepository(
        aniListService = aniListService,
    )
    val libraryRepository: LibraryRepository = LibraryRepository(
        libraryStore = libraryStore,
    )
    val servicesRepository: ServicesRepository = ServicesRepository(
        serviceDao = database.serviceDao(),
        stremioAddonDao = database.stremioAddonDao(),
        stremioService = stremioService,
    )
    val backupRepository: BackupRepository = BackupRepository(
        context = context,
        backupFileStore = backupFileStore,
        settingsStore = settingsStore,
        serviceDao = database.serviceDao(),
        stremioAddonDao = database.stremioAddonDao(),
    )
    val downloadsRepository: DownloadsRepository = DownloadsRepository(
        downloadsStore = downloadsStore,
    )
}

@Composable
fun rememberAppContainer(): EclipseAppContainer {
    val context = LocalContext.current.applicationContext
    return remember(context) {
        EclipseAppContainer(context)
    }
}

