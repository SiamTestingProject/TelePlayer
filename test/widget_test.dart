import 'dart:async';
import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:telegram_media_player/src/app/app.dart';
import 'package:telegram_media_player/src/app/app_scope.dart';
import 'package:telegram_media_player/src/core/errors/app_exception.dart';
import 'package:telegram_media_player/src/core/services/local_streaming_server.dart';
import 'package:telegram_media_player/src/core/services/secure_config_store.dart';
import 'package:telegram_media_player/src/features/auth/application/auth_controller.dart';
import 'package:telegram_media_player/src/features/auth/data/auth_repository.dart';
import 'package:telegram_media_player/src/features/auth/models/auth_models.dart';
import 'package:telegram_media_player/src/features/library/application/media_library_controller.dart';
import 'package:telegram_media_player/src/features/library/data/media_repository.dart';
import 'package:telegram_media_player/src/features/library/models/media_item.dart';
import 'package:telegram_media_player/src/features/player/application/player_controller.dart';
import 'package:telegram_media_player/src/features/settings/application/settings_controller.dart';
import 'package:telegram_media_player/src/features/settings/data/settings_repository.dart';
import 'package:telegram_media_player/src/features/settings/models/app_settings.dart';
import 'package:telegram_media_player/src/features/update/application/app_update_controller.dart';
import 'package:telegram_media_player/src/features/update/data/app_update_service.dart';
import 'package:telegram_media_player/src/infrastructure/telegram/telegram_client.dart';

void main() {
  testWidgets('shows the authentication entry screen', (tester) async {
    final telegramClient = _FakeTelegramClient();
    final settingsController = SettingsController(_FakeSettingsRepository());
    final authController = AuthController(
      repository: AuthRepository(telegramClient),
      settingsController: settingsController,
    );
    final libraryController = MediaLibraryController(
      repository: _FakeMediaRepository(telegramClient),
      settingsController: settingsController,
    );
    final playerController = PlayerController(libraryController);
    final updateController = AppUpdateController(
      AppUpdateService(
        repository: '',
        installedVersionLoader: () async => '1.1.0',
        releaseLoader: (_) async => const <Object?>[],
      ),
    );

    addTearDown(() async {
      playerController.dispose();
      libraryController.dispose();
      authController.dispose();
      settingsController.dispose();
      updateController.dispose();
      await telegramClient.close();
    });

    await tester.pumpWidget(
      AppScope(
        authController: authController,
        libraryController: libraryController,
        playerController: playerController,
        settingsController: settingsController,
        updateController: updateController,
        child: const TelePlayerApp(),
      ),
    );

    expect(find.text('TelePlayer'), findsOneWidget);
    expect(find.text('Sign in to Telegram'), findsOneWidget);
    expect(find.byIcon(Icons.settings_outlined), findsWidgets);

    telegramClient.emitError(
      const AppException(
        AppErrorCode.telegramInitialization,
        message: 'The bundled Telegram library could not be loaded.',
      ),
    );
    await tester.pump();

    expect(find.text('Telegram engine could not start'), findsOneWidget);
    expect(find.textContaining('bundled Telegram library'), findsOneWidget);

    await settingsController.save(
      const AppSettings(
        apiId: 12345,
        apiHash: 'test-api-hash',
        channelIds: <int>[],
        cacheLimitMb: 4096,
        preferWifi: true,
      ),
    );
    telegramClient.emitStep(const AuthStep(AuthStepKind.needsPassword));
    await tester.pump();

    final passwordField = tester.widget<TextField>(
      find.byKey(const ValueKey<String>('telegram-two-step-password')),
    );
    expect(passwordField.keyboardType, TextInputType.visiblePassword);
    expect(passwordField.obscureText, isTrue);

    await tester.enterText(
      find.byKey(const ValueKey<String>('telegram-two-step-password')),
      'Letters123!',
    );
    await tester.tap(find.text('Verify password'));
    await tester.pump();

    expect(telegramClient.submittedPassword, 'Letters123!');

    telegramClient.emitStep(const AuthStep(AuthStepKind.ready));
    await tester.pump();
    await tester.pump();

    expect(find.text('Library'), findsWidgets);
    expect(find.text('Newest'), findsOneWidget);
    expect(find.text('Songs'), findsNothing);
    expect(find.text('Videos'), findsNothing);
    expect(find.text('All'), findsNothing);
  });
}

class _FakeSettingsRepository extends SettingsRepository {
  _FakeSettingsRepository() : super(SecureConfigStore());

  @override
  Future<AppSettings> load() => Future<AppSettings>.value(AppSettings.empty());

  @override
  Future<void> save(AppSettings settings) => Future<void>.value();
}

class _FakeMediaRepository extends MediaRepository {
  _FakeMediaRepository(TelegramClient telegramClient)
      : super(
          telegramClient: telegramClient,
          streamingServer: LocalStreamingServer(telegramClient),
        );

  @override
  Future<List<MediaItem>> loadRecent(AppSettings settings) {
    return Future<List<MediaItem>>.value(const <MediaItem>[]);
  }

  @override
  Future<Uri> streamUriFor(MediaItem item) {
    return Future<Uri>.value(Uri.parse('http://127.0.0.1:0/media'));
  }
}

class _FakeTelegramClient implements TelegramClient {
  final _authSteps = StreamController<AuthStep>.broadcast();
  final _errors = StreamController<AppException>.broadcast();
  String? submittedPassword;

  @override
  Stream<AuthStep> get authSteps => _authSteps.stream;

  @override
  Stream<AppException> get errors => _errors.stream;

  void emitError(AppException error) => _errors.add(error);

  void emitStep(AuthStep step) => _authSteps.add(step);

  @override
  Future<void> initialize(AppSettings settings) => Future<void>.value();

  @override
  Future<void> submitPhoneNumber(String phoneNumber) => Future<void>.value();

  @override
  Future<void> submitCode(String code) => Future<void>.value();

  @override
  Future<void> submitPassword(String password) async {
    submittedPassword = password;
  }

  @override
  Future<List<MediaItem>> listRecentMedia({
    required List<int> channelIds,
    required int limitPerChannel,
  }) =>
      Future<List<MediaItem>>.value(const <MediaItem>[]);

  @override
  Future<List<MediaItem>> listAllMedia({
    required List<int> channelIds,
    required void Function(MediaScanProgress progress) onProgress,
  }) =>
      Future<List<MediaItem>>.value(const <MediaItem>[]);

  @override
  Future<MediaItem> refreshMedia(MediaItem item) {
    return Future<MediaItem>.value(item);
  }

  @override
  Future<Uint8List> readFileRange(MediaItem item, int start, int end) {
    return Future<Uint8List>.value(Uint8List(0));
  }

  @override
  Future<Uint8List?> loadThumbnail(MediaItem item) {
    return Future<Uint8List?>.value();
  }

  @override
  Future<void> close() async {
    await _authSteps.close();
    await _errors.close();
  }
}
