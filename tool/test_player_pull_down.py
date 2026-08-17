from pathlib import Path
import unittest

ROOT = Path(__file__).resolve().parents[1]


class PlayerPullDownTest(unittest.TestCase):
    def test_now_playing_surface_tracks_vertical_drag_and_dismisses_smoothly(self):
        source = (
            ROOT / "lib/src/features/player/presentation/player_screen.dart"
        ).read_text(encoding="utf-8")
        self.assertIn("class PlayerScreen extends StatefulWidget", source)
        self.assertIn("onVerticalDragUpdate: _handleVerticalDragUpdate", source)
        self.assertIn("onVerticalDragEnd: _handleVerticalDragEnd", source)
        self.assertIn("Transform.translate", source)
        self.assertIn("_dismissDistanceFraction = 0.18", source)
        self.assertIn("_dismissVelocity = 720", source)
        self.assertIn("_animateVerticalOffset(0", source)
        self.assertIn("_viewportHeight + 72", source)
        self.assertIn("widget.onClose()", source)

    def test_player_content_remains_fixed_instead_of_becoming_a_scroll_view(self):
        source = (
            ROOT / "lib/src/features/player/presentation/player_screen.dart"
        ).read_text(encoding="utf-8")
        self.assertIn("moves the whole surface instead of", source)
        self.assertNotIn("SingleChildScrollView(\n", source[:source.index("class _PlayerPalette")])


if __name__ == "__main__":
    unittest.main()
