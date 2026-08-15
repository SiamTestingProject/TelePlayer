import 'package:flutter/foundation.dart';

import '../../../core/errors/app_exception.dart';
import '../../settings/application/settings_controller.dart';
import '../data/media_repository.dart';
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
  Object? _error;
  List<MediaItem> _items = const <MediaItem>[];

  bool get isLoading => _isLoading;
  Object? get error => _error;
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

  Future<Uri> streamUriFor(MediaItem item) => _repository.streamUriFor(item);
}
