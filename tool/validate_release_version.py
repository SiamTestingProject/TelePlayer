#!/usr/bin/env python3
"""Verify that a GitHub release tag matches the Flutter package version."""

from __future__ import annotations

import argparse
import re
from pathlib import Path


VERSION_PATTERN = re.compile(
    r"^version:\s*(\d+\.\d+\.\d+)(?:\+\d+)?\s*$",
    flags=re.MULTILINE,
)


def read_version(pubspec: Path) -> str:
    if not pubspec.is_file():
        raise FileNotFoundError(f"pubspec.yaml was not found: {pubspec}")
    match = VERSION_PATTERN.search(pubspec.read_text(encoding="utf-8"))
    if match is None:
        raise RuntimeError("A numeric app version was not found in pubspec.yaml")
    return match.group(1)


def validate_tag(pubspec: Path, tag: str) -> None:
    version = read_version(pubspec)
    expected = f"v{version}"
    if tag != expected:
        raise RuntimeError(
            f"Release tag {tag!r} does not match app version {version!r}; "
            f"use tag {expected!r} or update pubspec.yaml."
        )


def main() -> int:
    parser = argparse.ArgumentParser()
    parser.add_argument("--pubspec", type=Path, default=Path("pubspec.yaml"))
    parser.add_argument("--tag", required=True)
    args = parser.parse_args()
    validate_tag(args.pubspec, args.tag)
    print(f"Release tag {args.tag} matches the Flutter app version.")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
