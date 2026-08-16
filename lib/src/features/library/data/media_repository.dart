import 'dart:convert';
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
    Duration thumbnailRetryBaseDelay = const Duration(milliseconds: 250),
  })  : _telegramClient = telegramClient,
        _streamingServer = streamingServer,
        _catalogCache = catalogCache ?? ChannelCatalogCache(),
        _thumbnailRetryBaseDelay = thumbnailRetryBaseDelay;

  final TelegramClient _telegramClient;
  final LocalStreamingServer _streamingServer;
  final ChannelCatalogCache _catalogCache;
  final Duration _thumbnailRetryBaseDelay;

  Future<List<MediaItem>> loadRecent(AppSettings settings) async {
    final configuredChannels = settings.channelIds.toSet();
    final cached = (await _catalogCache.readItems())
        .where(
          (item) =>
              configuredChannels.contains(item.chatId) &&
              item.kind == MediaKind.audio,
        )
        .toList(growable: false);
    late final List<MediaItem> recent;
    try {
      recent = (await _telegramClient.listRecentMedia(
        channelIds: settings.channelIds,
        limitPerChannel: 60,
      )).where((item) => item.kind == MediaKind.audio).toList(growable: false);
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
    final scannedItems = await _telegramClient.listAllMedia(
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
    final items = scannedItems
        .where((item) => item.kind == MediaKind.audio)
        .toList(growable: false);
    await _catalogCache.writeItems(items);
    onItemsAvailable?.call(List<MediaItem>.unmodifiable(items));

    var completed = 0;
    var failed = 0;
    var nextIndex = 0;
    onProgress(
      ChannelCacheProgress(
        phase: ChannelCachePhase.thumbnails,
        mediaCount: items.length,
        completedThumbnails: 0,
        totalThumbnails: items.length,
      ),
    );

    // A song can have no thumbnail in a history response but gain an album
    // cover after GetMessage refreshes its TDLib audio object. Cache every
    // song rather than only the items that already advertise a thumbnail.
    Future<void> worker() async {
      while (true) {
        final index = nextIndex;
        nextIndex += 1;
        if (index >= items.length) {
          return;
        }
        try {
          final artwork = await loadThumbnail(
            items[index],
            retryRemote: true,
          );
          if (artwork == null || artwork.isEmpty) {
            failed += 1;
          } else {
            completed += 1;
          }
        } on AppException catch (error) {
          if (!_isRecoverableThumbnailFailure(error)) {
            rethrow;
          }
          failed += 1;
        } catch (_) {
          // One malformed/unavailable artwork file must not abort a full
          // channel cache. The song catalog itself is already safely stored.
          failed += 1;
        }
        onProgress(
          ChannelCacheProgress(
            phase: ChannelCachePhase.thumbnails,
            mediaCount: items.length,
            completedThumbnails: completed,
            totalThumbnails: items.length,
            failedThumbnails: failed,
          ),
        );
      }
    }

    final workerCount =
        items.isEmpty ? 0 : (items.length < 4 ? items.length : 4);
    await Future.wait(
      List<Future<void>>.generate(workerCount, (_) => worker()),
    );

    onProgress(
      ChannelCacheProgress(
        phase: ChannelCachePhase.complete,
        mediaCount: items.length,
        completedThumbnails: completed,
        totalThumbnails: items.length,
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
    if (item.kind != MediaKind.audio) {
      return Future<Uri>.error(
        const AppException(
          AppErrorCode.invalidMedia,
          message: 'TelePlayer supports Telegram audio files only.',
        ),
      );
    }
    return _refreshAndRegister(item);
  }

  Future<Uri> _refreshAndRegister(MediaItem item) async {
    final refreshed = await _telegramClient.refreshMedia(item);
    return _streamingServer.register(refreshed);
  }

  Future<Uint8List?> loadThumbnail(
    MediaItem item, {
    bool retryRemote = false,
  }) async {
    // Item-keyed artwork survives cases where TDLib rotates a thumbnail file
    // ID or where the original history item had no thumbnail ID at all.
    // During a full cache pass, however, do not let an old minithumbnail-sized
    // artwork file permanently win. Refresh the Telegram message and try the
    // best remote album-cover variant again so existing installations can
    // upgrade low-resolution artwork in place.
    final cachedArtwork = await _catalogCache.readArtwork(item);
    if (!retryRemote && cachedArtwork != null) {
      return cachedArtwork;
    }

    var inlineFallback = _decodeInlineThumbnail(item);
    var currentItem = item;
    var refreshedOnce = false;

    Future<void> refreshCurrentItem() async {
      if (refreshedOnce) {
        return;
      }
      try {
        currentItem = await _telegramClient.refreshMedia(item);
        final refreshedInline = _decodeInlineThumbnail(currentItem);
        if (refreshedInline != null && refreshedInline.isNotEmpty) {
          inlineFallback = refreshedInline;
        }
      } on AppException catch (error) {
        if (!_isRecoverableThumbnailFailure(error)) {
          rethrow;
        }
      } finally {
        refreshedOnce = true;
      }
    }

    Future<Uint8List?> tryRemoteArtwork() async {
      final thumbnailId = currentItem.thumbnailFileId;
      if (thumbnailId == null) {
        return null;
      }

      final cachedThumbnail = await _catalogCache.readThumbnail(thumbnailId);
      if (!retryRemote && cachedThumbnail != null) {
        await _catalogCache.writeArtwork(item, cachedThumbnail);
        return cachedThumbnail;
      }

      try {
        final downloaded = await _telegramClient.loadThumbnail(currentItem);
        if (downloaded == null || downloaded.isEmpty) {
          if (cachedThumbnail != null && cachedThumbnail.isNotEmpty) {
            await _catalogCache.writeArtwork(item, cachedThumbnail);
            return cachedThumbnail;
          }
          return null;
        }
        await _catalogCache.writeThumbnail(thumbnailId, downloaded);
        await _catalogCache.writeArtwork(item, downloaded);
        return downloaded;
      } on AppException catch (error) {
        if (!_isRecoverableThumbnailFailure(error)) {
          rethrow;
        }
        if (cachedThumbnail != null && cachedThumbnail.isNotEmpty) {
          await _catalogCache.writeArtwork(item, cachedThumbnail);
          return cachedThumbnail;
        }
        return null;
      }
    }

    // The history response can contain only a tiny inline preview. A direct
    // GetMessage refresh often exposes album_cover_thumbnail or a larger
    // external_album_covers entry. Force that refresh when the user runs the
    // full cache operation, even if an older item-keyed artwork file exists.
    if (retryRemote) {
      await refreshCurrentItem();
    }

    for (var attempt = 0; attempt < 3; attempt++) {
      final remote = await tryRemoteArtwork();
      if (remote != null && remote.isNotEmpty) {
        return remote;
      }

      if (!refreshedOnce) {
        await refreshCurrentItem();
        final refreshedRemote = await tryRemoteArtwork();
        if (refreshedRemote != null && refreshedRemote.isNotEmpty) {
          return refreshedRemote;
        }
      }

      if (attempt < 2 && _thumbnailRetryBaseDelay > Duration.zero) {
        await Future<void>.delayed(
          Duration(
            milliseconds:
                _thumbnailRetryBaseDelay.inMilliseconds * (1 << attempt),
          ),
        );
      }
    }

    // Preserve a previously cached full image when Telegram is temporarily
    // unavailable. Inline minithumbnails are intentionally not persisted as
    // item artwork because doing so made a 40px preview look like the final
    // album cover on later launches.
    if (cachedArtwork != null && cachedArtwork.isNotEmpty) {
      return cachedArtwork;
    }
    return inlineFallback;
  }

  Uint8List? _decodeInlineThumbnail(MediaItem item) {
    final encoded = item.inlineThumbnailBase64?.trim() ?? '';
    if (encoded.isEmpty) {
      return null;
    }
    try {
      final bytes = base64Decode(encoded);
      return bytes.isEmpty ? null : bytes;
    } on FormatException {
      return null;
    }
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
