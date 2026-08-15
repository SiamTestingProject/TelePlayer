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
flutter analyze
flutter test
flutter run
```

On Windows desktop, run `flutter config --enable-windows-desktop` before creating or building the host project.

## Release

Every branch push runs GitHub Actions for Android and Windows, then stores compiled outputs as workflow artifacts.

Create a tag such as `v1.0.0` and push it to publish a GitHub Release. GitHub Actions will build and upload release artifacts named like:

- `TelegramMediaPlayer-v1.0.0.apk`
- `TelegramMediaPlayer-v1.0.0-arm64.apk`
- `TelegramMediaPlayer-v1.0.0-aab.aab`
- `TelegramMediaPlayer-v1.0.0-windows-x64.zip`

The workflow can also be started manually from the GitHub Actions tab. It fails on dependency install, analysis, tests, Android or Windows build, artifact rename, packaging, workflow artifact upload, or release upload errors.
