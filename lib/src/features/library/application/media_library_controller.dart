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
        final activeIds = _items.map((item) => item.id).toSet();
        _thumbnailRequests.removeWhere(
          (key, _) => !activeIds.contains(key.split('|').first),
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

  Future<Uri> streamUriFor(MediaItem item) => _repository.streamUriFor(item);

  Future<AudioTechnicalMetadata?> technicalMetadataFor(MediaItem item) {
    return _technicalMetadataRequests.putIfAbsent(
      item.id,
      () => _repository.loadTechnicalMetadata(item),
    );
  }

  Future<Uint8List?> thumbnailFor(
    MediaItem item, {
    bool highQuality = false,
  }) {
    // Keep list-tile and full-player requests separate. A tiny Telegram cover
    // may be fine in the library while the player needs embedded original art.
    final requestKey = '${item.id}|${highQuality ? 'hq' : 'thumb'}';
    return _thumbnailRequests.putIfAbsent(
      requestKey,
      () => _repository.loadThumbnail(
        item,
        preferHighResolution: highQuality,
      ),
    );
  }
}
