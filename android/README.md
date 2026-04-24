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
- A working Media3 normal-player boundary with subtitle track import, subtitle styling, language defaults, hold-to-speed, 85s skip, external-player handoff, and landscape-lock settings
- JS runtime and WebView helper interfaces for the future sideload-first provider ecosystem
- Live TMDB/AniList-backed browse, search, detail, and airing schedule flows, including iOS-parity TMDB movie rows for now playing, upcoming, and top-rated movies
- Persisted Android-side library and continue-watching state, with direct-player progress now syncing typed movie/episode progress and resume entries automatically
- Android-owned parity stores for iOS backup sections including progress, catalogs, tracker state, ratings, recommendation cache, Kanzen modules, logs, cache metrics, and recent searches
- A DataStore-backed settings screen with player selection, subtitle/player defaults, next-episode controls, auto-mode warning, reader defaults, tracker account controls, storage diagnostics, logger controls, and iOS-style catalog enable/reorder controls
- Settings backup import/export that restores and re-exports Android-owned backup sections while preserving unsupported/unknown Luna backup data
- Home now respects the backed catalog order/visibility and includes iOS catalog IDs for Just For You, Because You Watched, networks, genres, companies, featured, ranked rows, TMDB rows, and AniList rows
- Search now stores recent queries locally and fetches multiple TMDB pages alongside AniList anime results
- Detail pages now hydrate richer TMDB metadata including content ratings, cast, recommendations, episode stills/runtimes/descriptions, and broader season coverage
- Detail pages now expose watched/unwatched actions, mark-previous-episodes support, and backed user ratings that feed the recommendation cache/user-ratings backup path
- First-pass Stremio addon stream resolution on TMDB movie and series detail pages, plus an AniList-to-TMDB anime bridge for resolving mapped anime episodes
- Episode-aware stream resolution from detail episode rows instead of only resolving the first series episode
- Offline downloads can capture resolved direct HTTP streams, package basic HLS playlists with AES-128 keys, download subtitle files, and persist local file metadata
- Settings can display restored AniList/Trakt tracker state, save manual token/PIN fallback accounts, toggle tracker sync, disconnect accounts, and export that state through the Luna backup shape
- Backup-backed manga and novel overview surfaces for restored Kanzen library/progress/module data, plus live AniList manga/novel browse/search, Android library save/remove actions, resettable reading progress, and Kanzen module URL add/update/toggle/remove controls on the Manga and Novel tabs
- Kanzen module adds and updates now fetch Luna-compatible manifests, resolve and validate `scriptURL`, preserve real source metadata, and keep the edited module list in the iOS-compatible backup path

## Version choices

The Android dependency versions in `gradle/libs.versions.toml` were chosen from current official release sources on April 23, 2026, including Android Developers, Kotlin docs, and official project release pages.

## Current limitations

- The full feature set from the Apple app is not finished yet. Android now has a real shell, persistence, catalog controls, backup flow, richer detail/progress actions, and first-pass Stremio resolution, but it is still short of full parity.
- Anime-specific source resolution now has an AniList-to-TMDB bridge, but it is still heuristic and not as complete as the Apple app's full AniList/TMDB episode reconstruction.
- Torrent-style Stremio results are surfaced in the UI, but they are not playable yet because Android still needs its torrent engine or alternate-player handoff work.
- OAuth tracker login/sync execution, manga/novel readers, full Kanzen JS runtime browsing, and native VLC/mpv backends are still earlier-stage compared with the Apple app. Media3 now owns the parity-backed playback implementation for direct streams.

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

1. Harden the anime-specific AniList/TMDB hybrid flow with the fuller iOS episode reconstruction and special/OVA mapping.
2. Broaden Stremio support with torrent or alternate-player handling, not just direct URL streams.
3. Feed the same playback progress layer into next-episode orchestration and tracker sync.
4. Expand tracker OAuth/sync execution, JS runtime, manga, and novel parity iteratively by milestone.
5. Keep hardening downloads with more offline playback edge cases, storage cleanup, and pause/resume behavior.
