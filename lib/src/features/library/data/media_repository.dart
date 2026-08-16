import 'dart:typed_data';

import '../../../core/errors/app_exception.dart';
import '../../../core/services/local_streaming_server.dart';
import '../../../infrastructure/telegram/telegram_client.dart';
import '../../settings/models/app_settings.dart';
import '../models/channel_cache_progress.dart';
import '../models/media_item.dart';
import 'channel_catalog_cache.dart';

class MediaRepository {
  MediaRepository({
    required TelegramClient telegramClient,
    required LocalStreamingServer streamingServer,
    ChannelCatalogCache? catalogCache,
  })  : _telegramClient = telegramClient,
        _streamingServer = streamingServer,
        _catalogCache = catalogCache ?? ChannelCatalogCache();

  final TelegramClient _telegramClient;
  final LocalStreamingServer _streamingServer;
  final ChannelCatalogCache _catalogCache;

  Future<List<MediaItem>> loadRecent(AppSettings settings) async {
    final configuredChannels = settings.channelIds.toSet();
    final cached = (await _catalogCache.readItems())
        .where((item) => configuredChannels.contains(item.chatId))
        .toList(growable: false);
    late final List<MediaItem> recent;
    try {
      recent = await _telegramClient.listRecentMedia(
        channelIds: settings.channelIds,
        limitPerChannel: 60,
      );
    } catch (_) {
      if (cached.isNotEmpty) {
        return cached;
      }
      rethrow;
    }
    final merged = _mergeById(recent, cached);
    try {
      await _catalogCache.writeItems(merged);
    } catch (_) {
      // A catalog write failure must not hide an otherwise usable library.
    }
    return merged;
  }

  Future<List<MediaItem>> cacheAll(
    AppSettings settings, {
    required void Function(ChannelCacheProgress progress) onProgress,
    void Function(List<MediaItem> items)? onItemsAvailable,
  }) async {
    final items = await _telegramClient.listAllMedia(
      channelIds: settings.channelIds,
      onProgress: (progress) {
        onProgress(
          ChannelCacheProgress(
            phase: ChannelCachePhase.scanning,
            scannedMessages: progress.scannedMessages,
            mediaCount: progress.mediaCount,
          ),
        );
      },
    );
    await _catalogCache.writeItems(items);
    onItemsAvailable?.call(List<MediaItem>.unmodifiable(items));

    final thumbnailItems = <int, MediaItem>{};
    for (final item in items) {
      final thumbnailId = item.thumbnailFileId;
      if (thumbnailId != null) {
        thumbnailItems.putIfAbsent(thumbnailId, () => item);
      }
    }
    var completed = 0;
    var failed = 0;
    onProgress(
      ChannelCacheProgress(
        phase: ChannelCachePhase.thumbnails,
        mediaCount: items.length,
        completedThumbnails: completed,
        totalThumbnails: thumbnailItems.length,
      ),
    );
    for (final entry in thumbnailItems.entries) {
      try {
        final thumbnail = await loadThumbnail(entry.value);
        if (thumbnail == null || thumbnail.isEmpty) {
          failed += 1;
        } else {
          completed += 1;
        }
      } on AppException catch (error) {
        if (!_isRecoverableThumbnailFailure(error)) {
          rethrow;
        }
        failed += 1;
      }
      onProgress(
        ChannelCacheProgress(
          phase: ChannelCachePhase.thumbnails,
          mediaCount: items.length,
          completedThumbnails: completed,
          totalThumbnails: thumbnailItems.length,
          failedThumbnails: failed,
        ),
      );
    }
    onProgress(
      ChannelCacheProgress(
        phase: ChannelCachePhase.complete,
        mediaCount: items.length,
        completedThumbnails: completed,
        totalThumbnails: thumbnailItems.length,
        failedThumbnails: failed,
      ),
    );
    return items;
  }

  bool _isRecoverableThumbnailFailure(AppException error) {
    return switch (error.code) {
      AppErrorCode.missingThumbnail ||
      AppErrorCode.deletedMedia ||
      AppErrorCode.cacheUnavailable ||
      AppErrorCode.telegramApi => true,
      _ => false,
    };
  }

  Future<Uri> streamUriFor(MediaItem item) {
    return _refreshAndRegister(item);
  }

  Future<Uri> _refreshAndRegister(MediaItem item) async {
    final refreshed = await _telegramClient.refreshMedia(item);
    return _streamingServer.register(refreshed);
  }

  Future<Uint8List?> loadThumbnail(MediaItem item) async {
    final thumbnailId = item.thumbnailFileId;
    if (thumbnailId == null) {
      return null;
    }
    final cached = await _catalogCache.readThumbnail(thumbnailId);
    if (cached != null) {
      return cached;
    }
    final downloaded = await _telegramClient.loadThumbnail(item);
    if (downloaded != null && downloaded.isNotEmpty) {
      await _catalogCache.writeThumbnail(thumbnailId, downloaded);
    }
    return downloaded;
  }

  List<MediaItem> _mergeById(
    List<MediaItem> preferred,
    List<MediaItem> fallback,
  ) {
    final byId = <String, MediaItem>{};
    for (final item in fallback) {
      byId[item.id] = item;
    }
    for (final item in preferred) {
      byId[item.id] = item;
    }
    final items = byId.values.toList()
      ..sort((left, right) => right.messageId.compareTo(left.messageId));
    return items;
  }
}
