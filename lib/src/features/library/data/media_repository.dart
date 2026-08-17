import 'dart:convert';
import 'dart:typed_data';

import '../../../core/errors/app_exception.dart';
import '../../../core/services/local_streaming_server.dart';
import '../../../core/utils/embedded_artwork.dart';
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
    final channelIds = configuredChannels.toList(growable: false);
    final fullyScannedChannels = await _catalogCache.readFullyScannedChannels();
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
        channelIds: channelIds,
        limitPerChannel: 60,
      )).where((item) => item.kind == MediaKind.audio).toList(growable: false);
    } catch (_) {
      if (cached.isNotEmpty) {
        return cached;
      }
      rethrow;
    }
    final merged = _mergeByMessage(recent, cached);
    try {
      await _catalogCache.writeItems(
        merged,
        fullyScannedChannels: fullyScannedChannels.intersection(configuredChannels),
      );
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
    final configuredChannels = settings.channelIds.toSet();
    final channelIds = configuredChannels.toList(growable: false);
    final cachedItems = (await _catalogCache.readItems())
        .where(
          (item) =>
              configuredChannels.contains(item.chatId) &&
              item.kind == MediaKind.audio,
        )
        .toList(growable: false);
    final fullyScannedChannels =
        await _catalogCache.readFullyScannedChannels();

    final newestCachedMessageId = <int, int>{};
    for (final item in cachedItems) {
      final current = newestCachedMessageId[item.chatId] ?? 0;
      if (item.messageId > current) {
        newestCachedMessageId[item.chatId] = item.messageId;
      }
    }

    final incrementalClient = _telegramClient;
    final canIncrementallyScan = incrementalClient is IncrementalMediaScanner;
    final scanAnchors = <int, int>{};
    for (final channelId in channelIds) {
      if (fullyScannedChannels.contains(channelId) && canIncrementallyScan) {
        scanAnchors[channelId] = newestCachedMessageId[channelId] ?? 0;
      } else {
        // 0 means scan to the beginning. This happens on a fresh install, for
        // a newly configured channel, or for a small legacy catalog whose
        // completeness cannot safely be assumed.
        scanAnchors[channelId] = 0;
      }
    }

    late final List<MediaItem> scannedItems;
    if (canIncrementallyScan) {
      scannedItems = await (incrementalClient as IncrementalMediaScanner)
          .listMediaSince(
        channelIds: channelIds,
        afterMessageIdByChannel: scanAnchors,
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
    } else {
      // Fallback for alternate TelegramClient implementations used outside the
      // production TDLib client. It retains the previous full-scan behavior.
      scannedItems = await _telegramClient.listAllMedia(
        channelIds: channelIds,
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
    }

    final scannedAudio = _deduplicateByMessage(
      scannedItems.where((item) => item.kind == MediaKind.audio),
    );
    final cachedKeys = cachedItems.map((item) => item.messageKey).toSet();
    final newItems = scannedAudio
        .where((item) => !cachedKeys.contains(item.messageKey))
        .toList(growable: false);
    final items = _mergeByMessage(scannedAudio, cachedItems);

    await _catalogCache.writeItems(
      items,
      fullyScannedChannels: configuredChannels,
    );
    onItemsAvailable?.call(List<MediaItem>.unmodifiable(items));

    var completed = 0;
    var failed = 0;
    var nextIndex = 0;
    onProgress(
      ChannelCacheProgress(
        phase: ChannelCachePhase.thumbnails,
        mediaCount: items.length,
        completedThumbnails: 0,
        totalThumbnails: newItems.length,
      ),
    );

    // Existing artwork is intentionally left alone. The Cache button is now an
    // incremental sync: only songs that were not already present in the local
    // catalog pay the thumbnail/embedded-artwork download cost.
    Future<void> worker() async {
      while (true) {
        final index = nextIndex;
        nextIndex += 1;
        if (index >= newItems.length) {
          return;
        }
        try {
          final artwork = await loadThumbnail(
            newItems[index],
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
          failed += 1;
        }
        onProgress(
          ChannelCacheProgress(
            phase: ChannelCachePhase.thumbnails,
            mediaCount: items.length,
            completedThumbnails: completed,
            totalThumbnails: newItems.length,
            failedThumbnails: failed,
          ),
        );
      }
    }

    final workerCount = newItems.isEmpty
        ? 0
        : (newItems.length < 4 ? newItems.length : 4);
    await Future.wait(
      List<Future<void>>.generate(workerCount, (_) => worker()),
    );

    onProgress(
      ChannelCacheProgress(
        phase: ChannelCachePhase.complete,
        mediaCount: items.length,
        completedThumbnails: completed,
        totalThumbnails: newItems.length,
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

  Future<AudioTechnicalMetadata?> loadTechnicalMetadata(MediaItem item) async {
    final client = _telegramClient;
    if (client is! AudioTechnicalMetadataProvider) {
      return null;
    }
    try {
      return await (client as AudioTechnicalMetadataProvider)
          .loadTechnicalMetadata(item);
    } on AppException catch (error) {
      if (!_isRecoverableThumbnailFailure(error)) {
        rethrow;
      }
      return null;
    } catch (_) {
      return null;
    }
  }

  Future<Uri?> prepareDirectPlaybackUri(MediaItem item) async {
    final client = _telegramClient;
    if (client is! DirectPlaybackFileProvider || item.kind != MediaKind.audio) {
      return null;
    }
    try {
      return await (client as DirectPlaybackFileProvider)
          .prepareDirectPlaybackUri(item);
    } catch (_) {
      // The localhost stream remains a valid fallback when a full native TDLib
      // file cannot be prepared in time.
      return null;
    }
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

  Future<void> clearPlaybackCache(MediaItem item) async {
    final client = _telegramClient;
    if (client is! PlaybackCacheCleaner) {
      return;
    }
    try {
      await (client as PlaybackCacheCleaner).clearPlaybackCache(item);
    } catch (_) {
      // Playback cache cleanup is best-effort and must never interrupt the UI.
    }
  }

  Future<Uri> _refreshAndRegister(MediaItem item) async {
    final refreshed = await _telegramClient.refreshMedia(item);
    return _streamingServer.register(refreshed);
  }

  Future<Uint8List?> loadThumbnail(
    MediaItem item, {
    bool retryRemote = false,
    bool preferHighResolution = false,
  }) async {
    // Artwork cache revision 3 contains only the best cover TelePlayer could
    // obtain. Older revisions are intentionally ignored so tiny Telegram
    // previews cannot remain stuck on the full-size Now Playing screen.
    final cachedArtwork = await _catalogCache.readArtwork(item);
    if (!retryRemote && cachedArtwork != null) {
      return cachedArtwork;
    }

    var inlineFallback = _decodeInlineThumbnail(item);
    var currentItem = item;
    var refreshedOnce = false;
    var embeddedAttempted = false;
    Uint8List? embeddedArtwork;

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

    Future<Uint8List?> tryEmbeddedArtwork() async {
      if (embeddedAttempted) {
        return embeddedArtwork;
      }
      embeddedAttempted = true;
      final client = _telegramClient;
      if (client is! EmbeddedArtworkProvider) {
        return null;
      }
      try {
        final embedded = await (client as EmbeddedArtworkProvider)
            .loadEmbeddedArtwork(currentItem);
        if (embedded != null && embedded.isNotEmpty) {
          embeddedArtwork = embedded;
        }
      } on AppException catch (error) {
        if (!_isRecoverableThumbnailFailure(error)) {
          rethrow;
        }
      } catch (_) {
        // A malformed metadata block must never make the song unavailable.
      }
      return embeddedArtwork;
    }

    Future<Uint8List?> tryRemoteArtwork() async {
      final thumbnailId = currentItem.thumbnailFileId;
      if (thumbnailId == null) {
        return null;
      }

      final cachedThumbnail = await _catalogCache.readThumbnail(thumbnailId);
      if (!retryRemote && cachedThumbnail != null) {
        return cachedThumbnail;
      }

      try {
        final downloaded = await _telegramClient.loadThumbnail(currentItem);
        if (downloaded == null || downloaded.isEmpty) {
          return cachedThumbnail;
        }
        await _catalogCache.writeThumbnail(thumbnailId, downloaded);
        return downloaded;
      } on AppException catch (error) {
        if (!_isRecoverableThumbnailFailure(error)) {
          rethrow;
        }
        return cachedThumbnail;
      }
    }

    Future<Uint8List> selectBest(Uint8List remote) async {
      // Telegram frequently exposes a 40-320px cover for an audio message.
      // That is adequate for a list tile but visibly pixelates a 400px player
      // cover. When the remote image is below 512px on its shortest side,
      // probe the audio metadata and prefer its embedded original artwork.
      if ((!retryRemote && !preferHighResolution) ||
          EmbeddedArtwork.isHighResolution(remote)) {
        return remote;
      }
      final embedded = await tryEmbeddedArtwork();
      if (embedded != null && EmbeddedArtwork.isBetter(embedded, remote)) {
        return embedded;
      }
      return remote;
    }

    // A direct GetMessage refresh can expose external_album_covers or a larger
    // album_cover_thumbnail that wasn't present in channel history.
    if (retryRemote) {
      await refreshCurrentItem();
    }

    for (var attempt = 0; attempt < 3; attempt++) {
      final remote = await tryRemoteArtwork();
      if (remote != null && remote.isNotEmpty) {
        final selected = await selectBest(remote);
        await _catalogCache.writeArtwork(item, selected);
        return selected;
      }

      if (!refreshedOnce) {
        await refreshCurrentItem();
        final refreshedRemote = await tryRemoteArtwork();
        if (refreshedRemote != null && refreshedRemote.isNotEmpty) {
          final selected = await selectBest(refreshedRemote);
          await _catalogCache.writeArtwork(item, selected);
          return selected;
        }
      }

      if (retryRemote || preferHighResolution) {
        final embedded = await tryEmbeddedArtwork();
        if (embedded != null && embedded.isNotEmpty) {
          await _catalogCache.writeArtwork(item, embedded);
          return embedded;
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

    // Preserve a previously cached full image during temporary Telegram
    // failures. Inline minithumbnails are only an in-memory last resort and
    // are never persisted as the player's final album art.
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

  List<MediaItem> _mergeByMessage(
    List<MediaItem> preferred,
    List<MediaItem> fallback,
  ) {
    // TDLib file IDs can change after the local Telegram database is rebuilt.
    // The Telegram chat/message pair is the stable identity of a song, so
    // merging by MediaItem.id (which also contains fileId) can resurrect a
    // stale cached copy beside the fresh one after an app restart.
    final byMessage = <String, MediaItem>{};
    for (final item in fallback) {
      byMessage[_messageKey(item)] = item;
    }
    for (final item in preferred) {
      byMessage[_messageKey(item)] = item;
    }
    final items = byMessage.values.toList()
      ..sort((left, right) => right.messageId.compareTo(left.messageId));
    return items;
  }

  List<MediaItem> _deduplicateByMessage(Iterable<MediaItem> source) {
    final byMessage = <String, MediaItem>{};
    for (final item in source) {
      byMessage[_messageKey(item)] = item;
    }
    final items = byMessage.values.toList()
      ..sort((left, right) => right.messageId.compareTo(left.messageId));
    return items;
  }

  String _messageKey(MediaItem item) => '${item.chatId}:${item.messageId}';
}
