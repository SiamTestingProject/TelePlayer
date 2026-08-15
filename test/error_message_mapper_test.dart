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
}
