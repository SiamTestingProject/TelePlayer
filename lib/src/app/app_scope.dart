import 'package:flutter/widgets.dart';

import '../features/auth/application/auth_controller.dart';
import '../features/library/application/media_library_controller.dart';
import '../features/player/application/player_controller.dart';
import '../features/settings/application/settings_controller.dart';
import '../features/update/application/app_update_controller.dart';

class AppScope extends InheritedWidget {
  const AppScope({
    required this.authController,
    required this.libraryController,
    required this.playerController,
    required this.settingsController,
    required this.updateController,
    required super.child,
    super.key,
  });

  final AuthController authController;
  final MediaLibraryController libraryController;
  final PlayerController playerController;
  final SettingsController settingsController;
  final AppUpdateController updateController;

  static AppScope of(BuildContext context) {
    final scope = context.dependOnInheritedWidgetOfExactType<AppScope>();
    assert(scope != null, 'AppScope not found in widget tree.');
    return scope!;
  }

  @override
  bool updateShouldNotify(AppScope oldWidget) {
    return authController != oldWidget.authController ||
        libraryController != oldWidget.libraryController ||
        playerController != oldWidget.playerController ||
        settingsController != oldWidget.settingsController ||
        updateController != oldWidget.updateController;
  }
}
