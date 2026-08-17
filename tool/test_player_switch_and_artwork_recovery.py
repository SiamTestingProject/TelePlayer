from pathlib import Path
import unittest

ROOT = Path(__file__).resolve().parents[1]


class PlayerSwitchAndArtworkRecoveryTest(unittest.TestCase):
    def test_player_source_mutations_are_serialized_and_direct_handoff_is_guarded(self):
        source = (ROOT / "lib/src/features/player/application/player_controller.dart").read_text(encoding="utf-8")
        self.assertIn("_playerMutationTail", source)
        self.assertIn("_withPlayerMutation", source)
        self.assertIn("final directUri = await _libraryController.prepareDirectPlaybackUri(item);", source)
        self.assertIn("Direct-file preparation is optional", source)
        self.assertIn("_activePlaybackItem", source)

    def test_failed_artwork_requests_are_not_cached_forever(self):
        source = (ROOT / "lib/src/features/library/application/media_library_controller.dart").read_text(encoding="utf-8")
        self.assertIn("item.messageKey", source)
        self.assertIn("_thumbnailRequests.remove(requestKey)", source)
        self.assertIn("retryRemote: true", source)

    def test_high_quality_artwork_can_upgrade_a_small_cached_cover(self):
        source = (ROOT / "lib/src/features/library/data/media_repository.dart").read_text(encoding="utf-8")
        self.assertIn("EmbeddedArtwork.isHighResolution(cachedArtwork)", source)

    def test_player_artwork_carousel_prefetches_and_slides_between_tracks(self):
        source = (ROOT / "lib/src/features/player/presentation/player_screen.dart").read_text(encoding="utf-8")
        self.assertIn("_settleDuration = Duration(milliseconds: 360)", source)
        self.assertIn("_prefetchVisibleArtwork", source)
        self.assertIn("player-art-${item.messageKey}", source)
        self.assertIn("left: _travel + _dragOffset", source)
        self.assertIn("left: -_travel + _dragOffset", source)

    def test_resolved_artwork_is_available_synchronously_for_track_switches(self):
        controller = (ROOT / "lib/src/features/library/application/media_library_controller.dart").read_text(encoding="utf-8")
        artwork = (ROOT / "lib/src/features/library/presentation/media_artwork.dart").read_text(encoding="utf-8")
        self.assertIn("_resolvedThumbnails", controller)
        self.assertIn("cachedThumbnailFor", controller)
        self.assertIn("initialData: libraryController.cachedThumbnailFor", artwork)
        self.assertIn("gaplessPlayback: false", artwork)


if __name__ == "__main__":
    unittest.main()
