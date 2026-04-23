package dev.soupy.eclipse.android.ui

import androidx.compose.runtime.Composable
import androidx.compose.runtime.remember
import androidx.lifecycle.ViewModel
import androidx.lifecycle.ViewModelProvider
import androidx.lifecycle.viewmodel.compose.viewModel

class SimpleViewModelFactory<T : ViewModel>(
    private val creator: () -> T,
) : ViewModelProvider.Factory {
    @Suppress("UNCHECKED_CAST")
    override fun <VM : ViewModel> create(modelClass: Class<VM>): VM = creator() as VM
}

@Composable
inline fun <reified VM : ViewModel> rememberFeatureViewModel(
    key: String,
    noinline creator: () -> VM,
): VM {
    val factory = remember(key) { SimpleViewModelFactory(creator) }
    return viewModel(key = key, factory = factory)
}


