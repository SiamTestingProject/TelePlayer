import 'dart:async';
import 'dart:math';

import 'package:flutter/foundation.dart';
import 'package:video_player/video_player.dart';

import '../../../core/errors/app_exception.dart';
import '../../library/application/media_library_controller.dart';
import '../../library/models/media_item.dart';

class PlayerController extends ChangeNotifier {
  PlayerController(this._libraryController);

  final MediaLibraryController _libraryController;
  final Set<String> _favoriteIds = <String>{};
  final Random _random = Random();

  VideoPlayerController? _videoController;
  MediaItem? _item;
  Object? _error;
  bool _isLoading = false;
  bool _shuffleEnabled = false;
  bool _repeatEnabled = false;
  bool _isAdvancing = false;

  VideoPlayerController? get videoController => _videoController;
  MediaItem? get item => _item;
  Object? get error => _error;
  bool get isLoading => _isLoading;
  bool get shuffleEnabled => _shuffleEnabled;
  bool get repeatEnabled => _repeatEnabled;
  bool get isFavorite => _item != null && _favoriteIds.contains(_item!.id);

  Future<void> open(MediaItem item) async {
    _isLoading = true;
    _error = null;
    _item = item;
    notifyListeners();

    VideoPlayerController? nextController;
    try {
      final previousController = _videoController;
      _videoController = null;
      previousController?.removeListener(_handlePlaybackUpdate);
      await previousController?.dispose();

      final uri = await _libraryController.streamUriFor(item);
      nextController = VideoPlayerController.networkUrl(
        uri,
        videoPlayerOptions: VideoPlayerOptions(mixWithOthers: true),
      );
      await nextController.initialize().timeout(const Duration(seconds: 60));
      await nextController.setLooping(_repeatEnabled);
      nextController.addListener(_handlePlaybackUpdate);
      _videoController = nextController;
      await nextController.play();
    } on TimeoutException catch (error) {
      await nextController?.dispose();
      _videoController = null;
      _error = AppException(
        AppErrorCode.networkInterrupted,
        message: 'Telegram took too long to prepare this track. Try again.',
        cause: error,
      );
    } catch (error) {
      await nextController?.dispose();
      _videoController = null;
      _error = error is AppException
          ? error
          : AppException(
              AppErrorCode.playbackFailure,
              message: 'TelePlayer could not open this Telegram media stream.',
              cause: error,
            );
    } finally {
      _isLoading = false;
      notifyListeners();
    }
  }

  Future<void> togglePlay() async {
    final controller = _videoController;
    if (controller == null) {
      final currentItem = _item;
      if (currentItem != null) {
        await open(currentItem);
      }
      return;
    }
    if (controller.value.isPlaying) {
      await controller.pause();
    } else {
      await controller.play();
    }
    notifyListeners();
  }

  Future<void> playNext() async {
    final next = _adjacentItem(1);
    if (next != null) {
      await open(next);
    }
  }

  Future<void> playPrevious() async {
    final controller = _videoController;
    if (controller != null && controller.value.position.inSeconds > 5) {
      await controller.seekTo(Duration.zero);
      return;
    }
    final previous = _adjacentItem(-1);
    if (previous != null) {
      await open(previous);
    }
  }

  Future<void> seekToFraction(double fraction) async {
    final controller = _videoController;
    if (controller == null || !controller.value.isInitialized) {
      return;
    }
    final duration = controller.value.duration;
    final target = Duration(
      milliseconds: (duration.inMilliseconds * fraction.clamp(0, 1)).round(),
    );
    await controller.seekTo(target);
  }

  void toggleShuffle() {
    _shuffleEnabled = !_shuffleEnabled;
    notifyListeners();
  }

  Future<void> toggleRepeat() async {
    _repeatEnabled = !_repeatEnabled;
    await _videoController?.setLooping(_repeatEnabled);
    notifyListeners();
  }

  void toggleFavorite() {
    final currentItem = _item;
    if (currentItem == null) {
      return;
    }
    if (!_favoriteIds.add(currentItem.id)) {
      _favoriteIds.remove(currentItem.id);
    }
    notifyListeners();
  }

  MediaItem? _adjacentItem(int direction) {
    final queue = _libraryController.items;
    final currentItem = _item;
    if (queue.isEmpty) {
      return null;
    }
    if (_shuffleEnabled && queue.length > 1) {
      MediaItem candidate;
      do {
        candidate = queue[_random.nextInt(queue.length)];
      } while (candidate.id == currentItem?.id);
      return candidate;
    }
    final currentIndex = currentItem == null
        ? -1
        : queue.indexWhere((candidate) => candidate.id == currentItem.id);
    final start = currentIndex < 0 ? 0 : currentIndex;
    final nextIndex = (start + direction) % queue.length;
    return queue[nextIndex < 0 ? nextIndex + queue.length : nextIndex];
  }

  void _handlePlaybackUpdate() {
    final controller = _videoController;
    if (controller == null) {
      return;
    }
    final value = controller.value;
    if (value.hasError && _error == null) {
      _error = AppException(
        AppErrorCode.playbackFailure,
        message: 'Playback stopped because the Telegram stream was interrupted.',
        cause: value.errorDescription,
      );
      notifyListeners();
      return;
    }
    final duration = value.duration;
    final reachedEnd = duration > Duration.zero &&
        value.position >= duration &&
        !value.isPlaying;
    if (reachedEnd && !_repeatEnabled && !_isAdvancing) {
      _isAdvancing = true;
      unawaited(
        playNext().whenComplete(() {
          _isAdvancing = false;
        }),
      );
    }
  }

  @override
  void dispose() {
    _videoController?.removeListener(_handlePlaybackUpdate);
    unawaited(_videoController?.dispose());
    super.dispose();
  }
}
