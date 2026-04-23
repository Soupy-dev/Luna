# Eclipse Android Port

This directory is the Android foundation for the Luna/Eclipse port. It lives beside the existing Apple app and does not change the current iOS target.

The Android namespace now uses `dev.soupy.eclipse.android` rather than the earlier `cranci`-based placeholder naming.

## What is implemented here

- A separate Android Gradle project rooted in `android/`
- Modular structure for:
  - `app`
  - `core:design`
  - `core:model`
  - `core:network`
  - `core:storage`
  - `core:player`
  - `core:js`
  - `feature:home`
  - `feature:search`
  - `feature:detail`
  - `feature:schedule`
  - `feature:services`
  - `feature:library`
  - `feature:downloads`
  - `feature:settings`
  - `feature:manga`
  - `feature:novel`
- A Luna-inspired Jetpack Compose shell with navigation across Home, Search, Detail, Schedule, Library, Settings, and the remaining planned feature routes
- Parity-minded core models for TMDB, AniList, Stremio, playback context, and backup data
- Network foundations using OkHttp plus Kotlin serialization
- Room/DataStore/file-backed persistence foundations
- A working Media3 normal-player boundary
- JS runtime and WebView helper interfaces for the future sideload-first provider ecosystem
- Live TMDB/AniList-backed browse, search, detail, and airing schedule flows
- Persisted Android-side library and continue-watching state
- A DataStore-backed settings screen with player selection, next-episode controls, and the auto-mode warning

## Version choices

The Android dependency versions in `gradle/libs.versions.toml` were chosen from current official release sources on April 23, 2026, including Android Developers, Kotlin docs, and official project release pages.

## Current limitations

- The full feature set from the Apple app is not finished yet. Milestone 1 is meaningfully underway, and Milestone 2 has started with library/progress/settings foundations.
- A Gradle wrapper was not generated in this environment because `gradle` is not installed locally here.
- Services, downloads, trackers, Stremio configuration, manga, novels, and alternate player backends are still earlier-stage or placeholder-only on Android.

## Next recommended steps

1. Generate the Gradle wrapper from this directory once Gradle is available:
   `gradle wrapper --gradle-version 9.3.1`
2. Open `android/` in Android Studio and run an initial sync.
3. Do the first real compile/sync pass and fix any dependency or Compose API issues that show up in Android Studio.
4. Replace the remaining placeholder feature routes, starting with Services and Downloads.
5. Connect real playback progress callbacks so continue watching becomes automatic instead of manually queued from Detail.
6. Expand trackers, Stremio, JS runtime, downloads, and backup parity iteratively by milestone.
