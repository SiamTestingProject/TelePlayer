import 'dart:async';

import 'package:flutter/widgets.dart';

import '../core/services/local_streaming_server.dart';
import '../core/services/secure_config_store.dart';
import '../features/auth/application/auth_controller.dart';
import '../features/auth/data/auth_repository.dart';
import '../features/library/application/media_library_controller.dart';
import '../features/library/data/media_repository.dart';
import '../features/player/application/player_controller.dart';
import '../features/settings/application/settings_controller.dart';
import '../features/settings/data/settings_repository.dart';
import '../infrastructure/telegram/tdlib_gateway.dart';
import '../infrastructure/telegram/tdlib_telegram_client.dart';
import 'app.dart';
import 'app_scope.dart';

class AppBootstrap {
  AppBootstrap._({
    required this.authController,
    required this.libraryController,
    required this.playerController,
    required this.settingsController,
  });

  final AuthController authController;
  final MediaLibraryController libraryController;
  final PlayerController playerController;
  final SettingsController settingsController;

  static Future<AppBootstrap> create() async {
    final settingsController = SettingsController(
      SettingsRepository(SecureConfigStore()),
    );
    await settingsController.load();

    final telegramClient = TdlibTelegramClient(TdlibGateway());
    final authController = AuthController(
      repository: AuthRepository(telegramClient),
      settingsController: settingsController,
    );
    final libraryController = MediaLibraryController(
      repository: MediaRepository(
        telegramClient: telegramClient,
        streamingServer: LocalStreamingServer(telegramClient),
      ),
      settingsController: settingsController,
    );
    final playerController = PlayerController(libraryController);

    if (settingsController.settings.hasTelegramConfiguration) {
      unawaited(authController.initialize());
    }

    return AppBootstrap._(
      authController: authController,
      libraryController: libraryController,
      playerController: playerController,
      settingsController: settingsController,
    );
  }

  Widget buildApp() {
    return AppScope(
      authController: authController,
      libraryController: libraryController,
      playerController: playerController,
      settingsController: settingsController,
      child: const TelegramMediaPlayerApp(),
    );
  }
}
