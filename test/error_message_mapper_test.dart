import 'package:flutter_test/flutter_test.dart';
import 'package:telegram_media_player/src/core/errors/app_exception.dart';
import 'package:telegram_media_player/src/core/errors/error_message_mapper.dart';

void main() {
  const mapper = ErrorMessageMapper();

  test('maps rate limit with retry time', () {
    final friendly = mapper.map(
      const AppException(
        AppErrorCode.rateLimited,
        retryAfter: Duration(seconds: 42),
      ),
    );
    expect(friendly.title, 'Too many requests');
    expect(friendly.body, contains('42 seconds'));
  });

  test('maps deleted media without exposing exception text', () {
    final friendly = mapper.map(const AppException(AppErrorCode.deletedMedia));
    expect(friendly.title, 'Media was deleted');
    expect(friendly.body, isNot(contains('AppException')));
  });

  test('normalizes network-like errors', () {
    final friendly = mapper.map(Exception('SocketException: host lookup failed'));
    expect(friendly.title, 'No internet connection');
  });

  test('explains Telegram native library initialization failures', () {
    final friendly = mapper.map(
      const AppException(
        AppErrorCode.telegramInitialization,
        message: 'The bundled Telegram library could not be loaded.',
      ),
    );
    expect(friendly.title, 'Telegram engine could not start');
    expect(friendly.body, contains('bundled Telegram library'));
    expect(friendly.actionLabel, 'Retry');
  });

  test('preserves actionable Telegram authentication messages', () {
    final friendly = mapper.map(
      const AppException(
        AppErrorCode.telegramAuthFailed,
        message: 'Enter a phone number in international format.',
      ),
    );
    expect(friendly.title, 'Telegram sign-in failed');
    expect(friendly.body, contains('international format'));
  });
}
