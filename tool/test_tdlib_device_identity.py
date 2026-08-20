from pathlib import Path
import unittest

ROOT = Path(__file__).resolve().parents[1]


class TdlibDeviceIdentityTest(unittest.TestCase):
    def test_android_telegram_session_uses_teleplayer_name(self):
        source = (
            ROOT / 'lib/src/infrastructure/telegram/tdlib_telegram_client.dart'
        ).read_text(encoding='utf-8')
        self.assertIn("if (io.Platform.isAndroid)", source)
        self.assertIn("return 'TelePlayer';", source)
        self.assertNotIn("return 'Flutter Android';", source)
        self.assertIn("applicationVersion: '1.4.35'", source)


if __name__ == '__main__':
    unittest.main()
