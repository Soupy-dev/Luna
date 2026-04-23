package dev.soupy.eclipse.android.ui.home

import androidx.lifecycle.ViewModel
import androidx.lifecycle.viewModelScope
import kotlinx.coroutines.flow.MutableStateFlow
import kotlinx.coroutines.flow.StateFlow
import kotlinx.coroutines.flow.asStateFlow
import kotlinx.coroutines.flow.update
import kotlinx.coroutines.launch
import dev.soupy.eclipse.android.data.HomeRepository
import dev.soupy.eclipse.android.feature.home.HomeScreenState

class AndroidHomeViewModel(
    private val repository: HomeRepository,
) : ViewModel() {
    private val _state = MutableStateFlow(HomeScreenState(isLoading = true))
    val state: StateFlow<HomeScreenState> = _state.asStateFlow()

    init {
        refresh()
    }

    fun refresh() {
        viewModelScope.launch {
            _state.update { it.copy(isLoading = true, errorMessage = null) }
            repository.loadHome()
                .onSuccess { content ->
                    _state.value = HomeScreenState(
                        isLoading = false,
                        hero = content.hero,
                        sections = content.sections,
                    )
                }
                .onFailure { error ->
                    _state.update {
                        it.copy(
                            isLoading = false,
                            errorMessage = error.message ?: "Unknown home error.",
                        )
                    }
                }
        }
    }
}


