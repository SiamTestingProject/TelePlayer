from pathlib import Path
import unittest


ROOT = Path(__file__).resolve().parents[1]


class SettingsNavigationAndPlaybackCleanupTest(unittest.TestCase):
    def test_settings_are_split_into_destination_pages(self):
        source = (
            ROOT / 'lib/src/features/settings/presentation/settings_screen.dart'
        ).read_text(encoding='utf-8')
        for page in (
            'TelegramSettingsPage',
            'PlaybackSettingsPage',
            'UpdatesSettingsPage',
        ):
            self.assertIn(page, source)
        self.assertIn('_SettingsDestinationCard', source)
        self.assertIn("title: 'Telegram'", source)
        self.assertIn("title: 'Playback'", source)
        self.assertIn("title: 'Updates'", source)

    def test_settings_destination_cards_are_compact(self):
        source = (
            ROOT / 'lib/src/features/settings/presentation/settings_screen.dart'
        ).read_text(encoding='utf-8')
        self.assertNotIn('const _SettingsHero()', source)
        self.assertIn('width: 48', source)
        self.assertIn('height: 48', source)
        self.assertIn('vertical: 10', source)
        self.assertIn('maxLines: 1', source)
        self.assertNotIn("status: 'Auto-clean enabled'", source)

    def test_verbose_playback_and_background_explanations_are_hidden(self):
        source = (
            ROOT / 'lib/src/features/settings/presentation/settings_screen.dart'
        ).read_text(encoding='utf-8')
        self.assertNotIn("title: 'Temporary song storage'", source)
        self.assertNotIn('TelePlayer downloads only what playback needs.', source)
        self.assertNotIn("title: 'Why this matters'", source)
        self.assertNotIn('Some Android devices aggressively limit background activity', source)

    def test_background_activity_settings_are_available(self):
        source = (
            ROOT / 'lib/src/features/settings/presentation/settings_screen.dart'
        ).read_text(encoding='utf-8')
        self.assertIn('BackgroundActivitySettingsPage', source)
        self.assertIn("title: 'Background activity'", source)
        self.assertIn('Permission.ignoreBatteryOptimizations', source)
        self.assertIn('Ignore battery optimization', source)

    def test_playback_cache_is_deleted_from_tdlib(self):
        client = (
            ROOT / 'lib/src/infrastructure/telegram/telegram_client.dart'
        ).read_text(encoding='utf-8')
        tdlib = (
            ROOT / 'lib/src/infrastructure/telegram/tdlib_telegram_client.dart'
        ).read_text(encoding='utf-8')
        self.assertIn('abstract interface class PlaybackCacheCleaner', client)
        self.assertIn('td.CancelDownloadFile(', tdlib)
        self.assertIn('td.DeleteFile(fileId: fileId)', tdlib)
        self.assertIn('Future<void> clearPlaybackCache(MediaItem item)', tdlib)

    def test_player_cleans_completed_and_replaced_tracks(self):
        player = (
            ROOT / 'lib/src/features/player/application/player_controller.dart'
        ).read_text(encoding='utf-8')
        self.assertIn('stalePlaybackItem.messageKey != item.messageKey', player)
        self.assertIn('unawaited(_clearPlaybackCache(stalePlaybackItem))', player)
        self.assertIn('_activePlaybackItem = item', player)
        self.assertIn('_advanceAfterCompletion(completedItem)', player)
        self.assertIn('await _clearPlaybackCache(completedItem)', player)

    def test_full_cache_cleanup_is_available_and_sweeps_all_app_caches(self):
        settings = (
            ROOT / 'lib/src/features/settings/presentation/settings_screen.dart'
        ).read_text(encoding='utf-8')
        controller = (
            ROOT / 'lib/src/features/library/application/media_library_controller.dart'
        ).read_text(encoding='utf-8')
        repository = (
            ROOT / 'lib/src/features/library/data/media_repository.dart'
        ).read_text(encoding='utf-8')
        client = (
            ROOT / 'lib/src/infrastructure/telegram/telegram_client.dart'
        ).read_text(encoding='utf-8')
        tdlib = (
            ROOT / 'lib/src/infrastructure/telegram/tdlib_telegram_client.dart'
        ).read_text(encoding='utf-8')

        self.assertIn('Fully clean everything', settings)
        self.assertIn('scope.playerController.stopPlayback()', settings)
        self.assertIn('scope.libraryController.clearAllCachedData()', settings)
        self.assertIn('clearAllCachedData()', controller)
        self.assertIn('_catalogCache.clearAll()', repository)
        self.assertIn('teleplayer-system-artwork', repository)
        self.assertIn('TelePlayer', repository)
        self.assertIn('abstract interface class FullCacheCleaner', client)
        self.assertIn('Future<void> clearAllCachedFiles', tdlib)
        self.assertIn('td.OptimizeStorage(', tdlib)



if __name__ == '__main__':
    unittest.main()
