import 'dart:async';

import 'package:audio_service/audio_service.dart';
import 'package:just_audio/just_audio.dart' as audio;

/// Creates the single playback engine used by TelePlayer.
///
/// On Android this player is owned by [SystemMediaBridge], i.e. the
/// [AudioHandler] registered with audio_service. Keeping the real player inside
/// the foreground media handler is important: the native service then owns the
/// playback lifecycle instead of merely mirroring a player attached to the UI.
audio.AudioPlayer createTelePlayerAudioPlayer() {
  return audio.AudioPlayer(
    useLazyPreparation: false,
    audioLoadConfiguration: const audio.AudioLoadConfiguration(
      androidLoadControl: audio.AndroidLoadControl(
        // Keep a generous safety window while TDLib prepares a complete local
        // file. Once that file is ready PlayerController swaps the localhost
        // stream for file:// playback, removing the Dart HTTP server from the
        // background playback path entirely.
        minBufferDuration: Duration(minutes: 2),
        maxBufferDuration: Duration(minutes: 5),
        bufferForPlaybackDuration: Duration(seconds: 2),
        bufferForPlaybackAfterRebufferDuration: Duration(seconds: 10),
        prioritizeTimeOverSizeThresholds: true,
        backBufferDuration: Duration(seconds: 30),
      ),
    ),
  );
}

class SystemMediaBridge extends BaseAudioHandler with SeekHandler {
  SystemMediaBridge({audio.AudioPlayer? audioPlayer})
      : player = audioPlayer ?? createTelePlayerAudioPlayer() {
    _playbackEventSubscription = player.playbackEventStream.listen(
      (_) => _publishPlaybackState(),
      onError: (_) => _publishPlaybackState(),
    );
    _playerStateSubscription = player.playerStateStream.listen(
      (_) => _publishPlaybackState(),
      onError: (_) => _publishPlaybackState(),
    );
    _publishPlaybackState();
  }

  /// The real just_audio engine is deliberately owned by the AudioHandler.
  /// PlayerController uses this same instance for its UI-facing state.
  final audio.AudioPlayer player;

  StreamSubscription<audio.PlaybackEvent>? _playbackEventSubscription;
  StreamSubscription<audio.PlayerState>? _playerStateSubscription;

  Future<void> Function()? _onPlay;
  Future<void> Function()? _onPause;
  Future<void> Function()? _onStop;
  Future<void> Function()? _onNext;
  Future<void> Function()? _onPrevious;
  Future<void> Function(Duration position)? _onSeek;

  void bindControls({
    required Future<void> Function() onPlay,
    required Future<void> Function() onPause,
    required Future<void> Function() onStop,
    required Future<void> Function() onNext,
    required Future<void> Function() onPrevious,
    required Future<void> Function(Duration position) onSeek,
  }) {
    _onPlay = onPlay;
    _onPause = onPause;
    _onStop = onStop;
    _onNext = onNext;
    _onPrevious = onPrevious;
    _onSeek = onSeek;
  }

  void publishMediaItem({
    required String id,
    required String title,
    String? artist,
    String? album,
    Duration? duration,
    Uri? artUri,
  }) {
    mediaItem.add(
      MediaItem(
        id: id,
        title: title,
        artist: artist,
        album: album,
        duration: duration,
        artUri: artUri,
        playable: true,
      ),
    );
  }

  void refreshPlaybackState() => _publishPlaybackState();

  void _publishPlaybackState() {
    final processingState = switch (player.processingState) {
      audio.ProcessingState.idle => AudioProcessingState.idle,
      audio.ProcessingState.loading => AudioProcessingState.loading,
      audio.ProcessingState.buffering => AudioProcessingState.buffering,
      audio.ProcessingState.ready => AudioProcessingState.ready,
      audio.ProcessingState.completed => AudioProcessingState.completed,
    };
    final controls = <MediaControl>[
      MediaControl.skipToPrevious,
      if (player.playing) MediaControl.pause else MediaControl.play,
      MediaControl.skipToNext,
    ];
    playbackState.add(
      PlaybackState(
        controls: controls,
        systemActions: const <MediaAction>{
          MediaAction.seek,
          MediaAction.seekForward,
          MediaAction.seekBackward,
        },
        androidCompactActionIndices: const <int>[0, 1, 2],
        processingState: processingState,
        playing: player.playing,
        updatePosition: player.position,
        bufferedPosition: player.bufferedPosition,
        speed: player.speed,
      ),
    );
  }

  @override
  Future<void> play() async {
    final callback = _onPlay;
    if (callback != null) {
      await callback();
    } else {
      await player.play();
    }
    _publishPlaybackState();
  }

  @override
  Future<void> pause() async {
    final callback = _onPause;
    if (callback != null) {
      await callback();
    } else {
      await player.pause();
    }
    _publishPlaybackState();
  }

  @override
  Future<void> stop() async {
    final callback = _onStop;
    if (callback != null) {
      await callback();
    } else {
      await player.stop();
    }
    _publishPlaybackState();
  }

  @override
  Future<void> seek(Duration position) async {
    final callback = _onSeek;
    if (callback != null) {
      await callback(position);
    } else {
      await player.seek(position);
    }
    _publishPlaybackState();
  }

  @override
  Future<void> skipToNext() async {
    final callback = _onNext;
    if (callback != null) {
      await callback();
    }
    _publishPlaybackState();
  }

  @override
  Future<void> skipToPrevious() async {
    final callback = _onPrevious;
    if (callback != null) {
      await callback();
    }
    _publishPlaybackState();
  }

  Future<void> disposeBridge() async {
    await _playbackEventSubscription?.cancel();
    await _playerStateSubscription?.cancel();
    _playbackEventSubscription = null;
    _playerStateSubscription = null;
    await player.dispose();
  }
}
