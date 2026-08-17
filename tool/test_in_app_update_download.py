from pathlib import Path
import unittest

ROOT = Path(__file__).resolve().parents[1]


class InAppUpdateDownloadTest(unittest.TestCase):
    def test_android_update_picker_exposes_all_release_architectures(self):
        source = (ROOT / "lib/src/features/update/models/app_update.dart").read_text(encoding="utf-8")
        sheet = (ROOT / "lib/src/features/update/presentation/app_update_sheet.dart").read_text(encoding="utf-8")
        for token in ("arm64", "arm32", "x86_64", "universal"):
            self.assertIn(token, source)
        self.assertIn("Choose Android version", sheet)
        self.assertIn("ARM64 is recommended", sheet)

    def test_update_download_stays_inside_app_and_reports_progress(self):
        service = (ROOT / "lib/src/features/update/data/app_update_service.dart").read_text(encoding="utf-8")
        controller = (ROOT / "lib/src/features/update/application/app_update_controller.dart").read_text(encoding="utf-8")
        sheet = (ROOT / "lib/src/features/update/presentation/app_update_sheet.dart").read_text(encoding="utf-8")
        self.assertIn("Future<String> downloadAsset", service)
        self.assertIn("TelePlayer${Platform.pathSeparator}updates", service)
        self.assertIn("bytesPerSecond", service)
        self.assertIn("downloadUpdateAsset", controller)
        self.assertIn("_DownloadWave", sheet)
        self.assertIn("_formatBytes(progress.receivedBytes)", sheet)
        self.assertIn("percentage", sheet)

    def test_release_uses_versioned_changelog_body(self):
        workflow = (ROOT / ".github/workflows/release.yml").read_text(encoding="utf-8")
        changelog = (ROOT / "CHANGELOG.md").read_text(encoding="utf-8")
        self.assertIn("Prepare release changelog", workflow)
        self.assertIn("body_path: release-notes.md", workflow)
        self.assertNotIn("generate_release_notes: true", workflow)
        self.assertIn("## [1.4.19]", changelog)
        self.assertIn("ARM64, ARM32, x86_64, and Universal APKs", changelog)


if __name__ == "__main__":
    unittest.main()
