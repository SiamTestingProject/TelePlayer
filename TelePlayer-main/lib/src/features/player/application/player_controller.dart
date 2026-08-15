import 'package:flutter/foundation.dart';
import 'package:video_player/video_player.dart';

import '../../../core/errors/app_exception.dart';
import '../../library/application/media_library_controller.dart';
import '../../library/models/media_item.dart';

class PlayerController extends ChangeNotifier {
  PlayerController(this._libraryController);

  final MediaLibraryController _libraryController;

  VideoPlayerController? _videoController;
  MediaItem? _item;
  Object? _error;
  bool _isLoading = false;

  VideoPlayerController? get videoController => _videoController;
  MediaItem? get item => _item;
  Object? get error => _error;
  bool get isLoading => _isLoading;

  Future<void> open(MediaItem item) async {
    _isLoading = true;
    _error = null;
    _item = item;
    notifyListeners();
    try {
      await _videoController?.dispose();
      final uri = await _libraryController.streamUriFor(item);
      final controller = VideoPlayerController.networkUrl(uri);
      _videoController = controller;
      await controller.initialize();
      await controller.play();
    } catch (error) {
      _error = error is AppException
          ? error
          : AppException(AppErrorCode.playbackFailure, cause: error);
    } finally {
      _isLoading = false;
      notifyListeners();
    }
  }

  Future<void> togglePlay() async {
    final controller = _videoController;
    if (controller == null) {
      return;
    }
    if (controller.value.isPlaying) {
      await controller.pause();
    } else {
      await controller.play();
    }
    notifyListeners();
  }

  @override
  void dispose() {
    _videoController?.dispose();
    super.dispose();
  }
}
