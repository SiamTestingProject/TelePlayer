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

    def test_audio_service_config_does_not_violate_const_assertion(self):
        source = (ROOT / "lib/src/app/app_bootstrap.dart").read_text(encoding="utf-8")
        self.assertIn("androidNotificationOngoing: false", source)
        self.assertIn("androidStopForegroundOnPause: false", source)
        self.assertNotIn(
            "androidNotificationOngoing: true,\n          androidStopForegroundOnPause: false",
            source,
        )

    def test_player_screen_does_not_import_scheduler_directly(self):
        source = (
            ROOT / "lib/src/features/player/presentation/player_screen.dart"
        ).read_text(encoding="utf-8")
        self.assertNotIn("package:flutter/scheduler.dart", source)
        self.assertIn("on TickerCanceled", source)

    def test_settings_screen_has_no_unused_settings_local(self):
        source = (
            ROOT / "lib/src/features/settings/presentation/settings_screen.dart"
        ).read_text(encoding="utf-8")
        main_build_prefix = source.split("class TelegramSettingsPage", 1)[0]
        self.assertNotIn("final settings = settingsController.settings;", main_build_prefix)

if __name__ == "__main__":
    unittest.main()
