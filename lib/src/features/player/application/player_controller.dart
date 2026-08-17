import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:math';

import 'package:flutter/foundation.dart';
import 'package:just_audio/just_audio.dart' as audio;
import 'package:just_audio_background/just_audio_background.dart' as background;
import 'package:path_provider/path_provider.dart';

import '../../../core/errors/app_exception.dart';
import '../../library/application/media_library_controller.dart';
import '../../library/models/media_item.dart';

class PlayerController extends ChangeNotifier {
  PlayerController(this._libraryController);

  static const int _maxRecoveryAttempts = 6;
  static const Duration _bufferingWatchdogDelay = Duration(seconds: 18);

  final MediaLibraryController _libraryController;
  final Set<String> _favoriteKeys = <String>{};
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
  Timer? _bufferingWatchdog;

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
  bool get isFavorite => _item != null && isFavoriteItem(_item!);

  bool isFavoriteItem(MediaItem item) => _favoriteKeys.contains(item.messageKey);

  Future<void> initializeLibraryPreferences() async {
    try {
      final file = await _favoritesFile();
      if (!await file.exists()) {
        return;
      }
      final decoded = jsonDecode(await file.readAsString());
      if (decoded is! List) {
        return;
      }
      _favoriteKeys
        ..clear()
        ..addAll(
          decoded
              .map((value) => value.toString().trim())
              .where((value) => value.isNotEmpty),
        );
      _notify();
    } catch (_) {
      // Favorites are optional UI state; a damaged preference file must not
      // prevent playback from starting.
    }
  }

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
    _cancelBufferingWatchdog();
    return _open(item);
  }

  Future<void> _open(
    MediaItem item, {
    Duration resumeAt = Duration.zero,
  }) async {
    final generation = ++_openGeneration;
    final previousItem = _item;
    _cancelBufferingWatchdog();
    _isOpening = true;
    _error = null;
    _item = item;
    _notify();

    final player = _ensurePlayer();
    try {
      await player.stop();
      if (previousItem != null &&
          previousItem.messageKey != item.messageKey) {
        unawaited(_clearPlaybackCache(previousItem));
      }
      final uri = await _libraryController.streamUriFor(item);
      if (generation != _openGeneration || _disposed) {
        return;
      }
      final source = audio.AudioSource.uri(
        uri,
        tag: background.MediaItem(
          id: item.id,
          album: item.album ?? 'Telegram Mix',
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
        _recoverPlayback(error);
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
    toggleFavoriteFor(currentItem);
  }

  void toggleFavoriteFor(MediaItem item) {
    final key = item.messageKey;
    if (!_favoriteKeys.add(key)) {
      _favoriteKeys.remove(key);
    }
    _notify();
    unawaited(_saveFavorites());
  }

  Future<File> _favoritesFile() async {
    final support = await getApplicationSupportDirectory();
    final directory = Directory(
      '${support.path}${Platform.pathSeparator}teleplayer-preferences',
    );
    if (!await directory.exists()) {
      await directory.create(recursive: true);
    }
    return File(
      '${directory.path}${Platform.pathSeparator}favorites.json',
    );
  }

  Future<void> _saveFavorites() async {
    try {
      final file = await _favoritesFile();
      final sorted = _favoriteKeys.toList(growable: false)..sort();
      await file.writeAsString(jsonEncode(sorted), flush: true);
    } catch (_) {
      // Keep the in-memory favorite state even if local persistence fails.
    }
  }

  audio.AudioPlayer _ensurePlayer() {
    final existing = _audioPlayer;
    if (existing != null) {
      return existing;
    }
    final player = audio.AudioPlayer(
      useLazyPreparation: false,
      audioLoadConfiguration: const audio.AudioLoadConfiguration(
        androidLoadControl: audio.AndroidLoadControl(
          minBufferDuration: Duration(seconds: 60),
          maxBufferDuration: Duration(minutes: 2),
          bufferForPlaybackDuration: Duration(seconds: 2),
          bufferForPlaybackAfterRebufferDuration: Duration(seconds: 8),
          prioritizeTimeOverSizeThresholds: true,
          backBufferDuration: Duration(seconds: 20),
        ),
      ),
    );
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
    final stalled = state.playing &&
        (state.processingState == audio.ProcessingState.loading ||
            state.processingState == audio.ProcessingState.buffering);
    if (stalled) {
      _armBufferingWatchdog();
    } else {
      _cancelBufferingWatchdog();
    }

    if (state.processingState == audio.ProcessingState.completed &&
        !_repeatEnabled &&
        !_isAdvancing) {
      _isAdvancing = true;
      final completedItem = _item;
      unawaited(
        _advanceAfterCompletion(completedItem).whenComplete(() {
          _isAdvancing = false;
        }),
      );
    }
  }

  Future<void> _advanceAfterCompletion(MediaItem? completedItem) async {
    if (completedItem == null) {
      return;
    }
    final next = _adjacentItem(1);
    if (next == null || next.messageKey == completedItem.messageKey) {
      await _audioPlayer?.stop();
      await _clearPlaybackCache(completedItem);
      _notify();
      return;
    }
    await open(next);
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
    _recoverPlayback(error);
  }

  void _armBufferingWatchdog() {
    if (_bufferingWatchdog != null || _disposed || _isRecovering) {
      return;
    }
    final generation = _openGeneration;
    _bufferingWatchdog = Timer(_bufferingWatchdogDelay, () {
      _bufferingWatchdog = null;
      final player = _audioPlayer;
      if (_disposed ||
          _isRecovering ||
          generation != _openGeneration ||
          player == null ||
          !player.playing) {
        return;
      }
      final stillStalled =
          player.processingState == audio.ProcessingState.loading ||
              player.processingState == audio.ProcessingState.buffering;
      if (!stillStalled) {
        return;
      }
      _recoverPlayback(
        const AppException(
          AppErrorCode.networkInterrupted,
          message: 'Telegram playback remained buffered for too long.',
        ),
      );
    });
  }

  void _cancelBufferingWatchdog() {
    _bufferingWatchdog?.cancel();
    _bufferingWatchdog = null;
  }

  void _recoverPlayback(Object error) {
    if (_disposed || _isRecovering) {
      return;
    }
    _cancelBufferingWatchdog();
    final currentItem = _item;
    if (currentItem == null || _recoveryAttempts >= _maxRecoveryAttempts) {
      _setPlaybackError(error);
      return;
    }

    final resumeAt = position;
    final exponent = _recoveryAttempts.clamp(0, 4).toInt();
    final delay = Duration(milliseconds: 500 * (1 << exponent));
    final expectedItemId = currentItem.id;
    _recoveryAttempts += 1;
    _isRecovering = true;
    _isOpening = true;
    _notify();
    Object? recoveryFailure;
    unawaited(
      Future<void>.delayed(delay)
          .then((_) async {
            if (_disposed || _item?.id != expectedItemId) {
              return;
            }
            await _open(currentItem, resumeAt: resumeAt);
            if (!_disposed && _item?.id == expectedItemId) {
              recoveryFailure = _error;
            }
          })
          .whenComplete(() {
            _isRecovering = false;
            if (!_disposed &&
                _item?.id == expectedItemId &&
                recoveryFailure != null) {
              _recoverPlayback(recoveryFailure!);
              return;
            }
            final player = _audioPlayer;
            if (!_disposed &&
                player != null &&
                player.playing &&
                (player.processingState == audio.ProcessingState.loading ||
                    player.processingState == audio.ProcessingState.buffering)) {
              _armBufferingWatchdog();
            }
          }),
    );
  }

  Future<void> _clearPlaybackCache(MediaItem item) async {
    try {
      await _libraryController.clearPlaybackCache(item);
    } catch (_) {
      // Song audio storage is disposable. Cleanup failures should never block
      // playback or surface as a player error.
    }
  }

  void _setPlaybackError(Object error) {
    _cancelBufferingWatchdog();
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
    _cancelBufferingWatchdog();
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
