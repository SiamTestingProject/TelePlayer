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
        for density in (
            'drawable-mdpi',
            'drawable-hdpi',
            'drawable-xhdpi',
            'drawable-xxhdpi',
            'drawable-xxxhdpi',
        ):
            adaptive = (
                ROOT
                / 'assets/branding/platform/android/adaptive'
                / density
                / 'ic_launcher_foreground.png'
            )
            self.assertTrue(adaptive.is_file())
            self.assertGreater(adaptive.stat().st_size, 1_000)
        for density in (
            'mipmap-mdpi',
            'mipmap-hdpi',
            'mipmap-xhdpi',
            'mipmap-xxhdpi',
            'mipmap-xxxhdpi',
        ):
            round_icon = (
                ROOT
                / 'assets/branding/platform/android/round'
                / density
                / 'ic_launcher_round.png'
            )
            self.assertTrue(round_icon.is_file())
            self.assertGreater(round_icon.stat().st_size, 1_000)
        self.assertTrue(
            (ROOT / 'assets/branding/platform/windows/app_icon.ico').is_file()
        )


if __name__ == '__main__':
    unittest.main()
