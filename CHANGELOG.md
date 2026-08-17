## [1.4.24] - 2026-08-17

- Fixed `flutter analyze --fatal-infos` by removing the redundant direct `flutter/scheduler.dart` import from the Now Playing screen.
- Added a regression test so the unnecessary scheduler import cannot return.

# Changelog

## [1.4.23] - 2026-08-17

- Removed a redundant Flutter scheduler import so `flutter analyze --fatal-infos` passes cleanly.

## [1.4.22] - 2026-08-17

- Added a smooth pull-down gesture to the Now Playing page. The complete player surface now follows the finger instead of scrolling its internal controls.
- Releasing after a short pull springs the player back into place; pulling far enough or flicking downward dismisses the player.
- The player subtly scales and gains rounded top corners while being dragged for a more natural sheet-style transition.
- The header down button now uses the same full-page dismissal animation.

## [1.4.21] - 2026-08-17

- Reworked the Now Playing artwork carousel so song changes slide continuously instead of snapping between covers.
- Swiping a cover now finishes the visual carousel motion before the next/previous song is activated.
- Previous/next button changes use the same smooth directional artwork transition.
- Adjacent high-resolution covers are prefetched, and resolved artwork is kept in memory so the next song cover appears immediately instead of flashing the placeholder.
- Fixed stale FutureBuilder/image state that could briefly show the wrong or missing cover during rapid song changes.

## [1.4.20] - 2026-08-17

- Added a destructive **Fully clean everything** action in Playback settings.
- Full cleanup removes cached song audio, TDLib media files, album artwork, thumbnails, the local library catalog, temporary system artwork, legacy temporary media cache, and downloaded app updates.
- Full cleanup stops playback safely first and clears Flutter's in-memory image cache afterward.
- Telegram sign-in, API configuration, configured channels, and liked songs are intentionally preserved because they are user data rather than cache.

## [1.4.19] - 2026-08-17

- Fixed a crash that could occur when rapidly switching songs by serializing native player source changes.
- Direct-file background preparation is now cancellation-safe and cannot surface as an unhandled async error during a track change.
- Fixed album covers that could remain missing after a temporary Telegram thumbnail failure; failed artwork requests now retry instead of being cached forever.
- High-quality player artwork now upgrades low-resolution cached Telegram previews when better embedded artwork is available.

# TelePlayer Changelog

## [1.4.18] - 2026-08-17

### What's New

- Added an in-app Android update selector for ARM64, ARM32, x86_64, and Universal APKs.
- Update APKs now download directly inside TelePlayer without opening the GitHub website.
- Added a live animated wave download indicator with percentage, downloaded size, total size, and current download speed.
- ARM64 is selected by default for modern Android phones, while the other release architectures remain one tap away.
- Improved GitHub release-note parsing so the full changelog is shown in the update sheet.
- GitHub stable releases now publish this versioned changelog explicitly instead of relying on empty auto-generated notes.

## [1.4.17] - 2026-08-17

### What's New

- Reworked Android CI so validation, ABI APK builds, and AAB builds can run in parallel.
- Added Gradle build caching and generated the Universal APK from the App Bundle to reduce repeated build time.

## [1.4.16] - 2026-08-17

### What's New

- Added the new TelePlayer app logo to Android, Windows, the installer, and the authentication interface.
