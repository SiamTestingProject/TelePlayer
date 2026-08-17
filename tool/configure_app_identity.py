#!/usr/bin/env python3
"""Apply the TelePlayer product identity to generated Flutter host projects."""

from __future__ import annotations

import argparse
import re
import shutil
from pathlib import Path



PROJECT_ROOT = Path(__file__).resolve().parents[1]
BRANDING_ROOT = PROJECT_ROOT / "assets" / "branding" / "platform"
ANDROID_LAUNCHER_ICON_ROOT = BRANDING_ROOT / "android"
ANDROID_ADAPTIVE_ICON_ROOT = ANDROID_LAUNCHER_ICON_ROOT / "adaptive"
ANDROID_ROUND_ICON_ROOT = ANDROID_LAUNCHER_ICON_ROOT / "round"
WINDOWS_APP_ICON = BRANDING_ROOT / "windows" / "app_icon.ico"
ANDROID_LAUNCHER_DENSITIES = (
    "mipmap-mdpi",
    "mipmap-hdpi",
    "mipmap-xhdpi",
    "mipmap-xxhdpi",
    "mipmap-xxxhdpi",
)
ANDROID_ADAPTIVE_FOREGROUND_DENSITIES = (
    "drawable-mdpi",
    "drawable-hdpi",
    "drawable-xhdpi",
    "drawable-xxhdpi",
    "drawable-xxxhdpi",
)
ANDROID_ROUND_ICON_DENSITIES = ANDROID_LAUNCHER_DENSITIES

DISPLAY_NAME = "TelePlayer"
WINDOWS_BINARY_NAME = "teleplayer"
ANDROID_APPLICATION_ID = "com.siam.teleplayer"
ANDROID_INTERNET_PERMISSION = (
    '<uses-permission android:name="android.permission.INTERNET" />'
)
ANDROID_NOTIFICATION_PERMISSION = (
    '<uses-permission android:name="android.permission.POST_NOTIFICATIONS" />'
)
ANDROID_BATTERY_OPTIMIZATION_PERMISSION = (
    '<uses-permission '
    'android:name="android.permission.REQUEST_IGNORE_BATTERY_OPTIMIZATIONS" />'
)
ANDROID_BACKGROUND_AUDIO_PERMISSIONS = (
    '<uses-permission android:name="android.permission.WAKE_LOCK" />',
    '<uses-permission android:name="android.permission.FOREGROUND_SERVICE" />',
    '<uses-permission '
    'android:name="android.permission.FOREGROUND_SERVICE_MEDIA_PLAYBACK" />',
)
ANDROID_CLEARTEXT_ATTRIBUTE = 'android:usesCleartextTraffic="true"'
ANDROID_TOOLS_NAMESPACE = 'xmlns:tools="http://schemas.android.com/tools"'
ANDROID_AUDIO_ACTIVITY = "com.ryanheise.audioservice.AudioServiceActivity"
ANDROID_NOTIFICATION_ICON_NAME = "ic_stat_teleplayer"
ANDROID_ADAPTIVE_ICON_BACKGROUND_XML = """<shape xmlns:android="http://schemas.android.com/apk/res/android"
    android:shape="rectangle">
    <solid android:color="#FFF8F9FA" />
</shape>
"""
ANDROID_ADAPTIVE_ICON_XML = """<adaptive-icon xmlns:android="http://schemas.android.com/apk/res/android">
    <background android:drawable="@drawable/ic_launcher_background" />
    <foreground android:drawable="@drawable/ic_launcher_foreground" />
</adaptive-icon>
"""
ANDROID_NOTIFICATION_ICON_XML = """<vector xmlns:android="http://schemas.android.com/apk/res/android"
    android:width="24dp"
    android:height="24dp"
    android:viewportWidth="24"
    android:viewportHeight="24">
    <path
        android:fillColor="#FFFFFFFF"
        android:pathData="M12,3v10.55A4,4 0,1 0,14,17V7h4V3h-6z" />
</vector>
"""
ANDROID_AUDIO_COMPONENTS = """        <service
            android:name="com.ryanheise.audioservice.AudioService"
            android:foregroundServiceType="mediaPlayback"
            android:exported="true"
            android:stopWithTask="false"
            tools:ignore="Instantiatable">
            <intent-filter>
                <action android:name="android.media.browse.MediaBrowserService" />
            </intent-filter>
        </service>
        <receiver
            android:name="com.ryanheise.audioservice.MediaButtonReceiver"
            android:exported="true"
            tools:ignore="Instantiatable">
            <intent-filter>
                <action android:name="android.intent.action.MEDIA_BUTTON" />
            </intent-filter>
        </receiver>
"""


def _replace(path: Path, pattern: str, replacement: str) -> None:
    if not path.is_file():
        raise FileNotFoundError(f"Generated host file is missing: {path}")
    original = path.read_text(encoding="utf-8")
    updated, count = re.subn(pattern, replacement, original, flags=re.MULTILINE)
    if count == 0:
        raise RuntimeError(f"Expected app identity entry was not found in {path}")
    if updated != original:
        path.write_text(updated, encoding="utf-8")



def _configure_android_application_id(root: Path) -> None:
    app_dir = root / "android" / "app"
    build_file = app_dir / "build.gradle.kts"
    kotlin_dsl = True
    if not build_file.is_file():
        build_file = app_dir / "build.gradle"
        kotlin_dsl = False
    if not build_file.is_file():
        raise FileNotFoundError(
            f"Generated Android app Gradle file is missing under {app_dir}"
        )

    original = build_file.read_text(encoding="utf-8")
    if kotlin_dsl:
        updated, namespace_count = re.subn(
            r'(?m)^(\s*)namespace\s*=\s*"[^"]+"',
            rf'\1namespace = "{ANDROID_APPLICATION_ID}"',
            original,
            count=1,
        )
        updated, application_count = re.subn(
            r'(?m)^(\s*)applicationId\s*=\s*"[^"]+"',
            rf'\1applicationId = "{ANDROID_APPLICATION_ID}"',
            updated,
            count=1,
        )
    else:
        updated, namespace_count = re.subn(
            r'(?m)^(\s*)namespace\s+["\'][^"\']+["\']',
            rf'\1namespace "{ANDROID_APPLICATION_ID}"',
            original,
            count=1,
        )
        updated, application_count = re.subn(
            r'(?m)^(\s*)applicationId\s+["\'][^"\']+["\']',
            rf'\1applicationId "{ANDROID_APPLICATION_ID}"',
            updated,
            count=1,
        )

    if namespace_count == 0:
        raise RuntimeError(f"Expected Android namespace was not found in {build_file}")
    if application_count == 0:
        raise RuntimeError(f"Expected Android applicationId was not found in {build_file}")
    if updated != original:
        build_file.write_text(updated, encoding="utf-8")

    for language in ("kotlin", "java"):
        source_root = app_dir / "src" / "main" / language
        if not source_root.is_dir():
            continue
        activity_files = list(source_root.rglob("MainActivity.kt")) + list(
            source_root.rglob("MainActivity.java")
        )
        for activity in activity_files:
            activity_text = activity.read_text(encoding="utf-8")
            activity_text, package_count = re.subn(
                r'(?m)^package[ \t]+[A-Za-z0-9_.]+[ \t]*;?',
                f'package {ANDROID_APPLICATION_ID}',
                activity_text,
                count=1,
            )
            if package_count == 0:
                raise RuntimeError(
                    f"Expected MainActivity package declaration was not found in {activity}"
                )
            destination = (
                source_root
                / Path(*ANDROID_APPLICATION_ID.split("."))
                / activity.name
            )
            destination.parent.mkdir(parents=True, exist_ok=True)
            destination.write_text(activity_text, encoding="utf-8")
            if activity.resolve() != destination.resolve():
                activity.unlink()


def _install_android_launcher_icons(root: Path) -> None:
    res_root = root / "android" / "app" / "src" / "main" / "res"
    for density in ANDROID_LAUNCHER_DENSITIES:
        source = ANDROID_LAUNCHER_ICON_ROOT / density / "ic_launcher.png"
        if not source.is_file():
            raise FileNotFoundError(f"TelePlayer launcher icon is missing: {source}")
        destination_dir = res_root / density
        destination_dir.mkdir(parents=True, exist_ok=True)
        shutil.copyfile(source, destination_dir / "ic_launcher.png")

    # Keep the primary application icon as a normal bitmap. Some Android
    # media/foreground-service stacks still inspect ApplicationInfo.icon when
    # playback starts, and changing that resource into an adaptive-icon XML can
    # trigger OEM-specific crashes. Recent-app surfaces can use roundIcon
    # independently, so install the adaptive artwork under ic_launcher_round.
    for density in ANDROID_ADAPTIVE_FOREGROUND_DENSITIES:
        source = ANDROID_ADAPTIVE_ICON_ROOT / density / "ic_launcher_foreground.png"
        if not source.is_file():
            raise FileNotFoundError(
                f"TelePlayer adaptive launcher foreground is missing: {source}"
            )
        destination_dir = res_root / density
        destination_dir.mkdir(parents=True, exist_ok=True)
        shutil.copyfile(source, destination_dir / "ic_launcher_foreground.png")

    for density in ANDROID_ROUND_ICON_DENSITIES:
        source = ANDROID_ROUND_ICON_ROOT / density / "ic_launcher_round.png"
        if not source.is_file():
            raise FileNotFoundError(
                f"TelePlayer round launcher icon is missing: {source}"
            )
        destination_dir = res_root / density
        destination_dir.mkdir(parents=True, exist_ok=True)
        shutil.copyfile(source, destination_dir / "ic_launcher_round.png")

    drawable_dir = res_root / "drawable"
    drawable_dir.mkdir(parents=True, exist_ok=True)
    (drawable_dir / "ic_launcher_background.xml").write_text(
        ANDROID_ADAPTIVE_ICON_BACKGROUND_XML,
        encoding="utf-8",
    )
    adaptive_dir = res_root / "mipmap-anydpi-v26"
    adaptive_dir.mkdir(parents=True, exist_ok=True)
    # Do not replace ic_launcher with adaptive XML: audio_service and some
    # OEM media stacks may resolve the primary application icon while starting
    # the foreground playback service. Keep that resource bitmap-backed.
    primary_adaptive = adaptive_dir / "ic_launcher.xml"
    if primary_adaptive.exists():
        primary_adaptive.unlink()
    (adaptive_dir / "ic_launcher_round.xml").write_text(
        ANDROID_ADAPTIVE_ICON_XML,
        encoding="utf-8",
    )


def _install_windows_app_icon(root: Path) -> None:
    if not WINDOWS_APP_ICON.is_file():
        raise FileNotFoundError(f"TelePlayer Windows icon is missing: {WINDOWS_APP_ICON}")
    destination = root / "windows" / "runner" / "resources" / "app_icon.ico"
    destination.parent.mkdir(parents=True, exist_ok=True)
    shutil.copyfile(WINDOWS_APP_ICON, destination)


def configure_android(root: Path) -> None:
    _configure_android_application_id(root)
    _install_android_launcher_icons(root)
    drawable_dir = root / "android" / "app" / "src" / "main" / "res" / "drawable"
    drawable_dir.mkdir(parents=True, exist_ok=True)
    (drawable_dir / f"{ANDROID_NOTIFICATION_ICON_NAME}.xml").write_text(
        ANDROID_NOTIFICATION_ICON_XML,
        encoding="utf-8",
    )
    manifest = root / "android" / "app" / "src" / "main" / "AndroidManifest.xml"
    _replace(
        manifest,
        r'android:label="[^"]*"',
        f'android:label="{DISPLAY_NAME}"',
    )
    original = manifest.read_text(encoding="utf-8")
    if 'android:roundIcon=' not in original:
        updated, count = re.subn(
            r'(android:label="TelePlayer")',
            r'\1\n        android:roundIcon="@mipmap/ic_launcher_round"',
            original,
            count=1,
        )
        if count == 0:
            raise RuntimeError(f"Expected TelePlayer label was not found in {manifest}")
        manifest.write_text(updated, encoding="utf-8")
        original = updated
    if ANDROID_TOOLS_NAMESPACE not in original:
        updated, count = re.subn(
            r"(<manifest\b[^>]*)(>)",
            rf"\1\n    {ANDROID_TOOLS_NAMESPACE}\2",
            original,
            count=1,
        )
        if count == 0:
            raise RuntimeError(f"Expected manifest entry was not found in {manifest}")
        manifest.write_text(updated, encoding="utf-8")
        original = updated
    permissions = (
        ANDROID_INTERNET_PERMISSION,
        ANDROID_NOTIFICATION_PERMISSION,
        ANDROID_BATTERY_OPTIMIZATION_PERMISSION,
        *ANDROID_BACKGROUND_AUDIO_PERMISSIONS,
    )
    for permission in permissions:
        permission_name = re.search(r'android:name="([^"]+)"', permission)
        assert permission_name is not None
        if permission_name.group(1) in original:
            continue
        updated, count = re.subn(
            r"(^\s*<application\b)",
            rf"    {permission}\n\1",
            original,
            count=1,
            flags=re.MULTILINE,
        )
        if count == 0:
            raise RuntimeError(f"Expected application entry was not found in {manifest}")
        manifest.write_text(updated, encoding="utf-8")
        original = updated
    if ANDROID_CLEARTEXT_ATTRIBUTE not in original:
        updated, count = re.subn(
            r'(android:label="TelePlayer")',
            rf'\1\n        {ANDROID_CLEARTEXT_ATTRIBUTE}',
            original,
            count=1,
        )
        if count == 0:
            raise RuntimeError(f"Expected TelePlayer label was not found in {manifest}")
        manifest.write_text(updated, encoding="utf-8")
        original = updated
    if ANDROID_AUDIO_ACTIVITY not in original:
        updated, count = re.subn(
            r'android:name="[^"]*MainActivity"',
            f'android:name="{ANDROID_AUDIO_ACTIVITY}"',
            original,
            count=1,
        )
        if count == 0:
            raise RuntimeError(f"Expected Flutter MainActivity was not found in {manifest}")
        manifest.write_text(updated, encoding="utf-8")
        original = updated
    if (
        'android:name="com.ryanheise.audioservice.AudioService"' in original
        and 'android:stopWithTask="false"' not in original
    ):
        updated, count = re.subn(
            r'(android:name="com\.ryanheise\.audioservice\.AudioService"[^>]*android:exported="true")',
            r'\1\n            android:stopWithTask="false"',
            original,
            count=1,
            flags=re.MULTILINE,
        )
        if count == 0:
            raise RuntimeError(f"Expected AudioService entry was not found in {manifest}")
        manifest.write_text(updated, encoding="utf-8")
        original = updated
    if (
        'android:name="com.ryanheise.audioservice.AudioService"'
        not in original
    ):
        updated, count = re.subn(
            r"(^\s*</application>)",
            rf"{ANDROID_AUDIO_COMPONENTS}\1",
            original,
            count=1,
            flags=re.MULTILINE,
        )
        if count == 0:
            raise RuntimeError(f"Expected application closing tag was not found in {manifest}")
        manifest.write_text(updated, encoding="utf-8")


def configure_windows(root: Path) -> None:
    windows = root / "windows"
    _install_windows_app_icon(root)
    _replace(
        windows / "CMakeLists.txt",
        r'set\(BINARY_NAME "[^"]+"\)',
        f'set(BINARY_NAME "{WINDOWS_BINARY_NAME}")',
    )
    _replace(
        windows / "runner" / "main.cpp",
        r'(window\.(?:Create|CreateAndShow)\(L")[^"]+("[^\n]*\))',
        rf'\g<1>{DISPLAY_NAME}\g<2>',
    )
    runner_rc = windows / "runner" / "Runner.rc"
    replacements = {
        "FileDescription": DISPLAY_NAME,
        "InternalName": WINDOWS_BINARY_NAME,
        "OriginalFilename": f"{WINDOWS_BINARY_NAME}.exe",
        "ProductName": DISPLAY_NAME,
    }
    for field, value in replacements.items():
        _replace(
            runner_rc,
            rf'(VALUE "{field}", ")[^"]*(" "\\0")',
            rf'\g<1>{value}\g<2>',
        )


def main() -> int:
    parser = argparse.ArgumentParser()
    parser.add_argument(
        "--platform",
        choices=("android", "windows", "all"),
        default="all",
    )
    parser.add_argument("--root", type=Path, default=Path.cwd())
    args = parser.parse_args()

    root = args.root.resolve()
    if args.platform in ("android", "all"):
        configure_android(root)
    if args.platform in ("windows", "all"):
        configure_windows(root)
    print(f"Configured {DISPLAY_NAME} identity for {args.platform}.")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
