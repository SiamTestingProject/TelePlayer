import sys
import tempfile
import unittest
from pathlib import Path

sys.path.insert(0, str(Path(__file__).resolve().parent))

import patch_tdlib_android_namespace as patcher


class PatchTdlibAndroidTest(unittest.TestCase):
    def test_patches_groovy_namespace_and_compile_sdk(self) -> None:
        with tempfile.TemporaryDirectory() as directory:
            android_dir = Path(directory) / "android"
            manifest = android_dir / "src" / "main" / "AndroidManifest.xml"
            manifest.parent.mkdir(parents=True)
            manifest.write_text(
                '<manifest package="dev.example.tdlib" />', encoding="utf-8"
            )
            build_file = android_dir / "build.gradle"
            build_file.write_text(
                "android {\n    compileSdkVersion 31\n}\n", encoding="utf-8"
            )

            patcher.patch_build_file(build_file, 36)

            result = build_file.read_text(encoding="utf-8")
            self.assertIn('namespace "dev.example.tdlib"', result)
            self.assertIn("compileSdkVersion 36", result)

    def test_patches_kotlin_compile_sdk_when_namespace_exists(self) -> None:
        with tempfile.TemporaryDirectory() as directory:
            build_file = Path(directory) / "build.gradle.kts"
            build_file.write_text(
                'android {\n    namespace = "dev.example.tdlib"\n'
                "    compileSdk = 34\n}\n",
                encoding="utf-8",
            )

            patcher.patch_build_file(build_file, 36)

            result = build_file.read_text(encoding="utf-8")
            self.assertIn("compileSdk = 36", result)

    def test_does_not_downgrade_newer_compile_sdk_and_is_idempotent(self) -> None:
        with tempfile.TemporaryDirectory() as directory:
            build_file = Path(directory) / "build.gradle"
            build_file.write_text(
                'android {\n    namespace "dev.example.tdlib"\n'
                "    compileSdkVersion 37\n}\n",
                encoding="utf-8",
            )

            patcher.patch_build_file(build_file, 36)
            first_result = build_file.read_text(encoding="utf-8")
            patcher.patch_build_file(build_file, 36)

            self.assertEqual(first_result, build_file.read_text(encoding="utf-8"))
            self.assertIn("compileSdkVersion 37", first_result)


if __name__ == "__main__":
    unittest.main()
