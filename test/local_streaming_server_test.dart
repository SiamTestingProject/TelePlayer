import 'dart:async';
import 'dart:io';
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:telegram_media_player/src/core/errors/app_exception.dart';
import 'package:telegram_media_player/src/core/services/local_streaming_server.dart';
import 'package:telegram_media_player/src/features/auth/models/auth_models.dart';
import 'package:telegram_media_player/src/features/library/models/media_item.dart';
import 'package:telegram_media_player/src/features/settings/models/app_settings.dart';
import 'package:telegram_media_player/src/infrastructure/telegram/telegram_client.dart';

void main() {
  test('returns HTTP 206 for an open-ended player range request', () async {
    final telegram = _RangeTelegramClient(Uint8List.fromList(<int>[0, 1, 2, 3, 4]));
    final server = LocalStreamingServer(telegram);
    final httpClient = HttpClient();
    addTearDown(() async {
      httpClient.close(force: true);
      await server.stop();
    });

    const item = MediaItem(
      id: 'chat:message:file',
      chatId: -1001234567890,
      messageId: 42,
      fileId: 77,
      title: 'Example Track',
      fileName: 'Example Track.mp3',
      mimeType: 'audio/mpeg',
      size: 5,
      kind: MediaKind.audio,
    );
    final uri = await server.register(item);
    final request = await httpClient.getUrl(uri);
    request.headers.set(HttpHeaders.rangeHeader, 'bytes=0-');
    final response = await request.close();
    final body = await response.fold<List<int>>(
      <int>[],
      (bytes, chunk) => bytes..addAll(chunk),
    );

    expect(response.statusCode, HttpStatus.partialContent);
    expect(response.headers.value('accept-ranges'), 'bytes');
    expect(response.headers.value('content-range'), 'bytes 0-4/5');
    expect(response.headers.contentType?.mimeType, 'audio/mpeg');
    expect(body, <int>[0, 1, 2, 3, 4]);
  });
}

class _RangeTelegramClient implements TelegramClient {
  _RangeTelegramClient(this.bytes);

  final Uint8List bytes;

  @override
  Stream<AuthStep> get authSteps => const Stream<AuthStep>.empty();

  @override
  Stream<AppException> get errors => const Stream<AppException>.empty();

  @override
  Future<Uint8List> readFileRange(MediaItem item, int start, int end) async {
    return Uint8List.fromList(bytes.sublist(start, end + 1));
  }

  @override
  Future<MediaItem> refreshMedia(MediaItem item) async => item;

  @override
  Future<Uint8List?> loadThumbnail(MediaItem item) async => null;

  @override
  Future<List<MediaItem>> listRecentMedia({
    required List<int> channelIds,
    required int limitPerChannel,
  }) async =>
      const <MediaItem>[];

  @override
  Future<void> initialize(AppSettings settings) async {}

  @override
  Future<void> submitPhoneNumber(String phoneNumber) async {}

  @override
  Future<void> submitCode(String code) async {}

  @override
  Future<void> submitPassword(String password) async {}

  @override
  Future<void> close() async {}
}
