## [1.4.30] - 2026-08-17

- Completely replaced the previous TelePlayer branding with the newly supplied black-background white/blue music-note logo across the Flutter UI, Android launcher/adaptive/round icons, Windows executable, and installer.
- Changed the Android adaptive-icon background to black and rebuilt all density assets so launchers, App Info, and Recent Apps use the new logo consistently.
- Fixed Previous/Next artwork transitions restarting on every PlayerController loading/buffering notification. Repeated rebuilds for the same target song are now ignored, preventing the cover from violently moving forward and snapping back.
- Prefetches the selected target cover before external track-switch animation and keeps the already-loaded cover visible while a higher-quality version resolves, reducing missing-cover flashes.

## [1.4.29] - 2026-08-17

- Fixed the Android playback crash `Invalid notification (no valid small icon)` by explicitly preserving TelePlayer's custom media notification icon from release resource shrinking.
- Added Android `res/raw/keep.xml` for `@drawable/ic_stat_teleplayer`, matching audio_service's requirement for dynamically resolved custom notification icons.
- Restored the primary Android adaptive launcher icon now that playback uses a completely separate notification resource; App Info, Recent Apps, and modern launchers no longer fall back to the legacy full-background bitmap.
- Rebuilt legacy/round raster fallbacks with transparent outer pixels and a centered TelePlayer mark so older Android surfaces do not show the uneven white crescent around the logo.

## [1.4.28] - 2026-08-17

- Android updates now open the system package installer automatically as soon as an APK finishes downloading.
- Added the Android install-unknown-apps permission flow; when required, TelePlayer opens the per-app permission screen and continues installation after permission is granted.
- Added a retryable Install button for an already-downloaded APK so installation can be reopened without downloading the update again.
- Added a private FileProvider path for safely handing the downloaded APK to Android's package installer.

## [1.4.27] - 2026-08-17

- Removed the explanatory Temporary song storage information card from Playback settings to keep the page compact.
- Removed the Why this matters information card from Background activity settings while keeping the battery-optimization control available.

## [1.4.26] - 2026-08-17

- Fixed the Android playback crash regression introduced by the adaptive launcher-icon update by keeping the primary application icon bitmap-backed for foreground media-service compatibility.
- Moved the adaptive artwork to the dedicated Android `roundIcon` resource so Recent Apps can still use the corrected TelePlayer icon without changing the primary icon resource type used by playback services.
- Added raster round-icon fallbacks for every Android density and regression coverage to keep the notification icon independent from launcher/adaptive resources.

## [1.4.25] - 2026-08-17

- Added a proper Android adaptive launcher icon so Recent Apps and OEM launchers no longer wrap TelePlayer's legacy square bitmap inside an extra system icon shape.
- Added an adaptive foreground layer derived from the existing TelePlayer logo, with a clean neutral background and safe-zone scaling for round, squircle, and other launcher masks.
- Added Android `roundIcon` metadata and CI identity tests so generated host projects retain the corrected icon resources.

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
