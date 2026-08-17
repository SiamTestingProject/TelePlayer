from pathlib import Path
import unittest


ROOT = Path(__file__).resolve().parents[1]


class IncrementalCacheAndBackgroundPlaybackTest(unittest.TestCase):
    def test_cache_uses_persisted_channel_anchors_and_only_new_artwork(self):
        repository = (
            ROOT / "lib/src/features/library/data/media_repository.dart"
        ).read_text(encoding="utf-8")
        cache = (
            ROOT / "lib/src/features/library/data/channel_catalog_cache.dart"
        ).read_text(encoding="utf-8")
        client = (
            ROOT / "lib/src/infrastructure/telegram/tdlib_telegram_client.dart"
        ).read_text(encoding="utf-8")
        self.assertIn("fullyScannedChannels", cache)
        self.assertIn("readFullyScannedChannels", repository)
        self.assertIn("afterMessageIdByChannel: scanAnchors", repository)
        self.assertIn("final newItems = scannedAudio", repository)
        self.assertIn("if (index >= newItems.length)", repository)
        self.assertIn("Future<List<MediaItem>> listMediaSince", client)
        self.assertIn("messageId <= afterMessageId", client)

    def test_android_player_is_service_owned_and_hands_off_to_native_file(self):
        bootstrap = (
            ROOT / "lib/src/app/app_bootstrap.dart"
        ).read_text(encoding="utf-8")
        bridge = (
            ROOT / "lib/src/features/player/application/system_media_bridge.dart"
        ).read_text(encoding="utf-8")
        player = (
            ROOT / "lib/src/features/player/application/player_controller.dart"
        ).read_text(encoding="utf-8")
        tdlib = (
            ROOT / "lib/src/infrastructure/telegram/tdlib_telegram_client.dart"
        ).read_text(encoding="utf-8")
        self.assertIn("AudioService.init<SystemMediaBridge>", bootstrap)
        self.assertIn("builder: SystemMediaBridge.new", bootstrap)
        self.assertIn("final audio.AudioPlayer player", bridge)
        self.assertIn("minBufferDuration: Duration(minutes: 2)", bridge)
        self.assertIn("_systemMediaBridge?.player", player)
        self.assertIn("_upgradeToDirectPlaybackFile", player)
        self.assertIn("audio.AudioSource.uri(directUri)", player)
        self.assertIn("synchronous: true", tdlib)
        self.assertIn("return Uri.file(path)", tdlib)


if __name__ == "__main__":
    unittest.main()
