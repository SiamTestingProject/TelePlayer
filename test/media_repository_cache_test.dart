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
      thumbnailRetryBaseDelay: Duration.zero,
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
    expect(telegram.thumbnailAttempts, 3);
    expect(telegram.refreshAttempts, 1);
  });

  test('uses Telegram inline artwork when full artwork stays unavailable', () async {
    final directory = await Directory.systemTemp.createTemp(
      'teleplayer-inline-artwork-test-',
    );
    final telegram = _ThumbnailFailureTelegramClient(
      items: const <MediaItem>[
        MediaItem(
          id: '-1001:21:4',
          chatId: -1001,
          messageId: 21,
          fileId: 4,
          title: 'Inline Artwork Track',
          fileName: 'inline-artwork.mp3',
          mimeType: 'audio/mpeg',
          size: 120,
          kind: MediaKind.audio,
          thumbnailFileId: 5,
          inlineThumbnailBase64: 'AQIDBA==',
        ),
      ],
    );
    final cache = ChannelCatalogCache(
      directoryProvider: () async => directory,
    );
    final repository = MediaRepository(
      telegramClient: telegram,
      streamingServer: LocalStreamingServer(telegram),
      catalogCache: cache,
      thumbnailRetryBaseDelay: Duration.zero,
    );
    final progress = <ChannelCacheProgress>[];
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
    );
    final bytes = await repository.loadThumbnail(items.single);

    expect(bytes, orderedEquals(<int>[1, 2, 3, 4]));
    expect(progress.last.phase, ChannelCachePhase.complete);
    expect(progress.last.completedThumbnails, 1);
    expect(progress.last.failedThumbnails, 0);
  });

  test('caches artwork discovered only after refreshing a song', () async {
    final directory = await Directory.systemTemp.createTemp(
      'teleplayer-refreshed-artwork-test-',
    );
    final telegram = _RefreshArtworkTelegramClient();
    final cache = ChannelCatalogCache(
      directoryProvider: () async => directory,
    );
    final repository = MediaRepository(
      telegramClient: telegram,
      streamingServer: LocalStreamingServer(telegram),
      catalogCache: cache,
      thumbnailRetryBaseDelay: Duration.zero,
    );
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
      onProgress: (_) {},
    );

    expect(items.single.hasThumbnail, isFalse);
    expect(telegram.refreshAttempts, 1);
    expect(telegram.thumbnailAttempts, 1);

    final cachedArtwork = await repository.loadThumbnail(items.single);
    expect(cachedArtwork, orderedEquals(<int>[9, 8, 7, 6]));
    expect(telegram.thumbnailAttempts, 1);
  });

  test('full cache replaces previously cached low-resolution artwork', () async {
    final directory = await Directory.systemTemp.createTemp(
      'teleplayer-artwork-upgrade-test-',
    );
    final telegram = _RefreshArtworkTelegramClient();
    final cache = ChannelCatalogCache(
      directoryProvider: () async => directory,
    );
    final repository = MediaRepository(
      telegramClient: telegram,
      streamingServer: LocalStreamingServer(telegram),
      catalogCache: cache,
      thumbnailRetryBaseDelay: Duration.zero,
    );
    final originalItem = telegram.items.single;
    await cache.writeArtwork(originalItem, Uint8List.fromList(<int>[1, 1]));
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
      onProgress: (_) {},
    );

    expect(telegram.refreshAttempts, 1);
    expect(telegram.thumbnailAttempts, 1);
    expect(
      await cache.readArtwork(items.single),
      orderedEquals(<int>[9, 8, 7, 6]),
    );
  });

  test('excludes Telegram video messages from the cached song library', () async {
    final directory = await Directory.systemTemp.createTemp(
      'teleplayer-audio-only-cache-test-',
    );
    final telegram = _ThumbnailFailureTelegramClient(
      items: const <MediaItem>[
        _ThumbnailFailureTelegramClient.defaultItem,
        MediaItem(
          id: '-1001:30:8',
          chatId: -1001,
          messageId: 30,
          fileId: 8,
          title: 'Video should be ignored',
          fileName: 'ignored.mp4',
          mimeType: 'video/mp4',
          size: 400,
          kind: MediaKind.document,
        ),
      ],
    );
    final cache = ChannelCatalogCache(
      directoryProvider: () async => directory,
    );
    final repository = MediaRepository(
      telegramClient: telegram,
      streamingServer: LocalStreamingServer(telegram),
      catalogCache: cache,
      thumbnailRetryBaseDelay: Duration.zero,
    );
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
      onProgress: (_) {},
    );

    expect(items, hasLength(1));
    expect(items.single.kind, MediaKind.audio);
  });
}

class _RefreshArtworkTelegramClient extends _ThumbnailFailureTelegramClient {
  _RefreshArtworkTelegramClient()
      : super(
          items: const <MediaItem>[
            MediaItem(
              id: '-1001:40:10',
              chatId: -1001,
              messageId: 40,
              fileId: 10,
              title: 'Refresh Artwork Track',
              fileName: 'refresh-artwork.mp3',
              mimeType: 'audio/mpeg',
              size: 200,
              kind: MediaKind.audio,
            ),
          ],
        );

  @override
  Future<MediaItem> refreshMedia(MediaItem item) async {
    refreshAttempts += 1;
    return MediaItem(
      id: item.id,
      chatId: item.chatId,
      messageId: item.messageId,
      fileId: item.fileId,
      title: item.title,
      fileName: item.fileName,
      mimeType: item.mimeType,
      size: item.size,
      kind: item.kind,
      dateEpochSeconds: item.dateEpochSeconds,
      artist: item.artist,
      durationSeconds: item.durationSeconds,
      thumbnailFileId: 77,
      inlineThumbnailBase64: item.inlineThumbnailBase64,
      localPath: item.localPath,
      parts: item.parts,
    );
  }

  @override
  Future<Uint8List?> loadThumbnail(MediaItem item) async {
    thumbnailAttempts += 1;
    expect(item.thumbnailFileId, 77);
    return Uint8List.fromList(<int>[9, 8, 7, 6]);
  }
}

class _ThumbnailFailureTelegramClient implements TelegramClient {
  _ThumbnailFailureTelegramClient({List<MediaItem>? items})
      : items = items ?? <MediaItem>[defaultItem];

  static const defaultItem = MediaItem(
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

  final List<MediaItem> items;
  int thumbnailAttempts = 0;
  int refreshAttempts = 0;

  @override
  Stream<AuthStep> get authSteps => const Stream<AuthStep>.empty();

  @override
  Stream<AppException> get errors => const Stream<AppException>.empty();

  @override
  Future<List<MediaItem>> listAllMedia({
    required List<int> channelIds,
    required void Function(MediaScanProgress progress) onProgress,
  }) async {
    onProgress(
      MediaScanProgress(
        scannedMessages: items.length,
        mediaCount: items.length,
      ),
    );
    return items;
  }

  @override
  Future<Uint8List?> loadThumbnail(MediaItem item) {
    thumbnailAttempts += 1;
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
      items;

  @override
  Future<MediaItem> refreshMedia(MediaItem item) async {
    refreshAttempts += 1;
    return item;
  }

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
