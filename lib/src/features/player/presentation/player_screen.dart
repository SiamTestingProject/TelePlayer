import 'dart:async';

import 'package:flutter/material.dart';
import 'package:video_player/video_player.dart';

import '../../../app/app_scope.dart';
import '../../../app/error_panel.dart';
import '../../library/models/media_item.dart';
import '../../library/presentation/media_artwork.dart';
import '../application/player_controller.dart';

class PlayerScreen extends StatelessWidget {
  const PlayerScreen({required this.onClose, super.key});

  final VoidCallback onClose;

  @override
  Widget build(BuildContext context) {
    final scope = AppScope.of(context);
    final player = scope.playerController;
    final item = player.item;
    final colors = Theme.of(context).colorScheme;

    return Scaffold(
      backgroundColor: colors.surface,
      body: DecoratedBox(
        decoration: BoxDecoration(
          gradient: LinearGradient(
            begin: Alignment.topCenter,
            end: Alignment.bottomCenter,
            colors: <Color>[
              colors.primaryContainer.withValues(alpha: 0.68),
              colors.tertiaryContainer.withValues(alpha: 0.34),
              colors.surface,
            ],
            stops: const <double>[0, 0.42, 1],
          ),
        ),
        child: SafeArea(
          child: item == null
              ? _EmptyPlayer(onClose: onClose)
              : LayoutBuilder(
                  builder: (context, constraints) {
                    final artworkSize = (constraints.maxWidth - 56)
                        .clamp(240.0, 460.0)
                        .toDouble();
                    return SingleChildScrollView(
                      padding: const EdgeInsets.fromLTRB(22, 16, 22, 28),
                      child: Center(
                        child: ConstrainedBox(
                          constraints: const BoxConstraints(maxWidth: 620),
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.stretch,
                            children: <Widget>[
                              _PlayerHeader(onClose: onClose),
                              const SizedBox(height: 14),
                              Center(child: _SourcePill(item: item)),
                              const SizedBox(height: 24),
                              Center(
                                child: SizedBox.square(
                                  dimension: artworkSize,
                                  child: Material(
                                    elevation: 18,
                                    shadowColor:
                                        colors.primary.withValues(alpha: 0.24),
                                    borderRadius: BorderRadius.circular(38),
                                    clipBehavior: Clip.antiAlias,
                                    child: Hero(
                                      tag: 'artwork-${item.id}',
                                      child: _NowPlayingArtwork(
                                        item: item,
                                        player: player,
                                      ),
                                    ),
                                  ),
                                ),
                              ),
                              const SizedBox(height: 30),
                              Container(
                                padding: const EdgeInsets.fromLTRB(18, 16, 10, 16),
                                decoration: BoxDecoration(
                                  color: colors.surfaceContainer
                                      .withValues(alpha: 0.76),
                                  borderRadius: BorderRadius.circular(30),
                                  border: Border.all(
                                    color: colors.outlineVariant
                                        .withValues(alpha: 0.28),
                                  ),
                                ),
                                child: Row(
                                  crossAxisAlignment: CrossAxisAlignment.end,
                                  children: <Widget>[
                                    Expanded(
                                      child: Column(
                                        crossAxisAlignment: CrossAxisAlignment.start,
                                        children: <Widget>[
                                          Text(
                                            item.title,
                                            maxLines: 2,
                                            overflow: TextOverflow.ellipsis,
                                            style: Theme.of(context)
                                                .textTheme
                                                .headlineMedium
                                                ?.copyWith(
                                                  fontWeight: FontWeight.w800,
                                                  letterSpacing: 0,
                                                ),
                                          ),
                                          const SizedBox(height: 5),
                                          Text(
                                            item.artist ?? _mediaType(item),
                                            maxLines: 1,
                                            overflow: TextOverflow.ellipsis,
                                            style: Theme.of(context)
                                                .textTheme
                                                .titleMedium
                                                ?.copyWith(
                                                  color: colors.onSurfaceVariant,
                                                ),
                                          ),
                                        ],
                                      ),
                                    ),
                                    IconButton.filledTonal(
                                      tooltip: 'Favorite',
                                      onPressed: player.toggleFavorite,
                                      icon: Icon(
                                        player.isFavorite
                                            ? Icons.favorite_rounded
                                            : Icons.favorite_border_rounded,
                                      ),
                                    ),
                                  ],
                                ),
                              ),
                              const SizedBox(height: 24),
                              if (player.error != null) ...<Widget>[
                                ErrorPanel(
                                  error: player.error!,
                                  onAction: () => unawaited(player.open(item)),
                                ),
                                const SizedBox(height: 16),
                              ],
                              if (player.isLoading) ...<Widget>[
                                const LinearProgressIndicator(),
                                const SizedBox(height: 16),
                              ],
                              _ProgressSection(player: player, item: item),
                              const SizedBox(height: 24),
                              _PrimaryControls(player: player),
                              const SizedBox(height: 22),
                              _PlaybackModes(player: player),
                            ],
                          ),
                        ),
                      ),
                    );
                  },
                ),
        ),
      ),
    );
  }

  String _mediaType(MediaItem item) {
    return item.kind == MediaKind.audio ? 'Telegram audio' : 'Telegram video';
  }
}

class _SourcePill extends StatelessWidget {
  const _SourcePill({required this.item});

  final MediaItem item;

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).colorScheme;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
      decoration: BoxDecoration(
        color: colors.surface.withValues(alpha: 0.62),
        borderRadius: BorderRadius.circular(24),
        border: Border.all(color: colors.outlineVariant.withValues(alpha: 0.24)),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: <Widget>[
          Icon(
            item.kind == MediaKind.audio
                ? Icons.music_note_rounded
                : Icons.movie_rounded,
            size: 18,
            color: colors.primary,
          ),
          const SizedBox(width: 7),
          Text(
            item.kind == MediaKind.audio ? 'Telegram Audio' : 'Telegram Video',
            style: Theme.of(context).textTheme.labelLarge?.copyWith(
                  color: colors.onSurfaceVariant,
                  fontWeight: FontWeight.w800,
                  letterSpacing: 0,
                ),
          ),
        ],
      ),
    );
  }
}

class _PlayerHeader extends StatelessWidget {
  const _PlayerHeader({required this.onClose});

  final VoidCallback onClose;

  @override
  Widget build(BuildContext context) {
    return Row(
      children: <Widget>[
        IconButton.filledTonal(
          tooltip: 'Back to Library',
          onPressed: onClose,
          icon: const Icon(Icons.keyboard_arrow_down_rounded),
        ),
        const SizedBox(width: 14),
        Expanded(
          child: Text(
            'Now Playing',
            style: Theme.of(context).textTheme.titleLarge?.copyWith(
                  fontWeight: FontWeight.w700,
                ),
          ),
        ),
        IconButton.filledTonal(
          tooltip: 'Playback queue',
          onPressed: () => _showQueue(context),
          icon: const Icon(Icons.queue_music_rounded),
        ),
      ],
    );
  }

  void _showQueue(BuildContext context) {
    final scope = AppScope.of(context);
    unawaited(
      showModalBottomSheet<void>(
        context: context,
        showDragHandle: true,
        builder: (context) {
          final items = scope.libraryController.items;
          return SafeArea(
            child: ListView(
              padding: const EdgeInsets.fromLTRB(16, 0, 16, 20),
              children: <Widget>[
                Padding(
                  padding: const EdgeInsets.fromLTRB(4, 4, 4, 12),
                  child: Text(
                    'Up Next',
                    style: Theme.of(context).textTheme.titleLarge?.copyWith(
                          fontWeight: FontWeight.w800,
                          letterSpacing: 0,
                        ),
                  ),
                ),
                for (final item in items)
                  ListTile(
                    leading: Icon(
                      item.kind == MediaKind.audio
                          ? Icons.music_note_rounded
                          : Icons.movie_rounded,
                    ),
                    title: Text(item.title, maxLines: 1),
                    subtitle: item.artist == null ? null : Text(item.artist!),
                    selected: scope.playerController.item?.id == item.id,
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(20),
                    ),
                    onTap: () {
                      Navigator.pop(context);
                      unawaited(scope.playerController.open(item));
                    },
                  ),
              ],
            ),
          );
        },
      ),
    );
  }
}

class _NowPlayingArtwork extends StatelessWidget {
  const _NowPlayingArtwork({required this.item, required this.player});

  final MediaItem item;
  final PlayerController player;

  @override
  Widget build(BuildContext context) {
    final controller = player.videoController;
    if (item.kind != MediaKind.audio &&
        controller != null &&
        controller.value.isInitialized) {
      return ClipRRect(
        borderRadius: BorderRadius.circular(38),
        child: ColoredBox(
          color: Colors.black,
          child: Center(
            child: AspectRatio(
              aspectRatio: controller.value.aspectRatio == 0
                  ? 16 / 9
                  : controller.value.aspectRatio,
              child: VideoPlayer(controller),
            ),
          ),
        ),
      );
    }
    return MediaArtwork(
      item: item,
      libraryController: AppScope.of(context).libraryController,
      borderRadius: 38,
      iconSize: 82,
    );
  }
}

class _ProgressSection extends StatelessWidget {
  const _ProgressSection({required this.player, required this.item});

  final PlayerController player;
  final MediaItem item;

  @override
  Widget build(BuildContext context) {
    final controller = player.videoController;
    if (controller == null) {
      return _ProgressContent(
        position: Duration.zero,
        duration: Duration(seconds: item.durationSeconds ?? 0),
        item: item,
        onChanged: null,
      );
    }
    return AnimatedBuilder(
      animation: controller,
      builder: (context, _) {
        final value = controller.value;
        final duration = value.duration > Duration.zero
            ? value.duration
            : Duration(seconds: item.durationSeconds ?? 0);
        final position = value.position > duration ? duration : value.position;
        return _ProgressContent(
          position: position,
          duration: duration,
          item: item,
          onChanged: duration <= Duration.zero
              ? null
              : (fraction) => unawaited(player.seekToFraction(fraction)),
        );
      },
    );
  }
}

class _ProgressContent extends StatelessWidget {
  const _ProgressContent({
    required this.position,
    required this.duration,
    required this.item,
    required this.onChanged,
  });

  final Duration position;
  final Duration duration;
  final MediaItem item;
  final ValueChanged<double>? onChanged;

  @override
  Widget build(BuildContext context) {
    final fraction = duration.inMilliseconds <= 0
        ? 0.0
        : (position.inMilliseconds / duration.inMilliseconds)
            .clamp(0.0, 1.0)
            .toDouble();
    final type = item.mimeType.split('/').last.toUpperCase();
    final colors = Theme.of(context).colorScheme;
    return Container(
      padding: const EdgeInsets.fromLTRB(10, 8, 10, 12),
      decoration: BoxDecoration(
        color: colors.surfaceContainer.withValues(alpha: 0.76),
        borderRadius: BorderRadius.circular(30),
        border: Border.all(color: colors.outlineVariant.withValues(alpha: 0.24)),
      ),
      child: Column(
        children: <Widget>[
          Slider(
            value: fraction,
            onChanged: onChanged,
          ),
          Row(
            children: <Widget>[
              Text(_time(position)),
              Expanded(
                child: Center(
                  child: Container(
                    padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 5),
                    decoration: BoxDecoration(
                      color: colors.surfaceContainerHighest,
                      borderRadius: BorderRadius.circular(18),
                    ),
                    child: Text(
                      '${item.readableSize} · $type',
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: Theme.of(context).textTheme.labelMedium,
                    ),
                  ),
                ),
              ),
              Text(_time(duration)),
            ],
          ),
        ],
      ),
    );
  }

  String _time(Duration duration) {
    final hours = duration.inHours;
    final minutes = duration.inMinutes.remainder(60).toString().padLeft(2, '0');
    final seconds = duration.inSeconds.remainder(60).toString().padLeft(2, '0');
    return hours > 0 ? '$hours:$minutes:$seconds' : '$minutes:$seconds';
  }
}

class _PrimaryControls extends StatelessWidget {
  const _PrimaryControls({required this.player});

  final PlayerController player;

  @override
  Widget build(BuildContext context) {
    final controller = player.videoController;
    final playing = controller?.value.isPlaying == true;
    final colors = Theme.of(context).colorScheme;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 14),
      decoration: BoxDecoration(
        color: colors.surfaceContainerHigh.withValues(alpha: 0.84),
        borderRadius: BorderRadius.circular(42),
        border: Border.all(color: colors.outlineVariant.withValues(alpha: 0.24)),
      ),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceEvenly,
        children: <Widget>[
          _LargeControlButton(
            tooltip: 'Previous',
            icon: Icons.skip_previous_rounded,
            onPressed: () => unawaited(player.playPrevious()),
          ),
          _LargeControlButton(
            tooltip: playing ? 'Pause' : 'Play',
            icon: playing ? Icons.pause_rounded : Icons.play_arrow_rounded,
            emphasized: true,
            onPressed: () => unawaited(player.togglePlay()),
          ),
          _LargeControlButton(
            tooltip: 'Next',
            icon: Icons.skip_next_rounded,
            onPressed: () => unawaited(player.playNext()),
          ),
        ],
      ),
    );
  }
}

class _LargeControlButton extends StatelessWidget {
  const _LargeControlButton({
    required this.tooltip,
    required this.icon,
    required this.onPressed,
    this.emphasized = false,
  });

  final String tooltip;
  final IconData icon;
  final VoidCallback onPressed;
  final bool emphasized;

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).colorScheme;
    return Tooltip(
      message: tooltip,
      child: SizedBox.square(
        dimension: emphasized ? 88 : 68,
        child: Material(
          color: emphasized ? colors.primary : colors.surfaceContainerHighest,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(emphasized ? 32 : 26),
          ),
          clipBehavior: Clip.antiAlias,
          child: InkWell(
            onTap: onPressed,
            child: Icon(
              icon,
              size: emphasized ? 42 : 32,
              color: emphasized ? colors.onPrimary : colors.onSurfaceVariant,
            ),
          ),
        ),
      ),
    );
  }
}

class _PlaybackModes extends StatelessWidget {
  const _PlaybackModes({required this.player});

  final PlayerController player;

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).colorScheme;
    return Container(
      padding: const EdgeInsets.all(8),
      decoration: BoxDecoration(
        color: colors.surfaceContainer.withValues(alpha: 0.76),
        borderRadius: BorderRadius.circular(34),
        border: Border.all(color: colors.outlineVariant.withValues(alpha: 0.24)),
      ),
      child: Row(
        children: <Widget>[
          Expanded(
            child: _ModeButton(
              tooltip: 'Shuffle',
              selected: player.shuffleEnabled,
              icon: Icons.shuffle_rounded,
              onPressed: player.toggleShuffle,
            ),
          ),
          Expanded(
            child: _ModeButton(
              tooltip: 'Repeat',
              selected: player.repeatEnabled,
              icon: Icons.repeat_rounded,
              onPressed: () => unawaited(player.toggleRepeat()),
            ),
          ),
          Expanded(
            child: _ModeButton(
              tooltip: 'Favorite',
              selected: player.isFavorite,
              icon: player.isFavorite
                  ? Icons.favorite_rounded
                  : Icons.favorite_border_rounded,
              onPressed: player.toggleFavorite,
            ),
          ),
        ],
      ),
    );
  }
}

class _ModeButton extends StatelessWidget {
  const _ModeButton({
    required this.tooltip,
    required this.selected,
    required this.icon,
    required this.onPressed,
  });

  final String tooltip;
  final bool selected;
  final IconData icon;
  final VoidCallback onPressed;

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).colorScheme;
    return Tooltip(
      message: tooltip,
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 3),
        child: Material(
          color: selected ? colors.primaryContainer : Colors.transparent,
          borderRadius: BorderRadius.circular(27),
          clipBehavior: Clip.antiAlias,
          child: InkWell(
            onTap: onPressed,
            child: Padding(
              padding: const EdgeInsets.symmetric(vertical: 15),
              child: Icon(
                icon,
                color: selected
                    ? colors.onPrimaryContainer
                    : colors.onSurfaceVariant,
              ),
            ),
          ),
        ),
      ),
    );
  }
}

class _EmptyPlayer extends StatelessWidget {
  const _EmptyPlayer({required this.onClose});

  final VoidCallback onClose;

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).colorScheme;
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(32),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: <Widget>[
            Container(
              width: 108,
              height: 108,
              decoration: BoxDecoration(
                color: colors.primaryContainer,
                borderRadius: BorderRadius.circular(34),
              ),
              child: Icon(
                Icons.headphones_rounded,
                size: 66,
                color: colors.onPrimaryContainer,
              ),
            ),
            const SizedBox(height: 20),
            Text(
              'Nothing playing',
              style: Theme.of(context).textTheme.headlineSmall,
            ),
            const SizedBox(height: 8),
            Text(
              'Choose a song or video from your Telegram Library.',
              textAlign: TextAlign.center,
              style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                    color: colors.onSurfaceVariant,
                  ),
            ),
            const SizedBox(height: 24),
            FilledButton.icon(
              onPressed: onClose,
              icon: const Icon(Icons.library_music_rounded),
              label: const Text('Open Library'),
            ),
          ],
        ),
      ),
    );
  }
}
