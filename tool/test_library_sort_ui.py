from pathlib import Path
import unittest

ROOT = Path(__file__).resolve().parents[1]


class LibrarySortUiTest(unittest.TestCase):
    def test_library_uses_compact_inline_sort_control_without_shuffle_button(self):
        source = (
            ROOT / 'lib/src/features/library/presentation/library_screen.dart'
        ).read_text(encoding='utf-8')
        self.assertIn('SegmentedButton<MediaSortOrder>', source)
        self.assertIn("ValueKey<String>('library-sort-control')", source)
        self.assertNotIn("ValueKey<String>('library-shuffle')", source)
        self.assertNotIn('PopupMenuButton<MediaSortOrder>', source)
        self.assertNotIn("label: const Text('Shuffle')", source)


if __name__ == '__main__':
    unittest.main()
