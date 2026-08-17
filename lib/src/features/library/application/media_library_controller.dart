import 'package:flutter/foundation.dart';

import '../../../core/errors/app_exception.dart';
import '../../../core/utils/embedded_artwork.dart';
import '../../settings/application/settings_controller.dart';
import '../data/media_repository.dart';
import '../models/channel_cache_progress.dart';
import '../models/media_item.dart';

class MediaLibraryController extends ChangeNotifier {
  MediaLibraryController({
    required MediaRepository repository,
    required SettingsController settingsController,
  })  : _repository = repository,
        _settingsController = settingsController;

  final MediaRepository _repository;
  final SettingsController _settingsController;

  bool _isLoading = false;
  bool _isCaching = false;
  Object? _error;
  ChannelCacheProgress? _cacheProgress;
  List<MediaItem> _items = const <MediaItem>[];
  final Map<String, Future<Uint8List?>> _thumbnailRequests =
      <String, Future<Uint8List?>>{};
  final Map<String, Uint8List> _resolvedThumbnails = <String, Uint8List>{};
  final Map<String, Future<AudioTechnicalMetadata?>> _technicalMetadataRequests =
      <String, Future<AudioTechnicalMetadata?>>{};

  bool get isLoading => _isLoading;
  bool get isCaching => _isCaching;
  Object? get error => _error;
  ChannelCacheProgress? get cacheProgress => _cacheProgress;
  List<MediaItem> get items => _items;

  Future<void> load() async {
    _isLoading = true;
    _error = null;
    notifyListeners();
    try {
      final settings = _settingsController.settings;
      if (settings.channelIds.isEmpty) {
        _items = const <MediaItem>[];
      } else {
        _items = await _repository.loadRecent(settings);
        final activeMessageKeys = _items.map((item) => item.messageKey).toSet();
        final activeIds = _items.map((item) => item.id).toSet();
        _thumbnailRequests.removeWhere(
          (key, _) => !activeMessageKeys.contains(key.split('|').first),
        );
        _resolvedThumbnails.removeWhere(
          (key, _) => !activeMessageKeys.contains(key.split('|').first),
        );
        _technicalMetadataRequests.removeWhere(
          (id, _) => !activeIds.contains(id),
        );
      }
    } catch (error) {
      _error = error is AppException
          ? error
          : AppException(AppErrorCode.telegramApi, cause: error);
    } finally {
      _isLoading = false;
      notifyListeners();
    }
  }

  Future<bool> cacheAllChannels() async {
    if (_isCaching) {
      return false;
    }
    final settings = _settingsController.settings;
    if (settings.channelIds.isEmpty) {
      _error = const AppException(
        AppErrorCode.privateChannel,
        message: 'Add at least one Telegram channel in Settings before caching.',
      );
      notifyListeners();
      return false;
    }

    _isCaching = true;
    _error = null;
    _cacheProgress = const ChannelCacheProgress(
      phase: ChannelCachePhase.scanning,
      mediaCount: 0,
    );
    notifyListeners();
    try {
      final items = await _repository.cacheAll(
        settings,
        onItemsAvailable: (availableItems) {
          _items = availableItems;
          _thumbnailRequests.clear();
          _resolvedThumbnails.clear();
          _technicalMetadataRequests.clear();
          notifyListeners();
        },
        onProgress: (progress) {
          _cacheProgress = progress;
          notifyListeners();
        },
      );
      _items = items;
      _thumbnailRequests.clear();
      _resolvedThumbnails.clear();
      _technicalMetadataRequests.clear();
      return true;
    } catch (error) {
      _error = error is AppException
          ? error
          : AppException(AppErrorCode.cacheUnavailable, cause: error);
      return false;
    } finally {
      _isCaching = false;
      notifyListeners();
    }
  }

  Future<Uri?> prepareDirectPlaybackUri(MediaItem item) =>
      _repository.prepareDirectPlaybackUri(item);

  Future<Uri> streamUriFor(MediaItem item) => _repository.streamUriFor(item);

  Future<void> clearPlaybackCache(MediaItem item) =>
      _repository.clearPlaybackCache(item);

  Future<void> clearAllCachedData() async {
    if (_isCaching) {
      throw const AppException(
        AppErrorCode.cacheUnavailable,
        message: 'Wait for the current library cache operation to finish first.',
      );
    }
    await _repository.clearAllCachedData(_items);
    _thumbnailRequests.clear();
    _resolvedThumbnails.clear();
    _technicalMetadataRequests.clear();
    _cacheProgress = null;
  }

  Future<AudioTechnicalMetadata?> technicalMetadataFor(MediaItem item) {
    return _technicalMetadataRequests.putIfAbsent(
      item.id,
      () => _repository.loadTechnicalMetadata(item),
    );
  }

  Uint8List? cachedThumbnailFor(
    MediaItem item, {
    bool highQuality = false,
  }) {
    final quality = highQuality ? 'hq' : 'thumb';
    final exact = _resolvedThumbnails['${item.messageKey}|$quality'];
    if (exact != null && exact.isNotEmpty) {
      return exact;
    }
    if (highQuality) {
      final preview = _resolvedThumbnails['${item.messageKey}|thumb'];
      if (preview != null && preview.isNotEmpty) {
        return preview;
      }
    }
    return null;
  }

  Future<Uint8List?> thumbnailFor(
    MediaItem item, {
    bool highQuality = false,
  }) {
    // Telegram chat/message identity is stable across TDLib restarts, while a
    // TDLib fileId is not. Key artwork requests by message so a refreshed item
    // does not strand a completed/null Future under an obsolete file ID.
    final requestKey =
        '${item.messageKey}|${highQuality ? 'hq' : 'thumb'}';
    final existing = _thumbnailRequests[requestKey];
    if (existing != null) {
      return existing;
    }

    late final Future<Uint8List?> request;
    request = _loadThumbnailWithRetry(item, highQuality: highQuality).then(
      (bytes) {
        // Never cache a missing cover forever. A thumbnail download can race a
        // playback-cache cleanup or briefly fail during a song switch; letting
        // the next widget request retry fixes covers that previously stayed as
        // the music-note placeholder until the app restarted.
        if (bytes != null && bytes.isNotEmpty) {
          _resolvedThumbnails[requestKey] = bytes;
        } else if (identical(_thumbnailRequests[requestKey], request)) {
          _thumbnailRequests.remove(requestKey);
          _resolvedThumbnails.remove(requestKey);
        }
        return bytes;
      },
      onError: (Object error, StackTrace stackTrace) {
        if (identical(_thumbnailRequests[requestKey], request)) {
          _thumbnailRequests.remove(requestKey);
          _resolvedThumbnails.remove(requestKey);
        }
        Error.throwWithStackTrace(error, stackTrace);
      },
    );
    _thumbnailRequests[requestKey] = request;
    return request;
  }

  Future<Uint8List?> _loadThumbnailWithRetry(
    MediaItem item, {
    required bool highQuality,
  }) async {
    final first = await _repository.loadThumbnail(
      item,
      preferHighResolution: highQuality,
    );
    if (first != null && first.isNotEmpty) {
      return first;
    }
    // One forced refresh is enough to recover from stale Telegram thumbnail
    // metadata without creating an endless retry loop for songs with no cover.
    return _repository.loadThumbnail(
      item,
      retryRemote: true,
      preferHighResolution: highQuality,
    );
  }
}
