import 'dart:async';

import 'package:flutter/material.dart';
import 'package:video_player/video_player.dart';

import '../../../app/app_scope.dart';
import '../../../app/error_panel.dart';

class PlayerScreen extends StatelessWidget {
  const PlayerScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final player = AppScope.of(context).playerController;
    return Scaffold(
      appBar: AppBar(title: const Text('Player')),
      body: SafeArea(
        child: ListView(
          padding: const EdgeInsets.all(16),
          children: [
            if (player.error != null) ...[
              ErrorPanel(
                error: player.error!,
                onAction: player.item == null ? null : () => unawaited(player.open(player.item!)),
              ),
              const SizedBox(height: 12),
            ],
            if (player.isLoading) const LinearProgressIndicator(),
            const SizedBox(height: 12),
            if (player.videoController == null)
              SizedBox(
                height: 360,
                child: Center(
                  child: Text(
                    'Nothing playing',
                    style: Theme.of(context).textTheme.titleMedium,
                  ),
                ),
              )
            else
              _VideoSurface(controller: player.videoController!),
            const SizedBox(height: 12),
            if (player.item != null)
              Text(
                player.item!.title,
                maxLines: 2,
                overflow: TextOverflow.ellipsis,
                style: Theme.of(context).textTheme.titleLarge,
              ),
          ],
        ),
      ),
      bottomNavigationBar: player.videoController == null
          ? null
          : _PlaybackBar(controller: player.videoController!, onTogglePlay: player.togglePlay),
    );
  }
}

class _VideoSurface extends StatelessWidget {
  const _VideoSurface({required this.controller});

  final VideoPlayerController controller;

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: controller,
      builder: (context, _) {
        if (!controller.value.isInitialized) {
          return const AspectRatio(
            aspectRatio: 16 / 9,
            child: Center(child: CircularProgressIndicator()),
          );
        }
        return ClipRRect(
          borderRadius: BorderRadius.circular(8),
          child: AspectRatio(
            aspectRatio: controller.value.aspectRatio == 0 ? 16 / 9 : controller.value.aspectRatio,
            child: VideoPlayer(controller),
          ),
        );
      },
    );
  }
}

class _PlaybackBar extends StatelessWidget {
  const _PlaybackBar({required this.controller, required this.onTogglePlay});

  final VideoPlayerController controller;
  final Future<void> Function() onTogglePlay;

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: controller,
      builder: (context, _) {
        final value = controller.value;
        final duration = value.duration;
        final position = value.position > duration ? duration : value.position;
        return SafeArea(
          child: Padding(
            padding: const EdgeInsets.fromLTRB(16, 4, 16, 12),
            child: Row(
              children: [
                IconButton.filled(
                  tooltip: value.isPlaying ? 'Pause' : 'Play',
                  onPressed: () => unawaited(onTogglePlay()),
                  icon: Icon(value.isPlaying ? Icons.pause : Icons.play_arrow),
                ),
                const SizedBox(width: 12),
                Text(_time(position)),
                Expanded(
                  child: Slider(
                    value: duration.inMilliseconds == 0
                        ? 0
                        : position.inMilliseconds / duration.inMilliseconds,
                    onChanged: duration.inMilliseconds == 0
                        ? null
                        : (value) {
                            final target = Duration(
                              milliseconds: (duration.inMilliseconds * value).round(),
                            );
                            unawaited(controller.seekTo(target));
                          },
                  ),
                ),
                Text(_time(duration)),
              ],
            ),
          ),
        );
      },
    );
  }

  String _time(Duration duration) {
    final hours = duration.inHours;
    final minutes = duration.inMinutes.remainder(60).toString().padLeft(2, '0');
    final seconds = duration.inSeconds.remainder(60).toString().padLeft(2, '0');
    return hours > 0 ? '$hours:$minutes:$seconds' : '$minutes:$seconds';
  }
}
