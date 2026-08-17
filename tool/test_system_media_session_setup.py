import unittest
from pathlib import Path


ROOT = Path(__file__).resolve().parents[1]


class SystemMediaSessionSetupTest(unittest.TestCase):
    def test_uses_audio_service_directly_for_android_system_media(self) -> None:
        pubspec = (ROOT / "pubspec.yaml").read_text(encoding="utf-8")
        bootstrap = (ROOT / "lib/src/app/app_bootstrap.dart").read_text(encoding="utf-8")
        main = (ROOT / "lib/main.dart").read_text(encoding="utf-8")
        self.assertIn("audio_service: ^0.18.19", pubspec)
        self.assertNotIn("just_audio_background:", pubspec)
        self.assertIn("AudioService.init", bootstrap)
        self.assertIn("SystemMediaBridge", bootstrap)
        self.assertIn("androidStopForegroundOnPause: false", bootstrap)
        self.assertIn("drawable/ic_stat_teleplayer", bootstrap)
        self.assertNotIn("JustAudioBackground.init", main)

    def test_bridge_broadcasts_native_media_session_state_and_controls(self) -> None:
        bridge = (
            ROOT / "lib/src/features/player/application/system_media_bridge.dart"
        ).read_text(encoding="utf-8")
        player = (
            ROOT / "lib/src/features/player/application/player_controller.dart"
        ).read_text(encoding="utf-8")
        self.assertIn("mediaItem.add", bridge)
        self.assertIn("playbackState.add", bridge)
        self.assertIn("MediaControl.skipToPrevious", bridge)
        self.assertIn("MediaControl.pause", bridge)
        self.assertIn("MediaControl.play", bridge)
        self.assertIn("MediaControl.skipToNext", bridge)
        self.assertIn("artUri: artUri", bridge)
        self.assertIn("Uri.file(file.path)", player)
        self.assertIn("final audio.AudioPlayer player", bridge)
        self.assertIn("_systemMediaBridge?.player ?? createTelePlayerAudioPlayer()", player)
        self.assertIn("_upgradeToDirectPlaybackFile", player)
        self.assertIn("prepareDirectPlaybackUri", player)


if __name__ == "__main__":
    unittest.main()
