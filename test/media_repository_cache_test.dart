import 'dart:async';
import 'dart:io';
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:telegram_media_player/src/core/errors/app_exception.dart';
import 'package:telegram_media_player/src/core/services/local_streaming_server.dart';
import 'package:telegram_media_player/src/features/auth/models/auth_models.dart';
import 'package:telegram_media_player/src/features/library/data/channel_catalog_cache.dart';
import 'package:telegram_media_player/src/features/library/data/media_repository.dart';
import 'package:telegram_media_player/src/features/library/models/channel_cache_progress.dart';
import 'package:telegram_media_player/src/features/library/models/media_item.dart';
import 'package:telegram_media_player/src/features/settings/models/app_settings.dart';
import 'package:telegram_media_player/src/infrastructure/telegram/telegram_client.dart';

void main() {
  test('keeps scanned catalog when a Telegram thumbnail download fails', () async {
    final directory = await Directory.systemTemp.createTemp(
      'teleplayer-media-cache-test-',
    );
    final telegram = _ThumbnailFailureTelegramClient();
    final cache = ChannelCatalogCache(
      directoryProvider: () async => directory,
    );
    final repository = MediaRepository(
      telegramClient: telegram,
      streamingServer: LocalStreamingServer(telegram),
      catalogCache: cache,
    );
    final progress = <ChannelCacheProgress>[];
    List<MediaItem>? availableItems;
    addTearDown(() async {
      await telegram.close();
      if (await directory.exists()) {
        await directory.delete(recursive: true);
      }
    });

    final items = await repository.cacheAll(
      const AppSettings(
        apiId: 1,
        apiHash: 'test-hash',
        channelIds: <int>[-1001],
        cacheLimitMb: 4096,
        preferWifi: true,
      ),
      onProgress: progress.add,
      onItemsAvailable: (items) => availableItems = items,
    );

    expect(items, hasLength(1));
    expect(availableItems, hasLength(1));
    expect(await cache.readItems(), hasLength(1));
    expect(progress.last.phase, ChannelCachePhase.complete);
    expect(progress.last.completedThumbnails, 0);
    expect(progress.last.failedThumbnails, 1);
    expect(progress.last.processedThumbnails, 1);
  });
}

class _ThumbnailFailureTelegramClient implements TelegramClient {
  static const item = MediaItem(
    id: '-1001:20:2',
    chatId: -1001,
    messageId: 20,
    fileId: 2,
    title: 'Cached Track',
    fileName: 'cached-track.mp3',
    mimeType: 'audio/mpeg',
    size: 100,
    kind: MediaKind.audio,
    thumbnailFileId: 3,
  );

  @override
  Stream<AuthStep> get authSteps => const Stream<AuthStep>.empty();

  @override
  Stream<AppException> get errors => const Stream<AppException>.empty();

  @override
  Future<List<MediaItem>> listAllMedia({
    required List<int> channelIds,
    required void Function(MediaScanProgress progress) onProgress,
  }) async {
    onProgress(const MediaScanProgress(scannedMessages: 1, mediaCount: 1));
    return const <MediaItem>[item];
  }

  @override
  Future<Uint8List?> loadThumbnail(MediaItem item) {
    throw const AppException(
      AppErrorCode.telegramApi,
      message: 'File download has failed or was canceled',
    );
  }

  @override
  Future<List<MediaItem>> listRecentMedia({
    required List<int> channelIds,
    required int limitPerChannel,
  }) async =>
      const <MediaItem>[item];

  @override
  Future<MediaItem> refreshMedia(MediaItem item) async => item;

  @override
  Future<Uint8List> readFileRange(MediaItem item, int start, int end) async =>
      Uint8List(0);

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
