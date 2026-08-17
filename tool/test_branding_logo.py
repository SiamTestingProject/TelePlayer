from pathlib import Path
import unittest

ROOT = Path(__file__).resolve().parents[1]


class BrandingLogoTest(unittest.TestCase):
    def test_app_uses_teleplayer_logo_asset(self) -> None:
        logo = ROOT / 'assets/branding/teleplayer_logo.png'
        self.assertTrue(logo.is_file())
        self.assertGreater(logo.stat().st_size, 10_000)
        pubspec = (ROOT / 'pubspec.yaml').read_text(encoding='utf-8')
        self.assertIn('- assets/branding/teleplayer_logo.png', pubspec)
        auth = (
            ROOT / 'lib/src/features/auth/presentation/auth_screen.dart'
        ).read_text(encoding='utf-8')
        self.assertIn("Image.asset(\n              'assets/branding/teleplayer_logo.png'", auth)

    def test_platform_branding_assets_exist(self) -> None:
        for density in (
            'mipmap-mdpi',
            'mipmap-hdpi',
            'mipmap-xhdpi',
            'mipmap-xxhdpi',
            'mipmap-xxxhdpi',
        ):
            self.assertTrue(
                (
                    ROOT
                    / 'assets/branding/platform/android'
                    / density
                    / 'ic_launcher.png'
                ).is_file()
            )
        self.assertTrue(
            (ROOT / 'assets/branding/platform/windows/app_icon.ico').is_file()
        )


if __name__ == '__main__':
    unittest.main()
