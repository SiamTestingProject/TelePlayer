#!/usr/bin/env python3
"""Apply the TelePlayer product identity to generated Flutter host projects."""

from __future__ import annotations

import argparse
import re
from pathlib import Path


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


def configure_android(root: Path) -> None:
    _configure_android_application_id(root)
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
