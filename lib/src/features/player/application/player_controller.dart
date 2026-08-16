import 'dart:async';
import 'dart:math';

import 'package:flutter/foundation.dart';
import 'package:just_audio/just_audio.dart' as audio;
import 'package:just_audio_background/just_audio_background.dart' as background;

import '../../../core/errors/app_exception.dart';
import '../../library/application/media_library_controller.dart';
import '../../library/models/media_item.dart';

class PlayerController extends ChangeNotifier {
  PlayerController(this._libraryController);

  final MediaLibraryController _libraryController;
  final Set<String> _favoriteIds = <String>{};
  final Random _random = Random();
  final List<StreamSubscription<dynamic>> _playerSubscriptions =
      <StreamSubscription<dynamic>>[];

  audio.AudioPlayer? _audioPlayer;
  MediaItem? _item;
  Object? _error;
  bool _isOpening = false;
  bool _shuffleEnabled = false;
  bool _repeatEnabled = false;
  bool _isAdvancing = false;
  bool _isRecovering = false;
  bool _disposed = false;
  int _recoveryAttempts = 0;
  int _openGeneration = 0;
  Duration _recoveryBaseline = Duration.zero;

  MediaItem? get item => _item;
  Object? get error => _error;
  bool get isLoading => _isOpening;
  bool get isPlaying => _audioPlayer?.playing == true;
  bool get isBuffering {
    final state = _audioPlayer?.processingState;
    return state == audio.ProcessingState.loading ||
        state == audio.ProcessingState.buffering;
  }

  Duration get position => _audioPlayer?.position ?? Duration.zero;
  Duration get duration {
    final loadedDuration = _audioPlayer?.duration;
    if (loadedDuration != null && loadedDuration > Duration.zero) {
      return loadedDuration;
    }
    return Duration(seconds: _item?.durationSeconds ?? 0);
  }

  bool get shuffleEnabled => _shuffleEnabled;
  bool get repeatEnabled => _repeatEnabled;
  bool get isFavorite => _item != null && _favoriteIds.contains(_item!.id);

  Future<void> open(MediaItem item) {
    if (item.kind != MediaKind.audio) {
      _error = const AppException(
        AppErrorCode.invalidMedia,
        message: 'TelePlayer supports Telegram audio files only.',
      );
      _notify();
      return Future<void>.value();
    }
    _recoveryAttempts = 0;
    _recoveryBaseline = Duration.zero;
    return _open(item);
  }

  Future<void> _open(
    MediaItem item, {
    Duration resumeAt = Duration.zero,
  }) async {
    final generation = ++_openGeneration;
    _isOpening = true;
    _error = null;
    _item = item;
    _notify();

    final player = _ensurePlayer();
    try {
      await player.stop();
      final uri = await _libraryController.streamUriFor(item);
      if (generation != _openGeneration || _disposed) {
        return;
      }
      final source = audio.AudioSource.uri(
        uri,
        tag: background.MediaItem(
          id: item.id,
          album: 'Telegram Mix',
          title: item.title,
          artist: item.artist,
          duration: item.durationSeconds == null
              ? null
              : Duration(seconds: item.durationSeconds!),
        ),
      );
      await player
          .setAudioSources(
            <audio.AudioSource>[source],
            initialIndex: 0,
            initialPosition: resumeAt,
            useLazyPreparation: false,
          )
          .timeout(const Duration(seconds: 60));
      if (generation != _openGeneration || _disposed) {
        return;
      }
      await player.setLoopMode(
        _repeatEnabled ? audio.LoopMode.one : audio.LoopMode.off,
      );
      _recoveryBaseline = resumeAt;
      unawaited(_startPlayback(player, generation));
    } on TimeoutException catch (error) {
      if (generation == _openGeneration) {
        _error = AppException(
          AppErrorCode.networkInterrupted,
          message: 'Telegram took too long to prepare this song. Try again.',
          cause: error,
        );
      }
    } on audio.PlayerInterruptedException catch (error) {
      if (generation == _openGeneration) {
        _error = AppException(
          AppErrorCode.playbackFailure,
          message: 'Audio loading was interrupted. Try the song again.',
          cause: error,
        );
      }
    } catch (error) {
      if (generation == _openGeneration) {
        _error = error is AppException
            ? error
            : AppException(
                AppErrorCode.playbackFailure,
                message: 'TelePlayer could not open this Telegram audio stream.',
                cause: error,
              );
      }
    } finally {
      if (generation == _openGeneration) {
        _isOpening = false;
        _notify();
      }
    }
  }

  Future<void> _startPlayback(
    audio.AudioPlayer player,
    int generation,
  ) async {
    try {
      await player.play();
    } on audio.PlayerInterruptedException {
      // Loading another song intentionally interrupts the previous play call.
    } catch (error) {
      if (generation == _openGeneration && !_disposed) {
        _setPlaybackError(error);
      }
    }
  }

  Future<void> togglePlay() async {
    final player = _audioPlayer;
    if (player == null || player.processingState == audio.ProcessingState.idle) {
      final currentItem = _item;
      if (currentItem != null) {
        await open(currentItem);
      }
      return;
    }
    if (player.playing) {
      await player.pause();
    } else {
      if (player.processingState == audio.ProcessingState.completed) {
        await player.seek(Duration.zero);
      }
      unawaited(_startPlayback(player, _openGeneration));
    }
    _notify();
  }

  Future<void> playNext() async {
    final next = _adjacentItem(1);
    if (next != null) {
      await open(next);
    }
  }

  Future<void> playPrevious() async {
    final player = _audioPlayer;
    if (player != null && player.position.inSeconds > 5) {
      await player.seek(Duration.zero);
      return;
    }
    final previous = _adjacentItem(-1);
    if (previous != null) {
      await open(previous);
    }
  }

  Future<void> seekToFraction(double fraction) async {
    final player = _audioPlayer;
    final loadedDuration = duration;
    if (player == null || loadedDuration <= Duration.zero) {
      return;
    }
    final target = Duration(
      milliseconds:
          (loadedDuration.inMilliseconds * fraction.clamp(0, 1)).round(),
    );
    await player.seek(target);
  }

  void toggleShuffle() {
    _shuffleEnabled = !_shuffleEnabled;
    _notify();
  }

  Future<void> toggleRepeat() async {
    _repeatEnabled = !_repeatEnabled;
    await _audioPlayer?.setLoopMode(
      _repeatEnabled ? audio.LoopMode.one : audio.LoopMode.off,
    );
    _notify();
  }

  void toggleFavorite() {
    final currentItem = _item;
    if (currentItem == null) {
      return;
    }
    if (!_favoriteIds.add(currentItem.id)) {
      _favoriteIds.remove(currentItem.id);
    }
    _notify();
  }

  audio.AudioPlayer _ensurePlayer() {
    final existing = _audioPlayer;
    if (existing != null) {
      return existing;
    }
    final player = audio.AudioPlayer();
    _audioPlayer = player;
    _playerSubscriptions
      ..add(player.playerStateStream.listen(_handlePlayerState))
      ..add(player.positionStream.listen(_handlePosition))
      ..add(player.durationStream.listen((_) => _notify()))
      ..add(player.errorStream.listen(_handlePlayerError));
    return player;
  }

  MediaItem? _adjacentItem(int direction) {
    final queue = _libraryController.items
        .where((candidate) => candidate.kind == MediaKind.audio)
        .toList(growable: false);
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

  void _handlePlayerState(audio.PlayerState state) {
    _notify();
    if (state.processingState == audio.ProcessingState.completed &&
        !_repeatEnabled &&
        !_isAdvancing) {
      _isAdvancing = true;
      unawaited(
        playNext().whenComplete(() {
          _isAdvancing = false;
        }),
      );
    }
  }

  void _handlePosition(Duration currentPosition) {
    if (isPlaying &&
        currentPosition - _recoveryBaseline > const Duration(seconds: 15)) {
      _recoveryAttempts = 0;
      _recoveryBaseline = currentPosition;
    }
    _notify();
  }

  void _handlePlayerError(audio.PlayerException error) {
    if (_disposed || _isRecovering) {
      return;
    }
    final currentItem = _item;
    if (currentItem != null && _recoveryAttempts < 3) {
      final resumeAt = position;
      final delay = Duration(milliseconds: 500 * (1 << _recoveryAttempts));
      _recoveryAttempts += 1;
      _isRecovering = true;
      _isOpening = true;
      _notify();
      unawaited(
        Future<void>.delayed(delay)
            .then((_) => _open(currentItem, resumeAt: resumeAt))
            .whenComplete(() {
          _isRecovering = false;
        }),
      );
      return;
    }
    _setPlaybackError(error);
  }

  void _setPlaybackError(Object error) {
    _isOpening = false;
    _error = AppException(
      AppErrorCode.networkInterrupted,
      message:
          'The Telegram audio stream stopped. Check the connection and resume playback.',
      cause: error,
    );
    _notify();
  }

  void _notify() {
    if (!_disposed) {
      notifyListeners();
    }
  }

  @override
  void dispose() {
    _disposed = true;
    _openGeneration += 1;
    for (final subscription in _playerSubscriptions) {
      unawaited(subscription.cancel());
    }
    _playerSubscriptions.clear();
    final player = _audioPlayer;
    _audioPlayer = null;
    unawaited(player?.dispose());
    super.dispose();
  }
}
