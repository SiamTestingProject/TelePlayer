import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:math';

import 'package:flutter/foundation.dart';
import 'package:just_audio/just_audio.dart' as audio;
import 'package:path_provider/path_provider.dart';

import '../../../core/errors/app_exception.dart';
import '../../library/application/media_library_controller.dart';
import '../../library/models/media_item.dart';
import 'system_media_bridge.dart';

class PlayerController extends ChangeNotifier {
  PlayerController(
    this._libraryController, {
    SystemMediaBridge? systemMediaBridge,
  }) : _systemMediaBridge = systemMediaBridge;

  static const int _maxRecoveryAttempts = 6;
  static const Duration _bufferingWatchdogDelay = Duration(seconds: 30);
  static const Duration _bufferingProgressTolerance = Duration(seconds: 1);

  final MediaLibraryController _libraryController;
  final SystemMediaBridge? _systemMediaBridge;
  final Set<String> _favoriteKeys = <String>{};
  final Random _random = Random();
  final List<StreamSubscription<dynamic>> _playerSubscriptions =
      <StreamSubscription<dynamic>>[];
  final Map<String, Future<Uri>> _preparedStreamUris =
      <String, Future<Uri>>{};

  audio.AudioPlayer? _audioPlayer;
  MediaItem? _item;
  MediaItem? _activePlaybackItem;
  Future<void> _playerMutationTail = Future<void>.value();
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

  /// Resolves Telegram metadata and registers the localhost source without
  /// touching the native player. Gesture animations call this early so the
  /// current song can keep playing until the user actually commits the swipe.
  Future<void> prepareForTransition(MediaItem item) async {
    if (_disposed ||
        item.kind != MediaKind.audio ||
        item.messageKey == _item?.messageKey) {
      return;
    }
    try {
      await _preparedStreamUri(item);
    } catch (_) {
      // open() will retry normally if this optional preparation failed.
    }
  }

  Future<void> _open(
    MediaItem item, {
    Duration resumeAt = Duration.zero,
  }) async {
    final generation = ++_openGeneration;
    _cancelBufferingWatchdog();
    _isOpening = true;
    _error = null;
    _item = item;
    _notify();

    final player = _ensurePlayer();
    try {
      // Resolve Telegram media before touching the native player. If the user
      // taps another song while this request is in flight, the generation
      // check below drops the stale request without racing two setAudioSources
      // calls against ExoPlayer/Media3.
      final uri = await _takePreparedStreamUri(item);
      if (generation != _openGeneration || _disposed) {
        return;
      }

      MediaItem? playbackItemToClean;
      await _withPlayerMutation(() async {
        if (generation != _openGeneration || _disposed) {
          return;
        }
        playbackItemToClean = _activePlaybackItem;
        final source = audio.AudioSource.uri(uri);
        final canAppendForContinuousSwitch =
            _activePlaybackItem != null &&
            _activePlaybackItem!.messageKey != item.messageKey &&
            player.sequence.isNotEmpty;
        if (canAppendForContinuousSwitch) {
          // just_audio's playlist keeps the current source alive while the new
          // source is appended/prepared. Seeking to that prepared entry avoids
          // the explicit stop -> load -> play gap that mini-player swipes used
          // to trigger. Remove the obsolete entries only after takeover.
          final targetIndex = player.sequence.length;
          await player
              .addAudioSource(source)
              .timeout(const Duration(seconds: 30));
          if (generation != _openGeneration || _disposed) {
            if (player.sequence.length > targetIndex) {
              await player.removeAudioSourceAt(targetIndex);
            }
            if (!_disposed &&
                _item?.messageKey != item.messageKey) {
              unawaited(_clearPlaybackCache(item));
            }
            return;
          }
          await player
              .seek(resumeAt, index: targetIndex)
              .timeout(const Duration(seconds: 30));
          if (generation != _openGeneration || _disposed) {
            if (_disposed) {
              return;
            }
            // This source already became current before a rapid follow-up
            // gesture superseded it. Complete the takeover bookkeeping so the
            // queued request can append continuously and every replaced or
            // transient song still reaches temporary-file cleanup.
            if (targetIndex > 0) {
              await player.removeAudioSourceRange(0, targetIndex);
            }
            _activePlaybackItem = item;
            final interruptedPrevious = playbackItemToClean;
            if (!_disposed &&
                interruptedPrevious != null &&
                interruptedPrevious.messageKey != item.messageKey &&
                interruptedPrevious.messageKey != _item?.messageKey) {
              unawaited(_clearPlaybackCache(interruptedPrevious));
            }
            return;
          }
          if (targetIndex > 0) {
            await player.removeAudioSourceRange(0, targetIndex);
          }
        } else {
          await player
              .setAudioSources(
                <audio.AudioSource>[source],
                initialIndex: 0,
                initialPosition: resumeAt,
              )
              .timeout(const Duration(seconds: 60));
        }
        if (generation != _openGeneration || _disposed) {
          return;
        }
        await player.setLoopMode(
          _repeatEnabled ? audio.LoopMode.one : audio.LoopMode.off,
        );
        _activePlaybackItem = item;
      });
      if (generation != _openGeneration || _disposed) {
        return;
      }

      final stalePlaybackItem = playbackItemToClean;
      if (stalePlaybackItem != null &&
          stalePlaybackItem.messageKey != item.messageKey) {
        unawaited(_clearPlaybackCache(stalePlaybackItem));
      }
      // setAudioSources/addAudioSource has now prepared an initial safety
      // buffer. Starting the whole-file TDLib wait only after that point avoids
      // competing with the latency-sensitive first range while still moving
      // established playback onto a background-safe file:// source.
      final directUriFuture =
          _libraryController.prepareDirectPlaybackUri(item);
      _publishSystemMediaItem(item, generation);
      _recoveryBaseline = resumeAt;
      unawaited(_startPlayback(player, generation));
      unawaited(
        _upgradeToDirectPlaybackFile(
          item,
          generation,
          directUriFuture,
        ),
      );
      unawaited(_prewarmAdjacentTransitions());
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

  void _publishSystemMediaItem(MediaItem item, int generation) {
    final bridge = _systemMediaBridge;
    if (bridge == null) {
      return;
    }
    final duration = item.durationSeconds == null
        ? null
        : Duration(seconds: item.durationSeconds!);
    bridge.publishMediaItem(
      id: item.messageKey,
      title: item.title,
      artist: item.artist,
      album: item.album ?? 'Telegram Mix',
      duration: duration,
    );
    unawaited(_publishSystemArtwork(item, generation, duration));
  }

  Future<void> _publishSystemArtwork(
    MediaItem item,
    int generation,
    Duration? duration,
  ) async {
    final bridge = _systemMediaBridge;
    if (bridge == null) {
      return;
    }
    try {
      final bytes = await _libraryController.thumbnailFor(
        item,
        highQuality: true,
      );
      if (bytes == null || bytes.isEmpty || generation != _openGeneration) {
        return;
      }
      final cache = await getTemporaryDirectory();
      final directory = Directory(
        '${cache.path}${Platform.pathSeparator}teleplayer-system-artwork',
      );
      if (!await directory.exists()) {
        await directory.create(recursive: true);
      }
      final file = File(
        '${directory.path}${Platform.pathSeparator}'
        '${item.chatId}_${item.messageId}.${_artworkExtension(bytes)}',
      );
      await file.writeAsBytes(bytes, flush: true);
      if (generation != _openGeneration || _item?.messageKey != item.messageKey) {
        return;
      }
      bridge.publishMediaItem(
        id: item.messageKey,
        title: item.title,
        artist: item.artist,
        album: item.album ?? 'Telegram Mix',
        duration: duration,
        artUri: Uri.file(file.path),
      );
    } catch (_) {
      // System artwork is optional. Metadata and media controls remain active
      // even when a cover cannot be materialized locally.
    }
  }

  String _artworkExtension(List<int> bytes) {
    if (bytes.length >= 8 &&
        bytes[0] == 0x89 &&
        bytes[1] == 0x50 &&
        bytes[2] == 0x4e &&
        bytes[3] == 0x47) {
      return 'png';
    }
    if (bytes.length >= 12 &&
        bytes[0] == 0x52 &&
        bytes[1] == 0x49 &&
        bytes[2] == 0x46 &&
        bytes[3] == 0x46 &&
        bytes[8] == 0x57 &&
        bytes[9] == 0x45 &&
        bytes[10] == 0x42 &&
        bytes[11] == 0x50) {
      return 'webp';
    }
    return 'jpg';
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

  Future<void> _upgradeToDirectPlaybackFile(
    MediaItem item,
    int generation,
    Future<Uri?> directUriFuture,
  ) async {
    try {
      // This download is deliberately cancellable when the user changes
      // tracks. Cancellation used to escape this unawaited future as an
      // unhandled async error, which could terminate the app during rapid song
      // switches. Keep the entire preparation/handoff inside this guard.
      final directUri = await directUriFuture;
      if (directUri == null || directUri.scheme != 'file') {
        return;
      }
      if (_disposed ||
          generation != _openGeneration ||
          _item?.messageKey != item.messageKey) {
        return;
      }

      final localFile = File.fromUri(directUri);
      if (!await localFile.exists()) {
        return;
      }

      final player = _audioPlayer;
      if (player == null) {
        return;
      }

      await _withPlayerMutation(() async {
        if (_disposed ||
            generation != _openGeneration ||
            _item?.messageKey != item.messageKey ||
            _activePlaybackItem?.messageKey != item.messageKey) {
          return;
        }
        final wasPlaying = player.playing;
        // The initial localhost stream gives instant startup, but a Dart HTTP
        // server is vulnerable to aggressive OEM background throttling. As
        // soon as TDLib has the complete file, hand playback to ExoPlayer as a
        // file:// source. Append and prepare that source while the stream keeps
        // playing, then seek across at the latest position. This avoids another
        // stop/load gap during the background-reliability handoff.
        final sequenceLength = player.sequence.length;
        if (sequenceLength > 0) {
          await player
              .addAudioSource(audio.AudioSource.uri(directUri))
              .timeout(const Duration(seconds: 20));
          if (_disposed ||
              generation != _openGeneration ||
              _item?.messageKey != item.messageKey) {
            if (player.sequence.length > sequenceLength) {
              await player.removeAudioSourceAt(sequenceLength);
            }
            return;
          }
          final resumeAt = player.position;
          await player
              .seek(resumeAt, index: sequenceLength)
              .timeout(const Duration(seconds: 20));
          if (_disposed ||
              generation != _openGeneration ||
              _item?.messageKey != item.messageKey) {
            return;
          }
          await player.removeAudioSourceRange(0, sequenceLength);
        } else {
          await player
              .setAudioSources(
                <audio.AudioSource>[audio.AudioSource.uri(directUri)],
                initialIndex: 0,
                initialPosition: player.position,
              )
              .timeout(const Duration(seconds: 20));
        }
        if (_disposed ||
            generation != _openGeneration ||
            _item?.messageKey != item.messageKey) {
          return;
        }
        await player.setLoopMode(
          _repeatEnabled ? audio.LoopMode.one : audio.LoopMode.off,
        );
        if (wasPlaying) {
          unawaited(_startPlayback(player, generation));
        }
      });
      if (_disposed || generation != _openGeneration) {
        return;
      }
      _systemMediaBridge?.refreshPlaybackState();
      _notify();
    } on TimeoutException {
      // Keep the original stream if the native file handoff takes too long.
    } on audio.PlayerInterruptedException {
      // A user-initiated song change won the race with this background handoff.
    } catch (_) {
      // Direct-file preparation is optional and is commonly cancelled during
      // a song switch. Never allow that background task to become an unhandled
      // async error or crash an otherwise healthy player session.
    }
  }

  Future<void> togglePlay() async {
    if (isPlaying) {
      await pause();
    } else {
      await resume();
    }
  }

  Future<void> resume() async {
    final player = _audioPlayer;
    if (player == null || player.processingState == audio.ProcessingState.idle) {
      final currentItem = _item;
      if (currentItem != null) {
        await open(currentItem);
      }
      return;
    }
    if (player.processingState == audio.ProcessingState.completed) {
      await player.seek(Duration.zero);
    }
    unawaited(_startPlayback(player, _openGeneration));
    _notify();
  }

  Future<void> pause() async {
    await _audioPlayer?.pause();
    _notify();
  }

  Future<void> stopPlayback() async {
    final player = _audioPlayer;
    final currentItem = _activePlaybackItem ?? _item;
    if (player != null) {
      await _withPlayerMutation(() async {
        await player.stop();
        _activePlaybackItem = null;
      });
    }
    if (currentItem != null) {
      await _clearPlaybackCache(currentItem);
    }
    _notify();
  }

  Future<void> seekTo(Duration target) async {
    final player = _audioPlayer;
    if (player == null) {
      return;
    }
    final maxDuration = duration;
    final clamped = maxDuration > Duration.zero && target > maxDuration
        ? maxDuration
        : target < Duration.zero
            ? Duration.zero
            : target;
    await player.seek(clamped);
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
    final player = _systemMediaBridge?.player ?? createTelePlayerAudioPlayer();
    _audioPlayer = player;
    _playerSubscriptions
      ..add(player.playerStateStream.listen(_handlePlayerState))
      ..add(player.positionStream.listen(_handlePosition))
      ..add(player.durationStream.listen((_) => _notify()))
      ..add(player.errorStream.listen(_handlePlayerError));
    return player;
  }

  Future<Uri> _preparedStreamUri(MediaItem item) {
    final key = item.messageKey;
    final existing = _preparedStreamUris[key];
    if (existing != null) {
      return existing;
    }
    while (_preparedStreamUris.length >= 4) {
      _preparedStreamUris.remove(_preparedStreamUris.keys.first);
    }
    final request = _libraryController.streamUriFor(item);
    _preparedStreamUris[key] = request;
    unawaited(
      request.then<void>(
        (_) {},
        onError: (Object _, StackTrace _) {
          if (identical(_preparedStreamUris[key], request)) {
            _preparedStreamUris.remove(key);
          }
        },
      ),
    );
    return request;
  }

  Future<Uri> _takePreparedStreamUri(MediaItem item) {
    final prepared = _preparedStreamUris.remove(item.messageKey);
    return prepared ?? _libraryController.streamUriFor(item);
  }

  Future<void> _prewarmAdjacentTransitions() async {
    if (_shuffleEnabled || _disposed) {
      return;
    }
    final current = _item;
    if (current == null) {
      return;
    }
    final adjacent = <MediaItem?>[_adjacentItem(-1), _adjacentItem(1)];
    await Future.wait(
      adjacent
          .whereType<MediaItem>()
          .where((candidate) => candidate.messageKey != current.messageKey)
          .map(prepareForTransition),
    );
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
      _activePlaybackItem = null;
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
    final player = _audioPlayer;
    if (player == null) {
      return;
    }
    final generation = _openGeneration;
    final stalledAtPosition = player.position;
    final stalledAtBufferedPosition = player.bufferedPosition;
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
      final positionProgress =
          player.position - stalledAtPosition >= _bufferingProgressTolerance;
      final bufferProgress =
          player.bufferedPosition - stalledAtBufferedPosition >=
              _bufferingProgressTolerance;
      if (positionProgress || bufferProgress) {
        // Telegram is still delivering useful data. Give the native full-file
        // preparation another window instead of throwing away that progress
        // and reopening the stream, which used to create repeated background
        // buffering loops on slower connections.
        _armBufferingWatchdog();
        return;
      }
      _recoverPlayback(
        const AppException(
          AppErrorCode.networkInterrupted,
          message: 'Telegram playback stopped making buffering progress.',
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

  Future<T> _withPlayerMutation<T>(Future<T> Function() operation) async {
    final previous = _playerMutationTail;
    final turn = Completer<void>();
    _playerMutationTail = turn.future;
    try {
      try {
        await previous;
      } catch (_) {
        // A failed earlier mutation must not poison the serialization queue.
      }
      return await operation();
    } finally {
      if (!turn.isCompleted) {
        turn.complete();
      }
    }
  }

  Future<void> _clearPlaybackCache(MediaItem item) async {
    _preparedStreamUris.remove(item.messageKey)?.ignore();
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
    _preparedStreamUris.clear();
    final player = _audioPlayer;
    _audioPlayer = null;
    final bridge = _systemMediaBridge;
    if (bridge != null && identical(player, bridge.player)) {
      unawaited(bridge.disposeBridge());
    } else {
      unawaited(player?.dispose());
    }
    super.dispose();
  }
}
