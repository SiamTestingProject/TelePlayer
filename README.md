# Telegram Media Player

A Flutter Material 3 app for Android and Windows that signs in to Telegram, browses configured channel media, and plays videos through a local range-aware streaming server.

## Current Architecture

- UI: `lib/src/features/*/presentation`
- State management: `ChangeNotifier` controllers in `application`
- Routing/app shell: `lib/src/app`
- Telegram API/client: `lib/src/infrastructure/telegram`
- Authentication: `lib/src/features/auth`
- Media repository: `lib/src/features/library`
- Streaming: `lib/src/core/services/local_streaming_server.dart`
- Media player: `lib/src/features/player`
- Local cache: `lib/src/core/services/local_cache_service.dart`
- Settings: `lib/src/features/settings`
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
flutter pub get
python3 tool/patch_tdlib_android_namespace.py --compile-sdk 36
flutter analyze
flutter test
flutter run
```

On Windows desktop, run `flutter config --enable-windows-desktop` before creating or building the host project.
The TDLib compatibility patch adds its required Android namespace and raises the
plugin's `compileSdk` from API 31 to API 36. This is required because current
AndroidX dependencies need API 34 or newer even though `tdlib` 1.6.0 still
declares API 31.

## Release

Every branch push and manual workflow run builds Android and Windows. After both
platform jobs finish successfully, one release job downloads all outputs and
publishes them together in a GitHub prerelease tagged `build-<run number>`.

Push a version tag such as `v1.0.0` to publish a normal GitHub Release instead.
Publishing a GitHub Release manually also rebuilds the project and attaches all
generated files to that release. Output names include:

- `TelegramMediaPlayer-v1.0.0.apk`
- `TelegramMediaPlayer-v1.0.0-arm64.apk`
- `TelegramMediaPlayer-v1.0.0-armeabi-v7a.apk`
- `TelegramMediaPlayer-v1.0.0-x86_64.apk`
- `TelegramMediaPlayer-v1.0.0-aab.aab`
- `TelegramMediaPlayer-v1.0.0-Setup.exe`
- `TelegramMediaPlayer-v1.0.0-windows-x64.zip`

The Windows `Setup.exe` is a real per-user installer created with Inno Setup. It
installs the complete Flutter release, creates Start Menu and optional desktop
shortcuts, registers an uninstaller, and can launch the app when setup finishes.
The Windows ZIP remains available as a portable alternative.

The workflow fails if dependency installation, analysis, tests, an Android or
Windows build, installer generation, packaging, artifact aggregation, or release
upload fails. GitHub Release publishing happens only after both platform jobs
succeed, so a release cannot contain only one platform's files.
