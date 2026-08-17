from pathlib import Path
import unittest


ROOT = Path(__file__).resolve().parents[1]


class LibrarySectionsTest(unittest.TestCase):
    def test_library_contains_requested_sections(self):
        source = (ROOT / 'lib/src/features/library/presentation/library_screen.dart').read_text()
        for label in ('SONGS', 'ALBUMS', 'ARTISTS', 'PLAYLISTS', 'LIKED', 'FOLDERS'):
            self.assertIn("'%s'" % label, source)

    def test_section_tabs_are_eagerly_built_for_widget_tests_and_accessibility(self):
        source = (ROOT / 'lib/src/features/library/presentation/library_screen.dart').read_text()
        self.assertIn('SingleChildScrollView(', source)
        self.assertIn('child: Row(', source)
        self.assertIn("'library-section-${section.name}'", source)

    def test_library_sort_control_is_inline_and_shuffle_button_is_removed(self):
        source = (ROOT / 'lib/src/features/library/presentation/library_screen.dart').read_text()
        self.assertIn('SegmentedButton<MediaSortOrder>', source)
        self.assertIn("'library-sort-selector'", source)
        self.assertNotIn('PopupMenuButton<MediaSortOrder>', source)
        self.assertNotIn("label: const Text('Shuffle')", source)
        self.assertNotIn("'library-shuffle'", source)

    def test_liked_state_uses_stable_message_identity_and_persists(self):
        media = (ROOT / 'lib/src/features/library/models/media_item.dart').read_text()
        player = (ROOT / 'lib/src/features/player/application/player_controller.dart').read_text()
        self.assertIn("String get messageKey => '$chatId:$messageId';", media)
        self.assertIn('isFavoriteItem(MediaItem item)', player)
        self.assertIn('favorites.json', player)
        self.assertIn('initializeLibraryPreferences', player)

    def test_folder_and_album_metadata_are_carried_by_media_items(self):
        media = (ROOT / 'lib/src/features/library/models/media_item.dart').read_text()
        tdlib = (ROOT / 'lib/src/infrastructure/telegram/tdlib_telegram_client.dart').read_text()
        self.assertIn('final String? album;', media)
        self.assertIn('final String? sourceName;', media)
        self.assertIn('sourceName: _chatTitles[chatId]', tdlib)
        self.assertIn('album: _albumForMedia(media)', tdlib)


if __name__ == '__main__':
    unittest.main()
