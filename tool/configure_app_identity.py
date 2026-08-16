#!/usr/bin/env python3
"""Apply the TelePlayer product identity to generated Flutter host projects."""

from __future__ import annotations

import argparse
import re
from pathlib import Path


DISPLAY_NAME = "TelePlayer"
WINDOWS_BINARY_NAME = "teleplayer"
ANDROID_INTERNET_PERMISSION = (
    '<uses-permission android:name="android.permission.INTERNET" />'
)


def _replace(path: Path, pattern: str, replacement: str) -> None:
    if not path.is_file():
        raise FileNotFoundError(f"Generated host file is missing: {path}")
    original = path.read_text(encoding="utf-8")
    updated, count = re.subn(pattern, replacement, original, flags=re.MULTILINE)
    if count == 0:
        raise RuntimeError(f"Expected app identity entry was not found in {path}")
    if updated != original:
        path.write_text(updated, encoding="utf-8")


def configure_android(root: Path) -> None:
    manifest = root / "android" / "app" / "src" / "main" / "AndroidManifest.xml"
    _replace(
        manifest,
        r'android:label="[^"]*"',
        f'android:label="{DISPLAY_NAME}"',
    )
    original = manifest.read_text(encoding="utf-8")
    if "android.permission.INTERNET" not in original:
        updated, count = re.subn(
            r"(^\s*<application\b)",
            rf"    {ANDROID_INTERNET_PERMISSION}\n\1",
            original,
            count=1,
            flags=re.MULTILINE,
        )
        if count == 0:
            raise RuntimeError(f"Expected application entry was not found in {manifest}")
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
