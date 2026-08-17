from pathlib import Path
import unittest

ROOT = Path(__file__).resolve().parents[1]

class AnalyzerCleanupTest(unittest.TestCase):
    def test_animated_switcher_uses_null_aware_element(self):
        source = (ROOT / "lib/src/app/app.dart").read_text(encoding="utf-8")
        self.assertIn("?currentChild,", source)
        self.assertNotIn("if (currentChild != null) currentChild", source)

    def test_equalizer_constructor_and_builder_are_lint_clean(self):
        source = (ROOT / "lib/src/features/library/presentation/library_screen.dart").read_text(encoding="utf-8")
        self.assertIn("const _PlayingEqualizerIcon({required this.active});", source)
        self.assertIn("builder: (_, _) => CustomPaint(", source)
        self.assertNotIn("builder: (_, __) => CustomPaint(", source)

if __name__ == "__main__":
    unittest.main()
