from pathlib import Path
import unittest

ROOT = Path(__file__).resolve().parents[1]


class PlayerSwitchAndArtworkRecoveryTest(unittest.TestCase):
    def test_player_source_mutations_are_serialized_and_direct_handoff_is_guarded(self):
        source = (ROOT / "lib/src/features/player/application/player_controller.dart").read_text(encoding="utf-8")
        self.assertIn("_playerMutationTail", source)
        self.assertIn("_withPlayerMutation", source)
        self.assertIn("final directUriFuture =", source)
        self.assertIn("_libraryController.prepareDirectPlaybackUri(item);", source)
        self.assertIn("Direct-file preparation is optional", source)
        self.assertIn("_activePlaybackItem", source)
        self.assertIn("interruptedPrevious", source)
        self.assertIn("unawaited(_clearPlaybackCache(item));", source)
        self.assertNotIn("player.sequence?.", source)
        self.assertNotIn("player.sequence!", source)
        self.assertIn(
            "_preparedStreamUris.remove(item.messageKey)?.ignore();", source
        )

    def test_mini_player_swipes_keep_audio_handoff_and_animation_independent(self):
        source = (ROOT / "lib/src/app/app.dart").read_text(encoding="utf-8")
        self.assertIn("onHorizontalDragStart: _handleHorizontalDragStart", source)
        self.assertIn("unawaited(player.prepareForTransition(target));", source)
        self.assertIn("unawaited(player.open(target));", source)
        self.assertLess(
            source.index("unawaited(player.open(target));"),
            source.index("await _animateHorizontal(", source.index("unawaited(player.open(target));")),
        )
        self.assertIn("_pendingSwitchKey == targetKey", source)
        self.assertIn("ValueListenableBuilder<double>", source)

    def test_mini_player_pull_down_collapses_continuously(self):
        source = (ROOT / "lib/src/app/app.dart").read_text(encoding="utf-8")
        self.assertIn("onVerticalDragStart: _handleVerticalDragStart", source)
        self.assertIn("_verticalController.stop();", source)
        self.assertIn("heightFactor: 1 - verticalProgress", source)
        self.assertIn("projectedOffset", source)

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
        self.assertIn("_transitionItem?.messageKey == widget.item.messageKey", source)
        self.assertIn("_animateExternalSwitch(targetKey, direction)", source)

    def test_resolved_artwork_is_available_synchronously_for_track_switches(self):
        controller = (ROOT / "lib/src/features/library/application/media_library_controller.dart").read_text(encoding="utf-8")
        artwork = (ROOT / "lib/src/features/library/presentation/media_artwork.dart").read_text(encoding="utf-8")
        self.assertIn("_resolvedThumbnails", controller)
        self.assertIn("cachedThumbnailFor", controller)
        self.assertIn("initialData: libraryController.cachedThumbnailFor", artwork)
        self.assertIn("gaplessPlayback: true", artwork)


if __name__ == "__main__":
    unittest.main()
