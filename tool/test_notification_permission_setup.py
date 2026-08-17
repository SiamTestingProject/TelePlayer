import unittest
from pathlib import Path


ROOT = Path(__file__).resolve().parents[1]


class NotificationPermissionSetupTest(unittest.TestCase):
    def test_pubspec_includes_permission_handler(self) -> None:
        pubspec = (ROOT / "pubspec.yaml").read_text(encoding="utf-8")
        self.assertIn("permission_handler: ^12.0.3", pubspec)

    def test_app_requests_android_notification_permission(self) -> None:
        app = (ROOT / "lib/src/app/app.dart").read_text(encoding="utf-8")
        self.assertIn("Permission.notification.status", app)
        self.assertIn("Permission.notification.request()", app)
        self.assertIn("openAppSettings()", app)
        self.assertIn("defaultTargetPlatform != TargetPlatform.android", app)

    def test_generated_manifest_adds_notification_permission(self) -> None:
        identity = (ROOT / "tool/configure_app_identity.py").read_text(
            encoding="utf-8"
        )
        self.assertIn("android.permission.POST_NOTIFICATIONS", identity)
        self.assertIn("android.permission.FOREGROUND_SERVICE_MEDIA_PLAYBACK", identity)
        self.assertIn("com.ryanheise.audioservice.AudioService", identity)
        self.assertIn('android:stopWithTask="false"', identity)


if __name__ == "__main__":
    unittest.main()
