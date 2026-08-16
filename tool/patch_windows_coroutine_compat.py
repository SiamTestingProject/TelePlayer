#!/usr/bin/env python3
"""Patch Flutter's generated Windows CMake project for newer MSVC toolchains.

just_audio_windows 0.2.3 uses a C++/WinRT release that can include
<experimental/coroutine> when compiled as C++17. Newer MSVC toolchains turn the
header's deprecation notice into a hard static assertion unless the documented
silencing macro is defined.  Defining it at the app CMake directory level makes
it apply to generated plugin subdirectories without modifying the pub cache.
"""

from __future__ import annotations

import argparse
from pathlib import Path

MARKER = "_SILENCE_EXPERIMENTAL_COROUTINE_DEPRECATION_WARNINGS"
BLOCK = f"""
# Compatibility for plugins that still use the legacy C++/WinRT coroutine path.
# MSVC 14.51 / Visual Studio 18 promotes <experimental/coroutine>'s deprecation
# to a build-stopping static assertion. Keep the workaround scoped to MSVC and
# inherited by Flutter plugin subdirectories (notably just_audio_windows).
if(MSVC)
  add_compile_definitions({MARKER})
endif()
""".strip()


def patch_cmake(path: Path) -> bool:
    """Patch *path* in place. Returns True only when the file changed."""
    text = path.read_text(encoding="utf-8")
    if MARKER in text:
        return False

    lines = text.splitlines()
    insert_at: int | None = None

    # Flutter's Windows template declares project(...) near the top. Insert
    # immediately after it so the definition is active before plugin CMake
    # files are included later in the directory tree.
    for index, line in enumerate(lines):
        if line.lstrip().startswith("project("):
            insert_at = index + 1
            break

    if insert_at is None:
        raise RuntimeError(f"Could not find project(...) in {path}")

    block_lines = ["", *BLOCK.splitlines(), ""]
    lines[insert_at:insert_at] = block_lines
    path.write_text("\n".join(lines) + "\n", encoding="utf-8")
    return True


def main() -> int:
    parser = argparse.ArgumentParser()
    parser.add_argument(
        "--cmake",
        default="windows/CMakeLists.txt",
        help="Path to the generated Flutter Windows CMakeLists.txt",
    )
    args = parser.parse_args()

    cmake_path = Path(args.cmake)
    if not cmake_path.is_file():
        raise SystemExit(
            f"Windows CMake file not found: {cmake_path}. "
            "Run 'flutter create --platforms=windows .' first."
        )

    changed = patch_cmake(cmake_path)
    if changed:
        print(f"Patched {cmake_path} for modern MSVC coroutine compatibility.")
    else:
        print(f"{cmake_path} already contains the MSVC coroutine compatibility patch.")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
