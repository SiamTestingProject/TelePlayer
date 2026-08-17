import 'dart:async';
import 'dart:math' as math;

import 'package:flutter/material.dart';

import '../../../app/app_scope.dart';
import '../../../app/error_panel.dart';
import '../../../core/utils/embedded_artwork.dart';
import '../../library/models/media_item.dart';
import '../../library/presentation/media_artwork.dart';
import '../application/player_controller.dart';

class PlayerScreen extends StatefulWidget {
  const PlayerScreen({required this.onClose, super.key});

  final VoidCallback onClose;

  @override
  State<PlayerScreen> createState() => _PlayerScreenState();
}

class _PlayerScreenState extends State<PlayerScreen>
    with SingleTickerProviderStateMixin {
  static const double _dismissDistanceFraction = 0.18;
  static const double _dismissVelocity = 720;
  static const Duration _snapBackDuration = Duration(milliseconds: 280);
  static const Duration _dismissDuration = Duration(milliseconds: 300);

  late final AnimationController _verticalController;
  Animation<double>? _verticalAnimation;
  double _verticalOffset = 0;
  double _viewportHeight = 1;
  bool _dismissInProgress = false;

  @override
  void initState() {
    super.initState();
    _verticalController = AnimationController(vsync: this)
      ..addListener(_tickVerticalAnimation);
  }

  @override
  void dispose() {
    _verticalController
      ..removeListener(_tickVerticalAnimation)
      ..dispose();
    super.dispose();
  }

  void _tickVerticalAnimation() {
    final animation = _verticalAnimation;
    if (!mounted || animation == null) {
      return;
    }
    setState(() => _verticalOffset = animation.value);
  }

  void _handleVerticalDragStart(DragStartDetails _) {
    if (_dismissInProgress) {
      return;
    }
    _verticalController.stop();
    _verticalAnimation = null;
  }

  void _handleVerticalDragUpdate(DragUpdateDetails details) {
    if (_dismissInProgress) {
      return;
    }
    final delta = details.primaryDelta ?? details.delta.dy;
    var nextOffset = _verticalOffset + delta;
    if (nextOffset < 0) {
      // Upward movement should not scroll the fixed Now Playing page. A small
      // resistance keeps the gesture feeling physical without exposing empty
      // space above the player.
      nextOffset *= 0.08;
    }
    nextOffset = nextOffset.clamp(0.0, _viewportHeight + 80).toDouble();
    if ((nextOffset - _verticalOffset).abs() < 0.1) {
      return;
    }
    setState(() => _verticalOffset = nextOffset);
  }

  void _handleVerticalDragCancel() {
    if (_dismissInProgress) {
      return;
    }
    unawaited(_animateVerticalOffset(0, duration: _snapBackDuration));
  }

  void _handleVerticalDragEnd(DragEndDetails details) {
    if (_dismissInProgress) {
      return;
    }
    final velocity = details.primaryVelocity ?? 0;
    final shouldDismiss =
        _verticalOffset >= _viewportHeight * _dismissDistanceFraction ||
        velocity >= _dismissVelocity;
    if (shouldDismiss) {
      unawaited(_dismissPlayer());
    } else {
      unawaited(_animateVerticalOffset(0, duration: _snapBackDuration));
    }
  }

  Future<void> _animateVerticalOffset(
    double target, {
    required Duration duration,
    Curve curve = Curves.easeOutCubic,
  }) async {
    if (!mounted) {
      return;
    }
    _verticalController.stop();
    _verticalController.duration = duration;
    _verticalAnimation = Tween<double>(
      begin: _verticalOffset,
      end: target,
    ).animate(
      CurvedAnimation(
        parent: _verticalController,
        curve: curve,
      ),
    );
    try {
      await _verticalController.forward(from: 0).orCancel;
    } on TickerCanceled {
      return;
    }
  }

  Future<void> _dismissPlayer() async {
    if (_dismissInProgress || !mounted) {
      return;
    }
    setState(() {
      _dismissInProgress = true;
    });
    // Reveal the previous app page immediately, then let this surface finish
    // sliding over it. AnimatedSwitcher keeps the outgoing player mounted for
    // long enough to complete this local transition.
    widget.onClose();
    await _animateVerticalOffset(
      _viewportHeight + 72,
      duration: _dismissDuration,
      curve: Curves.easeOutCubic,
    );
  }

  @override
  Widget build(BuildContext context) {
    final scope = AppScope.of(context);
    final player = scope.playerController;
    final item = player.item;
    final backdrop = Theme.of(context).colorScheme.surface;

    return LayoutBuilder(
      builder: (context, viewportConstraints) {
        _viewportHeight = math.max(1.0, viewportConstraints.maxHeight);
        final progress = (_verticalOffset / _viewportHeight).clamp(0.0, 1.0).toDouble();
        final scale = 1 - (progress * 0.018);
        final radius = 34 * progress;

        return ColoredBox(
          color: Color.lerp(_PlayerPalette.background, backdrop, 0.78)!,
          child: GestureDetector(
            behavior: HitTestBehavior.translucent,
            onVerticalDragStart: _handleVerticalDragStart,
            onVerticalDragUpdate: _handleVerticalDragUpdate,
            onVerticalDragEnd: _handleVerticalDragEnd,
            onVerticalDragCancel: _handleVerticalDragCancel,
            child: Transform.translate(
              offset: Offset(0, _verticalOffset),
              child: Transform.scale(
                scale: scale,
                alignment: Alignment.topCenter,
                child: ClipRRect(
                  borderRadius: BorderRadius.vertical(
                    top: Radius.circular(radius),
                  ),
                  child: DecoratedBox(
                    decoration: BoxDecoration(
                      boxShadow: progress == 0
                          ? const <BoxShadow>[]
                          : <BoxShadow>[
                              BoxShadow(
                                color: Colors.black.withValues(
                                  alpha: 0.22 * progress,
                                ),
                                blurRadius: 26,
                                offset: const Offset(0, -8),
                              ),
                            ],
                    ),
                    child: Scaffold(
                      backgroundColor: _PlayerPalette.background,
                      body: ColoredBox(
                        color: _PlayerPalette.background,
                        child: SafeArea(
                          child: item == null
                              ? _EmptyPlayer(
                                  onClose: () => unawaited(_dismissPlayer()),
                                )
                              : LayoutBuilder(
                                  builder: (context, constraints) {
                                    // The Now Playing surface remains a fixed,
                                    // non-scrollable player. A downward swipe
                                    // moves the whole surface instead of
                                    // scrolling its internal content.
                                    final canvasWidth = math.min(
                                      588.0,
                                      math.max(320.0, constraints.maxWidth),
                                    );
                                    final items = scope.libraryController.items;
                                    return SizedBox.expand(
                                      child: FittedBox(
                                        fit: BoxFit.scaleDown,
                                        alignment: Alignment.topCenter,
                                        child: SizedBox(
                                          width: canvasWidth,
                                          child: Padding(
                                            padding: const EdgeInsets.fromLTRB(
                                              24,
                                              10,
                                              24,
                                              18,
                                            ),
                                            child: Column(
                                              crossAxisAlignment:
                                                  CrossAxisAlignment.stretch,
                                              mainAxisSize: MainAxisSize.min,
                                              children: <Widget>[
                                                _PlayerHeader(
                                                  onClose: () => unawaited(
                                                    _dismissPlayer(),
                                                  ),
                                                  onQueue: () =>
                                                      _showQueue(context),
                                                ),
                                                const SizedBox(height: 28),
                                                _ArtworkCarousel(
                                                  item: item,
                                                  nextItem: _adjacentLibraryItem(
                                                    item,
                                                    items,
                                                    1,
                                                  ),
                                                  previousItem:
                                                      _adjacentLibraryItem(
                                                    item,
                                                    items,
                                                    -1,
                                                  ),
                                                ),
                                                const SizedBox(height: 44),
                                                _TrackIdentity(
                                                  item: item,
                                                  onDetails: () =>
                                                      _showSongDetails(
                                                    context,
                                                    item,
                                                  ),
                                                ),
                                                const SizedBox(height: 24),
                                                if (player.error != null) ...<Widget>[
                                                  Theme(
                                                    data: Theme.of(context)
                                                        .copyWith(
                                                      colorScheme:
                                                          Theme.of(context)
                                                              .colorScheme
                                                              .copyWith(
                                                        surface: _PlayerPalette
                                                            .darkSurface,
                                                        onSurface:
                                                            _PlayerPalette.text,
                                                        onSurfaceVariant:
                                                            _PlayerPalette
                                                                .secondaryText,
                                                      ),
                                                    ),
                                                    child: ErrorPanel(
                                                      error: player.error!,
                                                      onAction: () => unawaited(
                                                        player.open(item),
                                                      ),
                                                    ),
                                                  ),
                                                  const SizedBox(height: 16),
                                                ],
                                                _ProgressSection(
                                                  player: player,
                                                  item: item,
                                                ),
                                                const SizedBox(height: 48),
                                                _PrimaryControls(player: player),
                                                const SizedBox(height: 18),
                                                Padding(
                                                  padding: const EdgeInsets.symmetric(
                                                    horizontal: 26,
                                                  ),
                                                  child: _PlaybackModes(
                                                    player: player,
                                                  ),
                                                ),
                                              ],
                                            ),
                                          ),
                                        ),
                                      ),
                                    );
                                  },
                                ),
                        ),
                      ),
                    ),
                  ),
                ),
              ),
            ),
          ),
        );
      },
    );
  }

  MediaItem? _adjacentLibraryItem(
    MediaItem current,
    List<MediaItem> items,
    int direction,
  ) {
    final audioItems = items
        .where((candidate) => candidate.kind == MediaKind.audio)
        .toList(growable: false);
    if (audioItems.length < 2) {
      return null;
    }
    final currentIndex =
        audioItems.indexWhere((candidate) => candidate.id == current.id);
    if (currentIndex < 0) {
      return audioItems.first;
    }
    final rawIndex = (currentIndex + direction) % audioItems.length;
    final index = rawIndex < 0 ? rawIndex + audioItems.length : rawIndex;
    return audioItems[index];
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
    required this.onQueue,
  });

  final VoidCallback onClose;
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
            size: 24,
            color: _PlayerPalette.paleBlue,
          ),
        ),
        const SizedBox(width: 16),
        const Expanded(
          child: Text(
            'Now Playing',
            style: TextStyle(
              color: _PlayerPalette.text,
              fontSize: 18,
              height: 1,
              fontWeight: FontWeight.w800,
              letterSpacing: -0.3,
            ),
          ),
        ),
        _HeaderButton(
          tooltip: 'Playback queue',
          onPressed: onQueue,
          child: const Icon(
            Icons.queue_music_rounded,
            size: 24,
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
      child: SizedBox(
        width: circular ? 44 : 52,
        height: 44,
        child: Material(
          color: _PlayerPalette.headerSurface,
          shape: circular
              ? const CircleBorder()
              : RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
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

class _ArtworkCarousel extends StatefulWidget {
  const _ArtworkCarousel({
    required this.item,
    required this.nextItem,
    required this.previousItem,
  });

  final MediaItem item;
  final MediaItem? nextItem;
  final MediaItem? previousItem;

  @override
  State<_ArtworkCarousel> createState() => _ArtworkCarouselState();
}

class _ArtworkCarouselState extends State<_ArtworkCarousel>
    with SingleTickerProviderStateMixin {
  static const double _velocityThreshold = 520;
  static const Duration _settleDuration = Duration(milliseconds: 360);

  late final AnimationController _settleController;
  late MediaItem _displayedItem;
  MediaItem? _displayedNext;
  MediaItem? _displayedPrevious;
  MediaItem? _transitionItem;
  double _transitionDirection = -1;
  String? _pendingSwipeKey;
  Animation<double>? _offsetAnimation;
  double _dragOffset = 0;
  double _travel = 1;
  int _animationGeneration = 0;

  @override
  void initState() {
    super.initState();
    _displayedItem = widget.item;
    _displayedNext = widget.nextItem;
    _displayedPrevious = widget.previousItem;
    _settleController = AnimationController(
      vsync: this,
      duration: _settleDuration,
    )..addListener(() {
        final animation = _offsetAnimation;
        if (animation == null || !mounted) {
          return;
        }
        setState(() => _dragOffset = animation.value);
      });
    _schedulePrefetchVisibleArtwork();
  }

  @override
  void didUpdateWidget(covariant _ArtworkCarousel oldWidget) {
    super.didUpdateWidget(oldWidget);
    _schedulePrefetchVisibleArtwork();

    if (widget.item.messageKey == _displayedItem.messageKey) {
      _displayedNext = widget.nextItem;
      _displayedPrevious = widget.previousItem;
      return;
    }

    if (_pendingSwipeKey == widget.item.messageKey) {
      // The swipe animation has already moved this cover fully into place.
      // Adopt the controller's new item without a second jump/animation.
      _animationGeneration++;
      _settleController.stop();
      _offsetAnimation = null;
      _transitionItem = null;
      _pendingSwipeKey = null;
      _dragOffset = 0;
      _displayedItem = widget.item;
      _displayedNext = widget.nextItem;
      _displayedPrevious = widget.previousItem;
      return;
    }

    // PlayerController notifies several times while a new source is opening
    // (loading, buffering, metadata, playback state). Those rebuilds can carry
    // the same new MediaItem. Never restart the artwork animation for the same
    // target: repeatedly resetting the controller made the cover shoot forward
    // and snap back when Previous/Next was pressed.
    if (_transitionItem?.messageKey == widget.item.messageKey) {
      return;
    }

    // A genuinely newer external selection supersedes an older unfinished
    // transition. Reset once, then animate only the latest requested cover.
    if (_transitionItem != null || _settleController.isAnimating) {
      _animationGeneration++;
      _settleController.stop();
      _offsetAnimation = null;
      _dragOffset = 0;
      _transitionItem = null;
    }

    // Previous/next buttons and queue selection update PlayerController before
    // this widget is rebuilt. Keep the old artwork on screen and carousel it
    // toward the new one rather than replacing it abruptly.
    final direction = widget.item.messageKey == _displayedPrevious?.messageKey
        ? 1.0
        : -1.0;
    final targetKey = widget.item.messageKey;
    _transitionItem = widget.item;
    _transitionDirection = direction;
    unawaited(_prefetchArtwork(widget.item));
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted ||
          widget.item.messageKey != targetKey ||
          _displayedItem.messageKey == targetKey ||
          _transitionItem?.messageKey != targetKey) {
        return;
      }
      unawaited(_animateExternalSwitch(targetKey, direction));
    });
  }

  Future<void> _prefetchArtwork(MediaItem? item) async {
    if (item == null || !mounted) {
      return;
    }
    try {
      await AppScope.of(context).libraryController.thumbnailFor(
            item,
            highQuality: true,
          );
    } catch (_) {
      // Artwork is optional. MediaArtwork will retry independently if a
      // Telegram thumbnail was temporarily unavailable.
    }
  }

  void _schedulePrefetchVisibleArtwork() {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) {
        _prefetchVisibleArtwork();
      }
    });
  }

  void _prefetchVisibleArtwork() {
    unawaited(_prefetchArtwork(widget.item));
    unawaited(_prefetchArtwork(widget.nextItem));
    unawaited(_prefetchArtwork(widget.previousItem));
  }

  void _updateDrag(DragUpdateDetails details) {
    final player = AppScope.of(context).playerController;
    if (player.isLoading ||
        _transitionItem != null ||
        _settleController.isAnimating) {
      return;
    }
    final nextOffset = (_dragOffset + details.delta.dx)
        .clamp(-_travel, _travel)
        .toDouble();
    // Do not let the user drag into an empty side of the queue.
    if (nextOffset < 0 && _displayedNext == null) {
      return;
    }
    if (nextOffset > 0 && _displayedPrevious == null) {
      return;
    }
    final target = nextOffset < 0 ? _displayedNext : _displayedPrevious;
    if (target != null) {
      unawaited(player.prepareForTransition(target));
    }
    setState(() => _dragOffset = nextOffset);
  }

  Future<void> _finishDrag(DragEndDetails details) async {
    final player = AppScope.of(context).playerController;
    if (player.isLoading ||
        _transitionItem != null ||
        _settleController.isAnimating) {
      return;
    }
    final velocity = details.primaryVelocity ?? 0;
    final crossedDistance = _dragOffset.abs() >= _travel * 0.17;
    final crossedVelocity = velocity.abs() >= _velocityThreshold;
    final direction = crossedVelocity ? velocity.sign : _dragOffset.sign;
    final target = direction < 0 ? _displayedNext : _displayedPrevious;

    if ((!crossedDistance && !crossedVelocity) || target == null) {
      await _animateOffset(_dragOffset, 0);
      return;
    }

    // Complete the visual movement first. This makes the narrow preview become
    // the full-size cover with no snap, then PlayerController changes tracks.
    final destination = direction < 0 ? -_travel : _travel;
    final targetKey = target.messageKey;
    _pendingSwipeKey = targetKey;
    unawaited(player.prepareForTransition(target));
    await _animateOffset(_dragOffset, destination);
    if (!mounted || _pendingSwipeKey != targetKey) {
      return;
    }
    unawaited(player.open(target));
  }

  Future<void> _animateExternalSwitch(
    String targetKey,
    double direction,
  ) async {
    final target = _transitionItem;
    if (target == null || target.messageKey != targetKey) {
      return;
    }
    final generation = ++_animationGeneration;
    final destination = direction < 0 ? -_travel : _travel;
    await _animateOffset(0, destination);
    if (!mounted ||
        generation != _animationGeneration ||
        widget.item.messageKey != targetKey ||
        _transitionItem?.messageKey != targetKey) {
      return;
    }
    setState(() {
      _displayedItem = target;
      _displayedNext = widget.nextItem;
      _displayedPrevious = widget.previousItem;
      _transitionItem = null;
      _dragOffset = 0;
      _offsetAnimation = null;
    });
  }

  Future<void> _animateOffset(double from, double to) async {
    _settleController.stop();
    _settleController.reset();
    _offsetAnimation = Tween<double>(begin: from, end: to).animate(
      CurvedAnimation(
        parent: _settleController,
        curve: Curves.easeOutCubic,
      ),
    );
    try {
      await _settleController.forward().orCancel;
    } on TickerCanceled {
      // A newer track change superseded this animation.
    }
  }

  void _cancelDrag() {
    if (_settleController.isAnimating || _transitionItem != null) {
      return;
    }
    unawaited(_animateOffset(_dragOffset, 0));
  }

  @override
  void dispose() {
    _animationGeneration++;
    _settleController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final library = AppScope.of(context).libraryController;
    return LayoutBuilder(
      builder: (context, constraints) {
        const gap = 10.0;
        final hasPreview = _displayedNext != null || _transitionItem != null;
        final previewWidth = hasPreview
            ? (constraints.maxWidth * 0.17).clamp(54.0, 82.0).toDouble()
            : 0.0;
        final artworkSize = hasPreview
            ? constraints.maxWidth - previewWidth - gap
            : constraints.maxWidth.clamp(240.0, 430.0).toDouble();
        _travel = artworkSize + gap;

        MediaItem? rightItem;
        MediaItem? leftItem;
        if (_transitionItem != null) {
          if (_transitionDirection > 0) {
            leftItem = _transitionItem;
          } else {
            rightItem = _transitionItem;
          }
        } else {
          rightItem = _displayedNext;
          leftItem = _displayedPrevious;
        }

        Widget artwork(MediaItem item) => SizedBox.square(
              dimension: artworkSize,
              child: MediaArtwork(
                key: ValueKey<String>('player-art-${item.messageKey}'),
                item: item,
                libraryController: library,
                borderRadius: 28,
                iconSize: 76,
                highQuality: true,
              ),
            );

        return GestureDetector(
          behavior: HitTestBehavior.opaque,
          onHorizontalDragUpdate: _updateDrag,
          onHorizontalDragEnd: _finishDrag,
          onHorizontalDragCancel: _cancelDrag,
          child: ClipRect(
            child: SizedBox(
              width: constraints.maxWidth,
              height: artworkSize,
              child: Stack(
                clipBehavior: Clip.hardEdge,
                children: <Widget>[
                  if (leftItem != null)
                    Positioned(
                      left: -_travel + _dragOffset,
                      top: 0,
                      child: artwork(leftItem),
                    ),
                  Positioned(
                    left: _dragOffset,
                    top: 0,
                    child: artwork(_displayedItem),
                  ),
                  if (rightItem != null)
                    Positioned(
                      left: _travel + _dragOffset,
                      top: 0,
                      child: artwork(rightItem),
                    ),
                ],
              ),
            ),
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
                  fontSize: 26,
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
            dimension: 48,
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
      dimension: 27,
      child: Stack(
        children: <Widget>[
          Positioned(
            left: 2,
            top: 3,
            child: Icon(
              Icons.chat_bubble_outline_rounded,
              size: 23,
              color: _PlayerPalette.paleBlue,
            ),
          ),
          Positioned(
            right: 1,
            top: 6,
            child: Icon(
              Icons.music_note_rounded,
              size: 13,
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
          animate: player.isPlaying && !player.isBuffering,
          onChanged: (value) => unawaited(player.seekToFraction(value)),
        ),
        const SizedBox(height: 8),
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
                child: FutureBuilder<AudioTechnicalMetadata?>(
                  future: AppScope.of(context)
                      .libraryController
                      .technicalMetadataFor(item),
                  builder: (context, snapshot) {
                    return _MetadataPill(
                      text: player.isBuffering
                          ? 'Buffering'
                          : _audioMetadata(item, snapshot.data),
                      buffering: player.isBuffering || player.isLoading,
                    );
                  },
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

class _WaveSeekBar extends StatefulWidget {
  const _WaveSeekBar({
    required this.value,
    required this.enabled,
    required this.animate,
    required this.onChanged,
  });

  final double value;
  final bool enabled;
  final bool animate;
  final ValueChanged<double> onChanged;

  @override
  State<_WaveSeekBar> createState() => _WaveSeekBarState();
}

class _WaveSeekBarState extends State<_WaveSeekBar>
    with SingleTickerProviderStateMixin {
  late final AnimationController _waveController;

  @override
  void initState() {
    super.initState();
    _waveController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 1150),
    );
    _syncWaveAnimation();
  }

  @override
  void didUpdateWidget(covariant _WaveSeekBar oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.animate != widget.animate ||
        oldWidget.enabled != widget.enabled) {
      _syncWaveAnimation();
    }
  }

  void _syncWaveAnimation() {
    if (widget.animate && widget.enabled) {
      if (!_waveController.isAnimating) {
        _waveController.repeat();
      }
    } else {
      _waveController.stop();
    }
  }

  @override
  void dispose() {
    _waveController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      height: 32,
      child: LayoutBuilder(
        builder: (context, constraints) {
          void update(double dx) {
            if (!widget.enabled || constraints.maxWidth <= 0) {
              return;
            }
            widget.onChanged(
              (dx / constraints.maxWidth).clamp(0.0, 1.0).toDouble(),
            );
          }

          return GestureDetector(
            behavior: HitTestBehavior.opaque,
            onTapDown: (details) => update(details.localPosition.dx),
            onHorizontalDragUpdate: (details) =>
                update(details.localPosition.dx),
            child: AnimatedBuilder(
              animation: _waveController,
              builder: (context, _) {
                return CustomPaint(
                  painter: _WaveSeekPainter(
                    value: widget.value,
                    phase: _waveController.value,
                  ),
                  size: Size(constraints.maxWidth, 32),
                );
              },
            ),
          );
        },
      ),
    );
  }
}

class _WaveSeekPainter extends CustomPainter {
  const _WaveSeekPainter({required this.value, required this.phase});

  final double value;
  final double phase;

  @override
  void paint(Canvas canvas, Size size) {
    if (size.width <= 0 || size.height <= 0) {
      return;
    }

    final centerY = size.height / 2;
    final clampedValue = value.clamp(0.0, 1.0).toDouble();
    final progressX = size.width * clampedValue;
    const thumbRadius = 8.5;
    const waveAmplitude = 4.2;
    const wavelength = 30.0;
    const sampleStep = 1.5;
    final phaseRadians = phase * math.pi * 2;

    final inactivePaint = Paint()
      ..color = _PlayerPalette.inactiveTrack
      ..strokeWidth = 5
      ..strokeCap = StrokeCap.round;
    final inactiveStart = math.min(
      size.width,
      progressX + thumbRadius + 6,
    ).toDouble();
    if (inactiveStart < size.width - 2) {
      canvas.drawLine(
        Offset(inactiveStart, centerY),
        Offset(size.width - 2, centerY),
        inactivePaint,
      );
    }

    if (progressX > 1) {
      final activePaint = Paint()
        ..color = _PlayerPalette.text
        ..style = PaintingStyle.stroke
        ..strokeWidth = 5.5
        ..strokeCap = StrokeCap.round
        ..strokeJoin = StrokeJoin.round
        ..isAntiAlias = true;
      final path = Path();
      var x = 0.0;
      var first = true;
      while (x <= progressX) {
        final edgeEnvelope = progressX < 36
            ? (progressX == 0
                  ? 0.0
                  : (x / progressX).clamp(0.0, 1.0).toDouble())
            : 1.0;
        final y = centerY +
            math.sin((x / wavelength) * math.pi * 2 - phaseRadians) *
                waveAmplitude *
                edgeEnvelope;
        if (first) {
          path.moveTo(x, y);
          first = false;
        } else {
          path.lineTo(x, y);
        }
        x += sampleStep;
      }
      // Land exactly beneath the thumb so the wave does not visually break
      // when the sample step does not divide the progress width.
      final endY = centerY +
          math.sin((progressX / wavelength) * math.pi * 2 - phaseRadians) *
              waveAmplitude;
      path.lineTo(progressX, endY);
      canvas.drawPath(path, activePaint);
    }

    final thumbX = progressX
        .clamp(thumbRadius, math.max(thumbRadius, size.width - thumbRadius))
        .toDouble();
    canvas.drawCircle(
      Offset(thumbX, centerY),
      thumbRadius,
      Paint()
        ..color = _PlayerPalette.text
        ..isAntiAlias = true,
    );
  }

  @override
  bool shouldRepaint(covariant _WaveSeekPainter oldDelegate) {
    return oldDelegate.value != value || oldDelegate.phase != phase;
  }
}

class _MetadataPill extends StatelessWidget {
  const _MetadataPill({required this.text, required this.buffering});

  final String text;
  final bool buffering;

  @override
  Widget build(BuildContext context) {
    return Container(
      constraints: const BoxConstraints(maxWidth: 240),
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 3),
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
                fontSize: 11,
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
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 12),
      child: Row(
        children: <Widget>[
          Expanded(
          child: _MainControlButton(
            tooltip: 'Previous',
            icon: Icons.skip_previous_rounded,
            color: _PlayerPalette.paleBlue,
            onPressed: () => unawaited(player.playPrevious()),
          ),
        ),
        const SizedBox(width: 6),
        Expanded(
          child: _MainControlButton(
            tooltip: playing ? 'Pause' : 'Play',
            icon: playing ? Icons.pause_rounded : Icons.play_arrow_rounded,
            color: _PlayerPalette.lavender,
            onPressed: () => unawaited(player.togglePlay()),
          ),
        ),
        const SizedBox(width: 6),
        Expanded(
          child: _MainControlButton(
            tooltip: 'Next',
            icon: Icons.skip_next_rounded,
            color: _PlayerPalette.paleBlue,
            onPressed: () => unawaited(player.playNext()),
          ),
          ),
        ],
      ),
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
        height: 80,
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
      height: 84,
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
                size: 26,
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

String _audioMetadata(
  MediaItem item,
  AudioTechnicalMetadata? technicalMetadata,
) {
  final durationSeconds = item.durationSeconds ?? 0;
  final estimatedBitrate = durationSeconds > 0 && item.size > 0
      ? ((item.size * 8) / durationSeconds / 1000).round()
      : null;
  final format = _audioFormat(item);
  final sampleRate = technicalMetadata?.sampleRateHz;
  final leading = sampleRate != null && sampleRate > 0
      ? _formatSampleRate(sampleRate)
      : item.readableSize;
  if (estimatedBitrate != null && estimatedBitrate > 0) {
    return '$leading · $estimatedBitrate kbps · $format';
  }
  return '$leading · $format';
}

String _formatSampleRate(int sampleRateHz) {
  if (sampleRateHz % 1000 == 0) {
    return '${sampleRateHz ~/ 1000} kHz';
  }
  final khz = sampleRateHz / 1000;
  return '${khz.toStringAsFixed(1)} kHz';
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
