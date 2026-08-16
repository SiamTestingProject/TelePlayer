import 'dart:async';
import 'dart:math' as math;

import 'package:flutter/material.dart';

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

    return Scaffold(
      backgroundColor: _PlayerPalette.background,
      body: ColoredBox(
        color: _PlayerPalette.background,
        child: SafeArea(
          child: item == null
              ? _EmptyPlayer(onClose: onClose)
              : LayoutBuilder(
                  builder: (context, constraints) {
                    return SingleChildScrollView(
                      padding: const EdgeInsets.fromLTRB(24, 18, 24, 30),
                      child: Center(
                        child: ConstrainedBox(
                          constraints: const BoxConstraints(maxWidth: 540),
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.stretch,
                            children: <Widget>[
                              _PlayerHeader(
                                onClose: onClose,
                                onAudioOutput: () => _showAudioOutputInfo(context),
                                onQueue: () => _showQueue(context),
                              ),
                              const SizedBox(height: 38),
                              _ArtworkCarousel(
                                item: item,
                                nextItem: _nextLibraryItem(
                                  item,
                                  scope.libraryController.items,
                                ),
                              ),
                              const SizedBox(height: 48),
                              _TrackIdentity(
                                item: item,
                                onDetails: () => _showSongDetails(context, item),
                              ),
                              const SizedBox(height: 28),
                              if (player.error != null) ...<Widget>[
                                Theme(
                                  data: Theme.of(context).copyWith(
                                    colorScheme: Theme.of(context)
                                        .colorScheme
                                        .copyWith(
                                          surface: _PlayerPalette.darkSurface,
                                          onSurface: _PlayerPalette.text,
                                          onSurfaceVariant:
                                              _PlayerPalette.secondaryText,
                                        ),
                                  ),
                                  child: ErrorPanel(
                                    error: player.error!,
                                    onAction: () => unawaited(player.open(item)),
                                  ),
                                ),
                                const SizedBox(height: 18),
                              ],
                              _ProgressSection(player: player, item: item),
                              const SizedBox(height: 30),
                              _PrimaryControls(player: player),
                              const SizedBox(height: 28),
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

  MediaItem? _nextLibraryItem(MediaItem current, List<MediaItem> items) {
    if (items.length < 2) {
      return null;
    }
    final currentIndex = items.indexWhere((candidate) => candidate.id == current.id);
    if (currentIndex < 0) {
      return items.first;
    }
    return items[(currentIndex + 1) % items.length];
  }

  void _showQueue(BuildContext context) {
    final scope = AppScope.of(context);
    unawaited(
      showModalBottomSheet<void>(
        context: context,
        showDragHandle: true,
        useSafeArea: true,
        builder: (context) {
          final items = scope.libraryController.items;
          return ListView.builder(
            padding: const EdgeInsets.fromLTRB(14, 0, 14, 24),
            itemCount: items.length,
            itemBuilder: (context, index) {
              final item = items[index];
              return ListTile(
                leading: SizedBox.square(
                  dimension: 48,
                  child: MediaArtwork(
                    item: item,
                    libraryController: scope.libraryController,
                    borderRadius: 14,
                    iconSize: 20,
                  ),
                ),
                title: Text(
                  item.title,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
                subtitle: item.artist == null
                    ? null
                    : Text(
                        item.artist!,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                      ),
                selected: scope.playerController.item?.id == item.id,
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(20),
                ),
                onTap: () {
                  Navigator.pop(context);
                  unawaited(scope.playerController.open(item));
                },
              );
            },
          );
        },
      ),
    );
  }

  void _showAudioOutputInfo(BuildContext context) {
    unawaited(
      showModalBottomSheet<void>(
        context: context,
        showDragHandle: true,
        useSafeArea: true,
        builder: (context) {
          return const Padding(
            padding: EdgeInsets.fromLTRB(24, 4, 24, 28),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: <Widget>[
                Text(
                  'Audio output',
                  style: TextStyle(fontSize: 22, fontWeight: FontWeight.w800),
                ),
                SizedBox(height: 10),
                Text(
                  'TelePlayer uses the active Android or Windows system audio output. '
                  'Change Bluetooth, speaker, headset, or other routing from the system audio controls.',
                ),
              ],
            ),
          );
        },
      ),
    );
  }

  void _showSongDetails(BuildContext context, MediaItem item) {
    final duration = Duration(seconds: item.durationSeconds ?? 0);
    unawaited(
      showModalBottomSheet<void>(
        context: context,
        showDragHandle: true,
        useSafeArea: true,
        builder: (context) {
          return Padding(
            padding: const EdgeInsets.fromLTRB(24, 4, 24, 28),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: <Widget>[
                Text(
                  item.title,
                  style: const TextStyle(
                    fontSize: 22,
                    fontWeight: FontWeight.w800,
                  ),
                ),
                if (item.artist?.trim().isNotEmpty == true) ...<Widget>[
                  const SizedBox(height: 4),
                  Text(item.artist!),
                ],
                const SizedBox(height: 18),
                _DetailRow(label: 'File', value: item.fileName),
                _DetailRow(label: 'Type', value: item.mimeType),
                _DetailRow(label: 'Size', value: item.readableSize),
                if (duration > Duration.zero)
                  _DetailRow(label: 'Duration', value: _formatTime(duration)),
              ],
            ),
          );
        },
      ),
    );
  }
}

class _PlayerPalette {
  static const Color background = Color(0xFF014A75);
  static const Color headerSurface = Color(0xFF003B5D);
  static const Color darkSurface = Color(0xFF1A2C40);
  static const Color text = Color(0xFFCDE5FF);
  static const Color secondaryText = Color(0xFF9FC7E5);
  static const Color paleBlue = Color(0xFF94CCFF);
  static const Color lavender = Color(0xFFCDBDFE);
  static const Color selected = Color(0xFFCDE5FF);
  static const Color ink = Color(0xFF10283A);
  static const Color inactiveTrack = Color(0xFF1B6A95);
}

class _PlayerHeader extends StatelessWidget {
  const _PlayerHeader({
    required this.onClose,
    required this.onAudioOutput,
    required this.onQueue,
  });

  final VoidCallback onClose;
  final VoidCallback onAudioOutput;
  final VoidCallback onQueue;

  @override
  Widget build(BuildContext context) {
    return Row(
      children: <Widget>[
        _HeaderButton(
          tooltip: 'Back to Library',
          onPressed: onClose,
          circular: true,
          child: const Icon(
            Icons.keyboard_arrow_down_rounded,
            size: 30,
            color: _PlayerPalette.paleBlue,
          ),
        ),
        const SizedBox(width: 22),
        const Expanded(
          child: Text(
            'Now Playing',
            style: TextStyle(
              color: _PlayerPalette.text,
              fontSize: 23,
              height: 1,
              fontWeight: FontWeight.w800,
              letterSpacing: -0.3,
            ),
          ),
        ),
        _HeaderButton(
          tooltip: 'Audio output',
          onPressed: onAudioOutput,
          child: const _AudioOutputGlyph(),
        ),
        const SizedBox(width: 8),
        _HeaderButton(
          tooltip: 'Playback queue',
          onPressed: onQueue,
          child: const Icon(
            Icons.queue_music_rounded,
            size: 30,
            color: _PlayerPalette.paleBlue,
          ),
        ),
      ],
    );
  }
}

class _HeaderButton extends StatelessWidget {
  const _HeaderButton({
    required this.tooltip,
    required this.onPressed,
    required this.child,
    this.circular = false,
  });

  final String tooltip;
  final VoidCallback onPressed;
  final Widget child;
  final bool circular;

  @override
  Widget build(BuildContext context) {
    return Tooltip(
      message: tooltip,
      child: SizedBox.square(
        dimension: 58,
        child: Material(
          color: _PlayerPalette.headerSurface,
          shape: circular
              ? const CircleBorder()
              : RoundedRectangleBorder(borderRadius: BorderRadius.circular(18)),
          clipBehavior: Clip.antiAlias,
          child: InkWell(
            onTap: onPressed,
            child: Center(child: child),
          ),
        ),
      ),
    );
  }
}

class _AudioOutputGlyph extends StatelessWidget {
  const _AudioOutputGlyph();

  @override
  Widget build(BuildContext context) {
    return const SizedBox.square(
      dimension: 34,
      child: Stack(
        clipBehavior: Clip.none,
        children: <Widget>[
          Positioned(
            left: 2,
            top: 2,
            child: Icon(
              Icons.smartphone_rounded,
              size: 25,
              color: _PlayerPalette.paleBlue,
            ),
          ),
          Positioned(
            right: -1,
            bottom: 1,
            child: Icon(
              Icons.volume_up_rounded,
              size: 21,
              color: _PlayerPalette.paleBlue,
            ),
          ),
        ],
      ),
    );
  }
}

class _ArtworkCarousel extends StatelessWidget {
  const _ArtworkCarousel({required this.item, required this.nextItem});

  final MediaItem item;
  final MediaItem? nextItem;

  @override
  Widget build(BuildContext context) {
    final library = AppScope.of(context).libraryController;
    return LayoutBuilder(
      builder: (context, constraints) {
        if (nextItem == null) {
          final size = constraints.maxWidth.clamp(240.0, 430.0).toDouble();
          return Center(
            child: SizedBox.square(
              dimension: size,
              child: Hero(
                tag: 'artwork-${item.id}',
                child: MediaArtwork(
                  item: item,
                  libraryController: library,
                  borderRadius: 28,
                  iconSize: 76,
                ),
              ),
            ),
          );
        }

        const gap = 10.0;
        final previewWidth = (constraints.maxWidth * 0.17)
            .clamp(54.0, 82.0)
            .toDouble();
        final artworkSize = constraints.maxWidth - previewWidth - gap;
        return SizedBox(
          height: artworkSize,
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: <Widget>[
              Expanded(
                child: Hero(
                  tag: 'artwork-${item.id}',
                  child: MediaArtwork(
                    item: item,
                    libraryController: library,
                    borderRadius: 28,
                    iconSize: 76,
                  ),
                ),
              ),
              const SizedBox(width: gap),
              SizedBox(
                width: previewWidth,
                child: GestureDetector(
                  onTap: () => unawaited(
                    AppScope.of(context).playerController.open(nextItem!),
                  ),
                  child: MediaArtwork(
                    item: nextItem!,
                    libraryController: library,
                    borderRadius: 28,
                    iconSize: 40,
                  ),
                ),
              ),
            ],
          ),
        );
      },
    );
  }
}

class _TrackIdentity extends StatelessWidget {
  const _TrackIdentity({required this.item, required this.onDetails});

  final MediaItem item;
  final VoidCallback onDetails;

  @override
  Widget build(BuildContext context) {
    return Row(
      crossAxisAlignment: CrossAxisAlignment.center,
      children: <Widget>[
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: <Widget>[
              Text(
                item.title,
                maxLines: 2,
                overflow: TextOverflow.ellipsis,
                style: const TextStyle(
                  color: _PlayerPalette.text,
                  fontSize: 31,
                  height: 1.04,
                  fontWeight: FontWeight.w800,
                  letterSpacing: -0.8,
                ),
              ),
              const SizedBox(height: 8),
              Text(
                item.artist?.trim().isNotEmpty == true
                    ? item.artist!
                    : 'Telegram audio',
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: const TextStyle(
                  color: _PlayerPalette.secondaryText,
                  fontSize: 19,
                  fontWeight: FontWeight.w500,
                ),
              ),
            ],
          ),
        ),
        const SizedBox(width: 18),
        Tooltip(
          message: 'Song details',
          child: SizedBox.square(
            dimension: 58,
            child: Material(
              color: _PlayerPalette.headerSurface,
              shape: const CircleBorder(),
              clipBehavior: Clip.antiAlias,
              child: InkWell(
                onTap: onDetails,
                child: const Center(child: _SongDetailsGlyph()),
              ),
            ),
          ),
        ),
      ],
    );
  }
}

class _SongDetailsGlyph extends StatelessWidget {
  const _SongDetailsGlyph();

  @override
  Widget build(BuildContext context) {
    return const SizedBox.square(
      dimension: 32,
      child: Stack(
        children: <Widget>[
          Positioned(
            left: 2,
            top: 3,
            child: Icon(
              Icons.chat_bubble_outline_rounded,
              size: 27,
              color: _PlayerPalette.paleBlue,
            ),
          ),
          Positioned(
            right: 1,
            top: 6,
            child: Icon(
              Icons.music_note_rounded,
              size: 15,
              color: _PlayerPalette.paleBlue,
            ),
          ),
        ],
      ),
    );
  }
}

class _ProgressSection extends StatelessWidget {
  const _ProgressSection({required this.player, required this.item});

  final PlayerController player;
  final MediaItem item;

  @override
  Widget build(BuildContext context) {
    final duration = player.duration;
    final position = player.position > duration ? duration : player.position;
    final fraction = duration.inMilliseconds <= 0
        ? 0.0
        : (position.inMilliseconds / duration.inMilliseconds)
            .clamp(0.0, 1.0)
            .toDouble();

    return Column(
      children: <Widget>[
        _WaveSeekBar(
          value: fraction,
          enabled: duration > Duration.zero,
          onChanged: (value) => unawaited(player.seekToFraction(value)),
        ),
        const SizedBox(height: 10),
        Row(
          children: <Widget>[
            SizedBox(
              width: 62,
              child: Text(
                _formatTime(position),
                style: const TextStyle(
                  color: _PlayerPalette.text,
                  fontSize: 15,
                  fontWeight: FontWeight.w800,
                ),
              ),
            ),
            Expanded(
              child: Center(
                child: _MetadataPill(
                  text: player.isBuffering
                      ? 'Buffering'
                      : _audioMetadata(item),
                  buffering: player.isBuffering || player.isLoading,
                ),
              ),
            ),
            SizedBox(
              width: 62,
              child: Text(
                _formatTime(duration),
                textAlign: TextAlign.end,
                style: const TextStyle(
                  color: _PlayerPalette.text,
                  fontSize: 15,
                  fontWeight: FontWeight.w800,
                ),
              ),
            ),
          ],
        ),
      ],
    );
  }
}

class _WaveSeekBar extends StatelessWidget {
  const _WaveSeekBar({
    required this.value,
    required this.enabled,
    required this.onChanged,
  });

  final double value;
  final bool enabled;
  final ValueChanged<double> onChanged;

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      height: 38,
      child: LayoutBuilder(
        builder: (context, constraints) {
          void update(double dx) {
            if (!enabled || constraints.maxWidth <= 0) {
              return;
            }
            onChanged(
              (dx / constraints.maxWidth).clamp(0.0, 1.0).toDouble(),
            );
          }

          return GestureDetector(
            behavior: HitTestBehavior.opaque,
            onTapDown: (details) => update(details.localPosition.dx),
            onHorizontalDragUpdate: (details) => update(details.localPosition.dx),
            child: CustomPaint(
              painter: _WaveSeekPainter(value: value),
              size: Size(constraints.maxWidth, 38),
            ),
          );
        },
      ),
    );
  }
}

class _WaveSeekPainter extends CustomPainter {
  const _WaveSeekPainter({required this.value});

  final double value;

  @override
  void paint(Canvas canvas, Size size) {
    final centerY = size.height / 2;
    final progressX = (size.width * value.clamp(0.0, 1.0)).toDouble();
    const thumbRadius = 8.5;
    const waveAmplitude = 3.5;
    const wavelength = 42.0;

    final inactivePaint = Paint()
      ..color = _PlayerPalette.inactiveTrack
      ..strokeWidth = 5
      ..strokeCap = StrokeCap.round;
    final inactiveStart = math.min(size.width, progressX + 18).toDouble();
    if (inactiveStart < size.width - 2) {
      canvas.drawLine(
        Offset(inactiveStart, centerY),
        Offset(size.width - 2, centerY),
        inactivePaint,
      );
    }

    if (progressX > 0) {
      final activePaint = Paint()
        ..color = _PlayerPalette.text
        ..style = PaintingStyle.stroke
        ..strokeWidth = 6
        ..strokeCap = StrokeCap.round
        ..strokeJoin = StrokeJoin.round;
      final path = Path()..moveTo(0, centerY);
      for (double x = 1; x <= progressX; x += 2) {
        final y = centerY +
            math.sin((x / wavelength) * math.pi * 2) * waveAmplitude;
        path.lineTo(x, y);
      }
      canvas.drawPath(path, activePaint);
    }

    final thumbCenter = Offset(
      progressX.clamp(thumbRadius, size.width - thumbRadius).toDouble(),
      centerY,
    );
    canvas.drawCircle(
      thumbCenter,
      thumbRadius,
      Paint()..color = _PlayerPalette.text,
    );
  }

  @override
  bool shouldRepaint(covariant _WaveSeekPainter oldDelegate) {
    return oldDelegate.value != value;
  }
}

class _MetadataPill extends StatelessWidget {
  const _MetadataPill({required this.text, required this.buffering});

  final String text;
  final bool buffering;

  @override
  Widget build(BuildContext context) {
    return Container(
      constraints: const BoxConstraints(maxWidth: 260),
      padding: const EdgeInsets.symmetric(horizontal: 13, vertical: 5),
      decoration: BoxDecoration(
        color: _PlayerPalette.inactiveTrack.withValues(alpha: 0.76),
        borderRadius: BorderRadius.circular(20),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: <Widget>[
          if (buffering) ...<Widget>[
            const SizedBox.square(
              dimension: 12,
              child: CircularProgressIndicator(
                strokeWidth: 2,
                color: _PlayerPalette.text,
              ),
            ),
            const SizedBox(width: 7),
          ],
          Flexible(
            child: Text(
              text,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              textAlign: TextAlign.center,
              style: const TextStyle(
                color: _PlayerPalette.text,
                fontSize: 12,
                fontWeight: FontWeight.w700,
                letterSpacing: 0.1,
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _PrimaryControls extends StatelessWidget {
  const _PrimaryControls({required this.player});

  final PlayerController player;

  @override
  Widget build(BuildContext context) {
    final playing = player.isPlaying;
    return Row(
      children: <Widget>[
        Expanded(
          child: _MainControlButton(
            tooltip: 'Previous',
            icon: Icons.skip_previous_rounded,
            color: _PlayerPalette.paleBlue,
            onPressed: () => unawaited(player.playPrevious()),
          ),
        ),
        const SizedBox(width: 10),
        Expanded(
          child: _MainControlButton(
            tooltip: playing ? 'Pause' : 'Play',
            icon: playing ? Icons.pause_rounded : Icons.play_arrow_rounded,
            color: _PlayerPalette.lavender,
            onPressed: () => unawaited(player.togglePlay()),
          ),
        ),
        const SizedBox(width: 10),
        Expanded(
          child: _MainControlButton(
            tooltip: 'Next',
            icon: Icons.skip_next_rounded,
            color: _PlayerPalette.paleBlue,
            onPressed: () => unawaited(player.playNext()),
          ),
        ),
      ],
    );
  }
}

class _MainControlButton extends StatelessWidget {
  const _MainControlButton({
    required this.tooltip,
    required this.icon,
    required this.color,
    required this.onPressed,
  });

  final String tooltip;
  final IconData icon;
  final Color color;
  final VoidCallback onPressed;

  @override
  Widget build(BuildContext context) {
    return Tooltip(
      message: tooltip,
      child: SizedBox(
        height: 86,
        child: Material(
          color: color,
          borderRadius: BorderRadius.circular(32),
          clipBehavior: Clip.antiAlias,
          child: InkWell(
            onTap: onPressed,
            child: Center(
              child: Icon(icon, size: 34, color: _PlayerPalette.ink),
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
    return Container(
      height: 72,
      padding: const EdgeInsets.all(6),
      decoration: BoxDecoration(
        color: _PlayerPalette.darkSurface,
        borderRadius: BorderRadius.circular(40),
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
    return Tooltip(
      message: tooltip,
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 2),
        child: Material(
          color: selected ? _PlayerPalette.selected : Colors.transparent,
          borderRadius: BorderRadius.circular(31),
          clipBehavior: Clip.antiAlias,
          child: InkWell(
            onTap: onPressed,
            child: Center(
              child: Icon(
                icon,
                size: 30,
                color: selected ? _PlayerPalette.ink : _PlayerPalette.text,
              ),
            ),
          ),
        ),
      ),
    );
  }
}

class _DetailRow extends StatelessWidget {
  const _DetailRow({required this.label, required this.value});

  final String label;
  final String value;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 10),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: <Widget>[
          SizedBox(
            width: 78,
            child: Text(
              label,
              style: TextStyle(color: Theme.of(context).colorScheme.onSurfaceVariant),
            ),
          ),
          Expanded(child: Text(value)),
        ],
      ),
    );
  }
}

class _EmptyPlayer extends StatelessWidget {
  const _EmptyPlayer({required this.onClose});

  final VoidCallback onClose;

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(32),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: <Widget>[
            Container(
              width: 112,
              height: 112,
              decoration: const BoxDecoration(
                color: _PlayerPalette.headerSurface,
                shape: BoxShape.circle,
              ),
              child: const Icon(
                Icons.headphones_rounded,
                size: 64,
                color: _PlayerPalette.paleBlue,
              ),
            ),
            const SizedBox(height: 24),
            const Text(
              'Nothing playing',
              style: TextStyle(
                color: _PlayerPalette.text,
                fontSize: 27,
                fontWeight: FontWeight.w800,
              ),
            ),
            const SizedBox(height: 8),
            const Text(
              'Choose a song from your Telegram Library.',
              textAlign: TextAlign.center,
              style: TextStyle(
                color: _PlayerPalette.secondaryText,
                fontSize: 16,
              ),
            ),
            const SizedBox(height: 26),
            FilledButton.icon(
              style: FilledButton.styleFrom(
                backgroundColor: _PlayerPalette.paleBlue,
                foregroundColor: _PlayerPalette.ink,
              ),
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

String _audioMetadata(MediaItem item) {
  final durationSeconds = item.durationSeconds ?? 0;
  final estimatedBitrate = durationSeconds > 0 && item.size > 0
      ? ((item.size * 8) / durationSeconds / 1000).round()
      : null;
  final format = _audioFormat(item);
  if (estimatedBitrate != null && estimatedBitrate > 0) {
    return '${item.readableSize} · $estimatedBitrate kbps · $format';
  }
  return '${item.readableSize} · $format';
}

String _audioFormat(MediaItem item) {
  final mimeSubtype = item.mimeType.split('/').last.trim();
  if (mimeSubtype.isNotEmpty && mimeSubtype != 'octet-stream') {
    return mimeSubtype.toUpperCase();
  }
  final dot = item.fileName.lastIndexOf('.');
  if (dot >= 0 && dot < item.fileName.length - 1) {
    return item.fileName.substring(dot + 1).toUpperCase();
  }
  return 'AUDIO';
}

String _formatTime(Duration duration) {
  final safe = duration.isNegative ? Duration.zero : duration;
  final hours = safe.inHours;
  final minutes = safe.inMinutes.remainder(60).toString().padLeft(2, '0');
  final seconds = safe.inSeconds.remainder(60).toString().padLeft(2, '0');
  return hours > 0 ? '$hours:$minutes:$seconds' : '$minutes:$seconds';
}
