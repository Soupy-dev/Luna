package dev.soupy.eclipse.android.ui.settings

import androidx.lifecycle.ViewModel
import androidx.lifecycle.viewModelScope
import kotlinx.coroutines.flow.MutableStateFlow
import kotlinx.coroutines.flow.StateFlow
import kotlinx.coroutines.flow.asStateFlow
import kotlinx.coroutines.flow.collect
import kotlinx.coroutines.launch
import dev.soupy.eclipse.android.core.storage.AppSettings
import dev.soupy.eclipse.android.core.storage.SettingsStore
import dev.soupy.eclipse.android.core.model.InAppPlayer
import dev.soupy.eclipse.android.feature.settings.SettingsScreenState

class AndroidSettingsViewModel(
    private val settingsStore: SettingsStore,
) : ViewModel() {
    private val _state = MutableStateFlow(SettingsScreenState())
    val state: StateFlow<SettingsScreenState> = _state.asStateFlow()

    init {
        viewModelScope.launch {
            settingsStore.settings.collect { settings ->
                _state.value = settings.toUiState()
            }
        }
    }

    fun setAutoModeEnabled(enabled: Boolean) {
        viewModelScope.launch {
            settingsStore.setAutoModeEnabled(enabled)
        }
    }

    fun setShowNextEpisodeButton(enabled: Boolean) {
        val current = _state.value
        viewModelScope.launch {
            settingsStore.updatePlayback(
                inAppPlayer = current.inAppPlayer,
                showNextEpisodeButton = enabled,
                nextEpisodeThreshold = current.nextEpisodeThreshold,
            )
        }
    }

    fun setNextEpisodeThreshold(threshold: Int) {
        val current = _state.value
        viewModelScope.launch {
            settingsStore.updatePlayback(
                inAppPlayer = current.inAppPlayer,
                showNextEpisodeButton = current.showNextEpisodeButton,
                nextEpisodeThreshold = threshold.coerceIn(70, 98),
            )
        }
    }

    fun setInAppPlayer(player: InAppPlayer) {
        val current = _state.value
        viewModelScope.launch {
            settingsStore.updatePlayback(
                inAppPlayer = player,
                showNextEpisodeButton = current.showNextEpisodeButton,
                nextEpisodeThreshold = current.nextEpisodeThreshold,
            )
        }
    }
}

private fun AppSettings.toUiState(): SettingsScreenState = SettingsScreenState(
    accentColor = accentColor,
    tmdbLanguage = tmdbLanguage,
    autoModeEnabled = autoModeEnabled,
    showNextEpisodeButton = showNextEpisodeButton,
    nextEpisodeThreshold = nextEpisodeThreshold,
    inAppPlayer = inAppPlayer,
)
