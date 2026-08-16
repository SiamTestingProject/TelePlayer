import sys
import tempfile
import unittest
from pathlib import Path

sys.path.insert(0, str(Path(__file__).resolve().parent))

from validate_release_version import read_version, validate_tag


class ValidateReleaseVersionTest(unittest.TestCase):
    def test_reads_version_without_flutter_build_number(self) -> None:
        with tempfile.TemporaryDirectory() as directory:
            pubspec = Path(directory) / "pubspec.yaml"
            pubspec.write_text("name: test\nversion: 1.1.0+3\n", encoding="utf-8")

            self.assertEqual(read_version(pubspec), "1.1.0")
            validate_tag(pubspec, "v1.1.0")

    def test_rejects_mismatched_tag(self) -> None:
        with tempfile.TemporaryDirectory() as directory:
            pubspec = Path(directory) / "pubspec.yaml"
            pubspec.write_text("version: 1.1.0+3\n", encoding="utf-8")

            with self.assertRaisesRegex(RuntimeError, "does not match"):
                validate_tag(pubspec, "v1.0.9")


if __name__ == "__main__":
    unittest.main()
