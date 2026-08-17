import sys
import tempfile
import unittest
import xml.etree.ElementTree as ElementTree
from pathlib import Path

sys.path.insert(0, str(Path(__file__).resolve().parent))

from configure_app_identity import (
    ANDROID_ADAPTIVE_ICON_ROOT,
    ANDROID_LAUNCHER_ICON_ROOT,
    ANDROID_ROUND_ICON_ROOT,
    WINDOWS_APP_ICON,
    configure_android,
    configure_windows,
)


class ConfigureAppIdentityTest(unittest.TestCase):
    def test_configures_android_display_name_and_is_idempotent(self) -> None:
        with tempfile.TemporaryDirectory() as directory:
            root = Path(directory)
            manifest = root / "android/app/src/main/AndroidManifest.xml"
            manifest.parent.mkdir(parents=True)
            build_file = root / "android/app/build.gradle.kts"
            build_file.parent.mkdir(parents=True, exist_ok=True)
            build_file.write_text(
                'android {\n'
                '    namespace = "com.example.telegram_media_player"\n'
                '    defaultConfig {\n'
                '        applicationId = "com.example.telegram_media_player"\n'
                '    }\n'
                '}\n',
                encoding="utf-8",
            )
            activity = (
                root
                / "android/app/src/main/kotlin/com/example/telegram_media_player/MainActivity.kt"
            )
            activity.parent.mkdir(parents=True, exist_ok=True)
            activity.write_text(
                'package com.example.telegram_media_player\n\n'
                'import io.flutter.embedding.android.FlutterActivity\n\n'
                'class MainActivity : FlutterActivity()\n',
                encoding="utf-8",
            )
            manifest.write_text(
                '<manifest xmlns:android="http://schemas.android.com/apk/res/android">\n'
                '    <application android:label="telegram_media_player" android:icon="@mipmap/ic_launcher">\n'
                '        <activity android:name=".MainActivity" />\n'
                '    </application>\n'
                '</manifest>\n',
                encoding="utf-8",
            )

            configure_android(root)
            configure_android(root)

            manifest_text = manifest.read_text()
            ElementTree.fromstring(manifest_text)
            self.assertIn('android:label="TelePlayer"', manifest_text)
            self.assertIn('android:icon="@mipmap/ic_launcher"', manifest_text)
            self.assertIn('namespace = "com.siam.teleplayer"', build_file.read_text())
            self.assertIn('applicationId = "com.siam.teleplayer"', build_file.read_text())
            moved_activity = (
                root / "android/app/src/main/kotlin/com/siam/teleplayer/MainActivity.kt"
            )
            self.assertTrue(moved_activity.is_file())
            moved_text = moved_activity.read_text()
            self.assertIn('package com.siam.teleplayer\n\n', moved_text)
            self.assertIn(
                'import io.flutter.embedding.android.FlutterActivity',
                moved_text,
            )
            self.assertNotIn(
                'com.siam.teleplayerimport',
                moved_text,
            )
            self.assertFalse(activity.exists())
            self.assertEqual(
                manifest_text.count('android.permission.INTERNET'),
                1,
            )
            self.assertEqual(
                manifest_text.count('android.permission.POST_NOTIFICATIONS'),
                1,
            )
            self.assertEqual(
                manifest_text.count(
                    'android.permission.REQUEST_IGNORE_BATTERY_OPTIMIZATIONS'
                ),
                1,
            )
            self.assertEqual(
                manifest_text.count('android:usesCleartextTraffic="true"'),
                1,
            )
            self.assertEqual(
                manifest_text.count('android.permission.WAKE_LOCK'),
                1,
            )
            self.assertEqual(
                manifest_text.count('android.permission.FOREGROUND_SERVICE"'),
                1,
            )
            self.assertEqual(
                manifest_text.count(
                    'android.permission.FOREGROUND_SERVICE_MEDIA_PLAYBACK'
                ),
                1,
            )
            self.assertEqual(
                manifest_text.count(
                    'android:name="com.ryanheise.audioservice.AudioServiceActivity"'
                ),
                1,
            )
            self.assertEqual(
                manifest_text.count(
                    'android:name="com.ryanheise.audioservice.AudioService"'
                ),
                1,
            )
            self.assertEqual(
                manifest_text.count('android:stopWithTask="false"'),
                1,
            )
            self.assertEqual(
                manifest_text.count(
                    'android:name="com.ryanheise.audioservice.MediaButtonReceiver"'
                ),
                1,
            )
            self.assertEqual(manifest_text.count('xmlns:tools='), 1)
            self.assertEqual(
                manifest_text.count(
                    'android:roundIcon="@mipmap/ic_launcher_round"'
                ),
                1,
            )
            primary_adaptive_icon = (
                root
                / 'android/app/src/main/res/mipmap-anydpi-v26/ic_launcher.xml'
            )
            self.assertFalse(primary_adaptive_icon.exists())
            adaptive_icon = (
                root
                / 'android/app/src/main/res/mipmap-anydpi-v26/ic_launcher_round.xml'
            )
            self.assertTrue(adaptive_icon.is_file())
            adaptive_text = adaptive_icon.read_text()
            self.assertIn('@drawable/ic_launcher_background', adaptive_text)
            self.assertIn('@drawable/ic_launcher_foreground', adaptive_text)
            adaptive_background = (
                root
                / 'android/app/src/main/res/drawable/ic_launcher_background.xml'
            )
            self.assertTrue(adaptive_background.is_file())
            self.assertIn('#FFF8F9FA', adaptive_background.read_text())
            for density in (
                'drawable-mdpi',
                'drawable-hdpi',
                'drawable-xhdpi',
                'drawable-xxhdpi',
                'drawable-xxxhdpi',
            ):
                installed_foreground = (
                    root
                    / 'android/app/src/main/res'
                    / density
                    / 'ic_launcher_foreground.png'
                )
                self.assertTrue(installed_foreground.is_file())
                self.assertEqual(
                    installed_foreground.read_bytes(),
                    (
                        ANDROID_ADAPTIVE_ICON_ROOT
                        / density
                        / 'ic_launcher_foreground.png'
                    ).read_bytes(),
                )
            for density in (
                "mipmap-mdpi",
                "mipmap-hdpi",
                "mipmap-xhdpi",
                "mipmap-xxhdpi",
                "mipmap-xxxhdpi",
            ):
                installed_round_icon = (
                    root
                    / "android/app/src/main/res"
                    / density
                    / "ic_launcher_round.png"
                )
                self.assertTrue(installed_round_icon.is_file())
                self.assertEqual(
                    installed_round_icon.read_bytes(),
                    (
                        ANDROID_ROUND_ICON_ROOT
                        / density
                        / "ic_launcher_round.png"
                    ).read_bytes(),
                )

            notification_icon = (
                root / "android/app/src/main/res/drawable/ic_stat_teleplayer.xml"
            )
            self.assertTrue(notification_icon.is_file())
            self.assertIn(
                'android:fillColor="#FFFFFFFF"',
                notification_icon.read_text(),
            )
            for density in (
                "mipmap-mdpi",
                "mipmap-hdpi",
                "mipmap-xhdpi",
                "mipmap-xxhdpi",
                "mipmap-xxxhdpi",
            ):
                installed_icon = (
                    root
                    / "android/app/src/main/res"
                    / density
                    / "ic_launcher.png"
                )
                self.assertTrue(installed_icon.is_file())
                self.assertEqual(
                    installed_icon.read_bytes(),
                    (ANDROID_LAUNCHER_ICON_ROOT / density / "ic_launcher.png").read_bytes(),
                )

    def test_configures_windows_product_and_binary_names(self) -> None:
        with tempfile.TemporaryDirectory() as directory:
            root = Path(directory)
            windows = root / "windows"
            runner = windows / "runner"
            runner.mkdir(parents=True)
            (windows / "CMakeLists.txt").write_text(
                'set(BINARY_NAME "telegram_media_player")\n',
                encoding="utf-8",
            )
            (runner / "main.cpp").write_text(
                'window.CreateAndShow(L"telegram_media_player", origin, size);\n',
                encoding="utf-8",
            )
            runner_rc = runner / "Runner.rc"
            runner_rc.write_text(
                'VALUE "FileDescription", "telegram_media_player" "\\0"\n'
                'VALUE "InternalName", "telegram_media_player" "\\0"\n'
                'VALUE "OriginalFilename", "telegram_media_player.exe" "\\0"\n'
                'VALUE "ProductName", "telegram_media_player" "\\0"\n',
                encoding="utf-8",
            )

            configure_windows(root)
            configure_windows(root)

            self.assertIn('set(BINARY_NAME "teleplayer")', (windows / "CMakeLists.txt").read_text())
            self.assertIn('L"TelePlayer"', (runner / "main.cpp").read_text())
            resource_text = runner_rc.read_text()
            self.assertIn('VALUE "FileDescription", "TelePlayer"', resource_text)
            self.assertIn('VALUE "InternalName", "teleplayer"', resource_text)
            self.assertIn('VALUE "OriginalFilename", "teleplayer.exe"', resource_text)
            self.assertIn('VALUE "ProductName", "TelePlayer"', resource_text)
            installed_icon = runner / "resources" / "app_icon.ico"
            self.assertTrue(installed_icon.is_file())
            self.assertEqual(installed_icon.read_bytes(), WINDOWS_APP_ICON.read_bytes())


if __name__ == "__main__":
    unittest.main()
