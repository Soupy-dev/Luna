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
- Persisted Android-side library and continue-watching state, with direct-player progress now syncing resume entries automatically
- A DataStore-backed settings screen with player selection, next-episode controls, and the auto-mode warning
- Settings backup import/export that preserves unsupported Luna backup sections for later parity work
- First-pass Stremio addon stream resolution on TMDB movie and series detail pages, with direct URLs playable in the Android normal player

## Version choices

The Android dependency versions in `gradle/libs.versions.toml` were chosen from current official release sources on April 23, 2026, including Android Developers, Kotlin docs, and official project release pages.

## Current limitations

- The full feature set from the Apple app is not finished yet. Android now has a real shell, persistence, backup flow, and first-pass Stremio resolution, but it is still well short of full parity.
- Anime-specific source resolution is not wired into the Android stream resolver yet. The first supported path is TMDB movie and series detail.
- Torrent-style Stremio results are surfaced in the UI, but they are not playable yet because Android still needs its torrent engine or alternate-player handoff work.
- Services, downloads, trackers, manga, novels, and alternate player backends are still earlier-stage compared with the Apple app.

## Running on Windows

1. Open Android Studio and choose `Open`, then select the `android/` directory in this repo.
2. Let Gradle sync. The repo already includes `gradlew.bat`, so Android Studio can use the checked-in wrapper.
3. Create an emulator in `Device Manager`.
   Recommended starter target: a Pixel-class phone running a recent Google Play image.
4. Start the emulator.
5. In Android Studio, choose the `app` run configuration and click `Run`.

You can also build from a terminal:

`cd android`

`.\gradlew.bat :app:assembleDebug`

The debug APK will land under `android/app/build/outputs/apk/debug/`.

## Next recommended steps

1. Expand the resolver beyond TMDB movies and shows into the anime-specific AniList/TMDB hybrid flow.
2. Add real downloader execution behind the existing downloads queue and metadata state.
3. Broaden Stremio support with torrent or alternate-player handling, not just direct URL streams.
4. Feed the same playback progress layer into next-episode orchestration instead of only continue-watching sync.
5. Expand trackers, JS runtime, manga, and novel parity iteratively by milestone.
