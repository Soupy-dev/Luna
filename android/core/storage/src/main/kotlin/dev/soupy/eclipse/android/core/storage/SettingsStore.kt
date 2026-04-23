package dev.soupy.eclipse.android.core.storage

import android.content.Context
import androidx.datastore.preferences.core.Preferences
import androidx.datastore.preferences.core.booleanPreferencesKey
import androidx.datastore.preferences.core.edit
import androidx.datastore.preferences.core.intPreferencesKey
import androidx.datastore.preferences.core.stringPreferencesKey
import androidx.datastore.preferences.preferencesDataStore
import kotlinx.coroutines.flow.Flow
import kotlinx.coroutines.flow.map
import dev.soupy.eclipse.android.core.model.InAppPlayer

private const val SettingsFileName = "eclipse_settings"

private val Context.dataStore by preferencesDataStore(name = SettingsFileName)

data class AppSettings(
    val accentColor: String = "#6D8CFF",
    val tmdbLanguage: String = "en-US",
    val inAppPlayer: InAppPlayer = InAppPlayer.NORMAL,
    val autoModeEnabled: Boolean = true,
    val showNextEpisodeButton: Boolean = true,
    val nextEpisodeThreshold: Int = 90,
)

class SettingsStore(
    private val context: Context,
) {
    val settings: Flow<AppSettings> = context.dataStore.data.map(::toAppSettings)

    suspend fun updateAppearance(
        accentColor: String,
        tmdbLanguage: String,
    ) {
        context.dataStore.edit { prefs ->
            prefs[Keys.accentColor] = accentColor
            prefs[Keys.tmdbLanguage] = tmdbLanguage
        }
    }

    suspend fun updatePlayback(
        inAppPlayer: InAppPlayer,
        showNextEpisodeButton: Boolean,
        nextEpisodeThreshold: Int,
    ) {
        context.dataStore.edit { prefs ->
            prefs[Keys.inAppPlayer] = inAppPlayer.name
            prefs[Keys.showNextEpisodeButton] = showNextEpisodeButton
            prefs[Keys.nextEpisodeThreshold] = nextEpisodeThreshold
        }
    }

    suspend fun setAutoModeEnabled(enabled: Boolean) {
        context.dataStore.edit { prefs ->
            prefs[Keys.autoModeEnabled] = enabled
        }
    }

    private fun toAppSettings(preferences: Preferences): AppSettings = AppSettings(
        accentColor = preferences[Keys.accentColor] ?: "#6D8CFF",
        tmdbLanguage = preferences[Keys.tmdbLanguage] ?: "en-US",
        inAppPlayer = preferences[Keys.inAppPlayer]
            ?.runCatching(InAppPlayer::valueOf)
            ?.getOrNull()
            ?: InAppPlayer.NORMAL,
        autoModeEnabled = preferences[Keys.autoModeEnabled] ?: true,
        showNextEpisodeButton = preferences[Keys.showNextEpisodeButton] ?: true,
        nextEpisodeThreshold = preferences[Keys.nextEpisodeThreshold] ?: 90,
    )

    private object Keys {
        val accentColor = stringPreferencesKey("accent_color")
        val tmdbLanguage = stringPreferencesKey("tmdb_language")
        val inAppPlayer = stringPreferencesKey("in_app_player")
        val autoModeEnabled = booleanPreferencesKey("auto_mode_enabled")
        val showNextEpisodeButton = booleanPreferencesKey("show_next_episode_button")
        val nextEpisodeThreshold = intPreferencesKey("next_episode_threshold")
    }
}


