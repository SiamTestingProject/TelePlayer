# TelePlayer

A Flutter Material 3 music app for Android and Windows that signs in to
Telegram, browses songs from configured channels, and plays audio through a
local range-aware streaming server.

Version 1.4 adds a category-driven, artwork-led Library with Songs, Albums,
Artists, Playlists, Liked, and Telegram-source Folders, plus persistent liked
songs, a persistent mini-player, a full-screen Now Playing experience,
queue/shuffle/repeat/favorite controls, and lower-latency Telegram playback. Android playback now runs through a media
foreground service, so songs continue while the app is backgrounded and remain
controllable from the notification, lock screen, and headset buttons. Android
also permits the app's loopback HTTP audio bridge, and open-ended player range
requests receive proper `206 Partial Content` responses so native playback can
initialize and seek reliably.

The Library download button scans the complete history of every configured
channel, ignores non-audio messages, and persistently caches song metadata plus
the best album artwork Telegram exposes. Artwork downloads are retried after a
message refresh, and Telegram's embedded mini artwork is retained as a fallback
when the full thumbnail is unavailable. Cached catalog entries remain browsable
when a later refresh is interrupted; audio payloads stay in TDLib's managed
cache and are downloaded as playback needs them. The Library category rail is horizontally scrollable, album/artist/folder
groups open into their songs, smart playlists include All Songs and Recently
Added, and the sort menu switches between **Newest** and **A-Z**.

## Current Architecture

- UI: `lib/src/features/*/presentation`
- State management: `ChangeNotifier` controllers in `application`
- Routing/app shell: `lib/src/app`
- Telegram API/client: `lib/src/infrastructure/telegram`
- Authentication: `lib/src/features/auth`
- Audio repository: `lib/src/features/library`
- Streaming: `lib/src/core/services/local_streaming_server.dart`
- Background audio player: `lib/src/features/player`
- Local catalog/artwork cache: `lib/src/features/library/data/channel_catalog_cache.dart`
- Media cache limits: `lib/src/core/services/local_cache_service.dart`
- Settings: `lib/src/features/settings`
- GitHub release updates: `lib/src/features/update`
- Models: feature `models` folders
- Errors: `lib/src/core/errors`

## Security

Telegram API ID, API hash, session credentials, tokens, signing keys, and keystores are not hardcoded. Runtime Telegram settings are stored with `flutter_secure_storage`. Release signing can be supplied through GitHub repository secrets:

- `ANDROID_KEYSTORE_BASE64`
- `ANDROID_KEY_ALIAS`
- `ANDROID_KEY_PASSWORD`
- `ANDROID_STORE_PASSWORD`
- `TDJSON_WINDOWS_DLL_BASE64` for optionally bundling `tdjson.dll` in Windows release ZIPs

Do not commit `.env`, session, keystore, or generated secret files.

Windows builds need the TDLib JSON runtime. Provide `tdjson.dll` next to the executable, configure its path in the Windows settings screen, or store a base64-encoded DLL in the `TDJSON_WINDOWS_DLL_BASE64` repository secret for release packaging.

## Local Development

Install Flutter 3.44.8 or newer, then run:

```bash
flutter create --platforms=android,windows --project-name telegram_media_player .
python tool/configure_app_identity.py --platform all
flutter pub get
python tool/patch_tdlib_android_namespace.py --compile-sdk 36
flutter analyze
flutter test
flutter run --dart-define=GITHUB_REPOSITORY=owner/repository
```

On Windows desktop, run `flutter config --enable-windows-desktop` before creating or building the host project.
The Android package/application ID is `com.siam.teleplayer`.
The identity step also installs the Android background-audio service, receiver,
foreground-service permissions, and loopback streaming permission. The TDLib
compatibility patch adds its required Android namespace and raises the plugin's
`compileSdk` from API 31 to API 36. This is required because current AndroidX
dependencies need API 34 or newer even though `tdlib` 1.6.0 still declares API
31.

## App Updates

TelePlayer checks stable GitHub Releases once after startup. A manual check is
also available from **Settings > App updates**. When a newer semantic version is
available, the app shows a draggable Material 3 changelog sheet and opens the
universal APK on Android or the Inno Setup installer on Windows. If that
platform asset is missing, it opens the GitHub Release page instead.

If GitHub has no public stable release yet, the updater reports that normal
state instead of showing the Releases API's `404` response as an app error.
Automatic `build-*` prereleases remain available on GitHub but are intentionally
ignored by the in-app stable updater.

The release repository is embedded at build time with
`--dart-define=GITHUB_REPOSITORY=owner/repository`. GitHub Actions supplies this
automatically. Android release builds also receive the background playback
components and required permissions from `tool/configure_app_identity.py`.

## Release

Every branch push and manual workflow run builds Android and Windows. After both
platform jobs finish successfully, one release job downloads all outputs and
publishes them together in a GitHub prerelease tagged `build-<run number>`.

Push a version tag such as `v1.4.8` to publish a normal GitHub Release instead.
Publishing a GitHub Release manually also rebuilds the project and attaches all
generated files to that release. A version tag must match the version in
`pubspec.yaml`, which prevents the updater from offering the currently installed
build again. Output names include:

- `TelePlayer-v1.4.8.apk`
- `TelePlayer-v1.4.8-arm64.apk`
- `TelePlayer-v1.4.8-armeabi-v7a.apk`
- `TelePlayer-v1.4.8-x86_64.apk`
- `TelePlayer-v1.4.8-aab.aab`
- `TelePlayer-v1.4.8-Setup.exe`
- `TelePlayer-v1.4.8-windows-x64.zip`

The Windows `Setup.exe` is a real per-user installer created with Inno Setup. It
installs the complete Flutter release, creates Start Menu and optional desktop
shortcuts, registers an uninstaller, and can launch the app when setup finishes.
The Windows ZIP remains available as a portable alternative.

The workflow fails if dependency installation, analysis, tests, an Android or
Windows build, installer generation, packaging, artifact aggregation, or release
upload fails. GitHub Release publishing happens only after both platform jobs
succeed, so a release cannot contain only one platform's files.
