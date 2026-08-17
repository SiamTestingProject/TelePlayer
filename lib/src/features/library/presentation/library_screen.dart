import 'dart:async';
import 'dart:math' as math;

import 'package:flutter/material.dart';

import '../../../app/app_scope.dart';
import '../../../app/error_panel.dart';
import '../models/channel_cache_progress.dart';
import '../models/media_item.dart';
import 'media_artwork.dart';

enum _LibrarySection { songs, albums, artists, playlists, liked, folders }
enum _SongAction { play, favorite }

class LibraryScreen extends StatefulWidget {
  const LibraryScreen({required this.onOpenPlayer, super.key});

  final VoidCallback onOpenPlayer;

  @override
  State<LibraryScreen> createState() => _LibraryScreenState();
}

class _LibraryScreenState extends State<LibraryScreen> {
  bool _requestedInitialLoad = false;
  MediaSortOrder _sortOrder = MediaSortOrder.newest;
  _LibrarySection _section = _LibrarySection.songs;
  _LibraryGroup? _openGroup;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (_requestedInitialLoad) {
      return;
    }
    _requestedInitialLoad = true;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) {
        unawaited(AppScope.of(context).libraryController.load());
      }
    });
  }

  @override
  Widget build(BuildContext context) {
    final scope = AppScope.of(context);
    final library = scope.libraryController;
    final songs = _sorted(library.items.where((e) => e.kind == MediaKind.audio));
    final colors = Theme.of(context).colorScheme;

    return Scaffold(
      backgroundColor: colors.surface,
      body: SafeArea(
        child: RefreshIndicator(
          onRefresh: library.load,
          child: CustomScrollView(
            physics: const AlwaysScrollableScrollPhysics(),
            slivers: <Widget>[
              SliverToBoxAdapter(
                child: Padding(
                  padding: const EdgeInsets.fromLTRB(22, 18, 18, 12),
                  child: Row(
                    children: <Widget>[
                      Expanded(
                        child: Text(
                          'Library',
                          style: Theme.of(context).textTheme.displaySmall?.copyWith(
                                fontWeight: FontWeight.w900,
                                letterSpacing: -0.8,
                              ),
                        ),
                      ),
                      IconButton.filledTonal(
                        tooltip: 'Cache new songs and album artwork',
                        onPressed: library.isCaching
                            ? null
                            : () => unawaited(_cacheAll(scope)),
                        icon: library.isCaching
                            ? const SizedBox.square(
                                dimension: 20,
                                child: CircularProgressIndicator(strokeWidth: 2.5),
                              )
                            : const Icon(Icons.download_for_offline_rounded),
                      ),
                    ],
                  ),
                ),
              ),
              SliverToBoxAdapter(
                child: _SectionBar(
                  selected: _section,
                  onChanged: (value) => setState(() {
                    _section = value;
                    _openGroup = null;
                  }),
                ),
              ),
              if (library.isCaching && library.cacheProgress != null)
                SliverToBoxAdapter(
                  child: Padding(
                    padding: const EdgeInsets.fromLTRB(18, 0, 18, 12),
                    child: _ChannelCacheBanner(progress: library.cacheProgress!),
                  ),
                ),
              if (_openGroup != null ||
                  _section == _LibrarySection.songs ||
                  _section == _LibrarySection.liked)
                SliverToBoxAdapter(
                  child: Padding(
                    padding: const EdgeInsets.fromLTRB(18, 2, 18, 14),
                    child: _SortBar(
                      sortOrder: _sortOrder,
                      onSortChanged: (value) =>
                          setState(() => _sortOrder = value),
                    ),
                  ),
                ),
              if (_openGroup != null)
                SliverToBoxAdapter(
                  child: Padding(
                    padding: const EdgeInsets.fromLTRB(18, 0, 18, 12),
                    child: _GroupHeader(
                      title: _openGroup!.title,
                      count: _openGroup!.items.length,
                      onBack: () => setState(() => _openGroup = null),
                    ),
                  ),
                ),
              if (library.error != null)
                SliverPadding(
                  padding: const EdgeInsets.fromLTRB(18, 0, 18, 12),
                  sliver: SliverToBoxAdapter(
                    child: ErrorPanel(
                      error: library.error!,
                      onAction: () => unawaited(library.load()),
                    ),
                  ),
                ),
              if (library.isLoading)
                const SliverToBoxAdapter(child: LinearProgressIndicator()),
              if (!library.isLoading) ..._bodySlivers(scope, songs),
            ],
          ),
        ),
      ),
    );
  }

  List<Widget> _bodySlivers(AppScope scope, List<MediaItem> songs) {
    if (_openGroup != null) {
      return _songSlivers(scope, _sorted(_openGroup!.items));
    }

    switch (_section) {
      case _LibrarySection.songs:
        return _songSlivers(scope, songs);
      case _LibrarySection.liked:
        return _songSlivers(
          scope,
          songs.where(scope.playerController.isFavoriteItem).toList(growable: false),
          emptyTitle: 'No liked songs yet',
          emptyBody: 'Use the heart button or a song menu to add songs here.',
        );
      case _LibrarySection.albums:
        return _groupSlivers(
          _groups(
            songs,
            keyFor: (item) => _clean(item.album)?.toLowerCase() ?? '__unknown__',
            titleFor: (item) => _clean(item.album) ?? 'Singles & unknown albums',
            subtitleFor: (items) {
              final artists = items
                  .map((item) => _clean(item.artist))
                  .whereType<String>()
                  .toSet();
              return artists.length == 1 ? artists.first : '${items.length} songs';
            },
          ),
          'No albums found',
          'Album metadata has not been found for these songs yet.',
        );
      case _LibrarySection.artists:
        return _groupSlivers(
          _groups(
            songs,
            keyFor: (item) => _clean(item.artist)?.toLowerCase() ?? '__unknown__',
            titleFor: (item) => _clean(item.artist) ?? 'Unknown artist',
            subtitleFor: (items) =>
                '${items.length} ${items.length == 1 ? 'song' : 'songs'}',
          ),
          'No artists found',
          'Artist metadata has not been found for these songs yet.',
        );
      case _LibrarySection.folders:
        return _groupSlivers(
          _groups(
            songs,
            keyFor: (item) => item.chatId.toString(),
            titleFor: (item) => _clean(item.sourceName) ?? 'Telegram ${item.chatId}',
            subtitleFor: (items) =>
                '${items.length} ${items.length == 1 ? 'song' : 'songs'}',
          ),
          'No folders found',
          'Telegram source folders will appear here.',
        );
      case _LibrarySection.playlists:
        final newest = songs.toList(growable: true)
          ..sort((a, b) => b.dateEpochSeconds.compareTo(a.dateEpochSeconds));
        final liked = songs
            .where(scope.playerController.isFavoriteItem)
            .toList(growable: false);
        final groups = songs.isEmpty
            ? const <_LibraryGroup>[]
            : <_LibraryGroup>[
                _LibraryGroup(
                  key: 'all',
                  title: 'All Songs',
                  subtitle: '${songs.length} songs',
                  items: songs,
                ),
                _LibraryGroup(
                  key: 'recent',
                  title: 'Recently Added',
                  subtitle: '${math.min(50, newest.length)} songs',
                  items: newest.take(50).toList(growable: false),
                ),
                if (liked.isNotEmpty)
                  _LibraryGroup(
                    key: 'liked',
                    title: 'Liked Songs',
                    subtitle: '${liked.length} songs',
                    items: liked,
                  ),
              ];
        return _groupSlivers(
          groups,
          'No playlists yet',
          'Smart playlists will appear as your Library grows.',
        );
    }
  }

  List<Widget> _songSlivers(
    AppScope scope,
    List<MediaItem> songs, {
    String emptyTitle = 'No songs found',
    String emptyBody = 'No Telegram audio matched this Library.',
  }) {
    if (songs.isEmpty) {
      return <Widget>[
        SliverFillRemaining(
          hasScrollBody: false,
          child: _EmptyLibrary(title: emptyTitle, body: emptyBody),
        ),
      ];
    }

    return <Widget>[
      SliverPadding(
        padding: const EdgeInsets.fromLTRB(18, 0, 18, 28),
        sliver: SliverList(
          delegate: SliverChildBuilderDelegate(
            (context, index) {
              final item = songs[index];
              return Padding(
                padding: const EdgeInsets.only(bottom: 10),
                child: MediaLibraryTile(
                  key: ValueKey<String>('library-${item.messageKey}'),
                  item: item,
                  onTap: () => _open(scope, item),
                  onToggleFavorite: () {
                    scope.playerController.toggleFavoriteFor(item);
                    setState(() {});
                  },
                ),
              );
            },
            childCount: songs.length,
          ),
        ),
      ),
    ];
  }

  List<Widget> _groupSlivers(
    List<_LibraryGroup> groups,
    String emptyTitle,
    String emptyBody,
  ) {
    if (groups.isEmpty) {
      return <Widget>[
        SliverFillRemaining(
          hasScrollBody: false,
          child: _EmptyLibrary(title: emptyTitle, body: emptyBody),
        ),
      ];
    }

    return <Widget>[
      SliverPadding(
        padding: const EdgeInsets.fromLTRB(18, 0, 18, 28),
        sliver: SliverGrid(
          gridDelegate: const SliverGridDelegateWithMaxCrossAxisExtent(
            maxCrossAxisExtent: 260,
            mainAxisExtent: 176,
            crossAxisSpacing: 12,
            mainAxisSpacing: 12,
          ),
          delegate: SliverChildBuilderDelegate(
            (context, index) {
              final group = groups[index];
              return _GroupCard(
                key: ValueKey<String>('library-group-${group.key}'),
                group: group,
                onTap: () => setState(() => _openGroup = group),
              );
            },
            childCount: groups.length,
          ),
        ),
      ),
    ];
  }

  List<_LibraryGroup> _groups(
    List<MediaItem> songs, {
    required String Function(MediaItem) keyFor,
    required String Function(MediaItem) titleFor,
    required String Function(List<MediaItem>) subtitleFor,
  }) {
    final grouped = <String, List<MediaItem>>{};
    for (final item in songs) {
      grouped.putIfAbsent(keyFor(item), () => <MediaItem>[]).add(item);
    }
    final result = grouped.entries.map((entry) {
      final items = _sorted(entry.value);
      return _LibraryGroup(
        key: entry.key,
        title: titleFor(items.first),
        subtitle: subtitleFor(items),
        items: items,
      );
    }).toList(growable: true)
      ..sort((a, b) => a.title.toLowerCase().compareTo(b.title.toLowerCase()));
    return result;
  }

  List<MediaItem> _sorted(Iterable<MediaItem> items) {
    final result = items.toList(growable: true);
    result.sort((a, b) => compareMediaItems(a, b, _sortOrder));
    return result;
  }

  String? _clean(String? value) {
    final cleaned = value?.trim() ?? '';
    return cleaned.isEmpty ? null : cleaned;
  }

  void _open(AppScope scope, MediaItem item) {
    unawaited(scope.playerController.open(item));
    widget.onOpenPlayer();
  }

  Future<void> _cacheAll(AppScope scope) async {
    final cached = await scope.libraryController.cacheAllChannels();
    if (!mounted) {
      return;
    }
    final failed = scope.libraryController.cacheProgress?.failedThumbnails ?? 0;
    final message = cached
        ? failed == 0
            ? '${scope.libraryController.items.length} songs and their best artwork are cached.'
            : '${scope.libraryController.items.length} songs cached. '
                '$failed unavailable thumbnails were skipped.'
        : 'Channel caching stopped. Review the message above and try again.';
    ScaffoldMessenger.of(context)
      ..hideCurrentSnackBar()
      ..showSnackBar(SnackBar(content: Text(message)));
  }
}

class _SectionBar extends StatelessWidget {
  const _SectionBar({required this.selected, required this.onChanged});

  final _LibrarySection selected;
  final ValueChanged<_LibrarySection> onChanged;

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      height: 64,
      child: SingleChildScrollView(
        scrollDirection: Axis.horizontal,
        padding: const EdgeInsets.fromLTRB(18, 4, 18, 12),
        child: Row(
          children: _LibrarySection.values.map((section) {
            return Padding(
              padding: const EdgeInsets.only(right: 10),
              child: ChoiceChip(
                key: ValueKey<String>('library-section-${section.name}'),
                selected: section == selected,
                showCheckmark: false,
                label: Text(_label(section)),
                labelStyle: Theme.of(context).textTheme.labelLarge?.copyWith(
                      fontWeight: FontWeight.w800,
                      letterSpacing: 0.2,
                    ),
                padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(24),
                ),
                onSelected: (_) => onChanged(section),
              ),
            );
          }).toList(growable: false),
        ),
      ),
    );
  }

  String _label(_LibrarySection section) => switch (section) {
        _LibrarySection.songs => 'SONGS',
        _LibrarySection.albums => 'ALBUMS',
        _LibrarySection.artists => 'ARTISTS',
        _LibrarySection.playlists => 'PLAYLISTS',
        _LibrarySection.liked => 'LIKED',
        _LibrarySection.folders => 'FOLDERS',
      };
}

class _SortBar extends StatelessWidget {
  const _SortBar({
    required this.sortOrder,
    required this.onSortChanged,
  });

  final MediaSortOrder sortOrder;
  final ValueChanged<MediaSortOrder> onSortChanged;

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).colorScheme;
    return Align(
      alignment: Alignment.centerRight,
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 286),
        child: KeyedSubtree(
          key: const ValueKey<String>('library-sort-control'),
          child: SegmentedButton<MediaSortOrder>(
            key: const ValueKey<String>('library-sort-selector'),
            segments: const <ButtonSegment<MediaSortOrder>>[
              ButtonSegment<MediaSortOrder>(
                value: MediaSortOrder.newest,
                icon: Icon(Icons.schedule_rounded),
                label: Text('Newest'),
              ),
              ButtonSegment<MediaSortOrder>(
                value: MediaSortOrder.alphabetical,
                icon: Icon(Icons.sort_by_alpha_rounded),
                label: Text('A-Z'),
              ),
            ],
            selected: <MediaSortOrder>{sortOrder},
            showSelectedIcon: false,
            onSelectionChanged: (selection) {
              if (selection.isNotEmpty) {
                onSortChanged(selection.first);
              }
            },
            style: ButtonStyle(
              minimumSize: const WidgetStatePropertyAll<Size>(Size(0, 48)),
              visualDensity: VisualDensity.compact,
              side: WidgetStatePropertyAll<BorderSide>(
                BorderSide(color: colors.outlineVariant),
              ),
            ),
          ),
        ),
      ),
    );
  }
}

class _GroupHeader extends StatelessWidget {
  const _GroupHeader({
    required this.title,
    required this.count,
    required this.onBack,
  });

  final String title;
  final int count;
  final VoidCallback onBack;

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).colorScheme;
    return Container(
      padding: const EdgeInsets.fromLTRB(8, 8, 16, 8),
      decoration: BoxDecoration(
        color: colors.surfaceContainerLow,
        borderRadius: BorderRadius.circular(24),
      ),
      child: Row(
        children: <Widget>[
          IconButton(onPressed: onBack, icon: const Icon(Icons.arrow_back_rounded)),
          const SizedBox(width: 4),
          Expanded(
            child: Text(
              title,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: Theme.of(context).textTheme.titleMedium?.copyWith(
                    fontWeight: FontWeight.w800,
                  ),
            ),
          ),
          Text(
            '$count',
            style: Theme.of(context).textTheme.labelLarge?.copyWith(
                  color: colors.onSurfaceVariant,
                  fontWeight: FontWeight.w800,
                ),
          ),
        ],
      ),
    );
  }
}

class _ChannelCacheBanner extends StatelessWidget {
  const _ChannelCacheBanner({required this.progress});

  final ChannelCacheProgress progress;

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).colorScheme;
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: colors.secondaryContainer,
        borderRadius: BorderRadius.circular(20),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: <Widget>[
          Row(
            children: <Widget>[
              Icon(Icons.cloud_download_rounded, color: colors.onSecondaryContainer),
              const SizedBox(width: 10),
              Expanded(
                child: Text(
                  'Syncing channel library',
                  style: Theme.of(context).textTheme.titleMedium?.copyWith(
                        color: colors.onSecondaryContainer,
                        fontWeight: FontWeight.w800,
                      ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 10),
          Text(
            progress.label,
            style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                  color: colors.onSecondaryContainer,
                ),
          ),
          const SizedBox(height: 12),
          LinearProgressIndicator(
            value: progress.fraction,
            color: colors.onSecondaryContainer,
            backgroundColor: colors.onSecondaryContainer.withValues(alpha: 0.18),
          ),
        ],
      ),
    );
  }
}

class MediaLibraryTile extends StatelessWidget {
  const MediaLibraryTile({
    required this.item,
    required this.onTap,
    required this.onToggleFavorite,
    super.key,
  });

  final MediaItem item;
  final VoidCallback onTap;
  final VoidCallback onToggleFavorite;

  @override
  Widget build(BuildContext context) {
    final scope = AppScope.of(context);
    final colors = Theme.of(context).colorScheme;
    final playing = scope.playerController.item?.messageKey == item.messageKey;
    final favorite = scope.playerController.isFavoriteItem(item);
    final subtitle = (item.artist?.trim().isNotEmpty ?? false)
        ? item.artist!
        : '${item.readableSize} · Audio';
    final tileColor = playing
        ? colors.primaryContainer.withValues(alpha: 0.66)
        : colors.surfaceContainerLow;
    final titleColor = playing ? colors.onPrimaryContainer : colors.onSurface;
    final subtitleColor = playing
        ? colors.onPrimaryContainer.withValues(alpha: 0.74)
        : colors.onSurfaceVariant;

    return AnimatedContainer(
      duration: const Duration(milliseconds: 240),
      curve: Curves.easeOutCubic,
      decoration: BoxDecoration(
        color: tileColor,
        borderRadius: BorderRadius.circular(28),
        border: Border.all(
          color: playing
              ? colors.primary.withValues(alpha: 0.34)
              : colors.outlineVariant.withValues(alpha: 0.16),
        ),
      ),
      child: Material(
        color: Colors.transparent,
        borderRadius: BorderRadius.circular(28),
        clipBehavior: Clip.antiAlias,
        child: InkWell(
          onTap: onTap,
          child: Padding(
            padding: const EdgeInsets.all(12),
            child: Row(
              children: <Widget>[
                SizedBox.square(
                  dimension: 70,
                  child: MediaArtwork(
                    item: item,
                    libraryController: scope.libraryController,
                    borderRadius: 18,
                    iconSize: 28,
                  ),
                ),
                const SizedBox(width: 16),
                Expanded(
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: <Widget>[
                      Text(
                        item.title,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: Theme.of(context).textTheme.titleMedium?.copyWith(
                              color: titleColor,
                              fontWeight: FontWeight.w800,
                            ),
                      ),
                      const SizedBox(height: 5),
                      Text(
                        subtitle,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                              color: subtitleColor,
                            ),
                      ),
                    ],
                  ),
                ),
                const SizedBox(width: 8),
                AnimatedSwitcher(
                  duration: const Duration(milliseconds: 260),
                  switchInCurve: Curves.easeOutBack,
                  switchOutCurve: Curves.easeInCubic,
                  transitionBuilder: (child, animation) => ScaleTransition(
                    scale: animation,
                    child: FadeTransition(opacity: animation, child: child),
                  ),
                  child: playing
                      ? IconButton.filledTonal(
                          key: const ValueKey<String>('equalizer'),
                          onPressed: onTap,
                          icon: _PlayingEqualizerIcon(
                            active: scope.playerController.isPlaying,
                          ),
                        )
                      : PopupMenuButton<_SongAction>(
                          key: const ValueKey<String>('menu'),
                          tooltip: 'Song options',
                          onSelected: (action) {
                            if (action == _SongAction.play) {
                              onTap();
                            } else {
                              onToggleFavorite();
                            }
                          },
                          itemBuilder: (_) => <PopupMenuEntry<_SongAction>>[
                            const PopupMenuItem(
                              value: _SongAction.play,
                              child: ListTile(
                                leading: Icon(Icons.play_arrow_rounded),
                                title: Text('Play'),
                                contentPadding: EdgeInsets.zero,
                              ),
                            ),
                            PopupMenuItem(
                              value: _SongAction.favorite,
                              child: ListTile(
                                leading: Icon(
                                  favorite
                                      ? Icons.favorite_rounded
                                      : Icons.favorite_border_rounded,
                                ),
                                title: Text(
                                  favorite ? 'Remove from Liked' : 'Add to Liked',
                                ),
                                contentPadding: EdgeInsets.zero,
                              ),
                            ),
                          ],
                          child: Container(
                            width: 48,
                            height: 48,
                            decoration: BoxDecoration(
                              color: colors.surfaceContainerHigh,
                              shape: BoxShape.circle,
                            ),
                            child: const Icon(Icons.more_vert_rounded),
                          ),
                        ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class _GroupCard extends StatelessWidget {
  const _GroupCard({required this.group, required this.onTap, super.key});

  final _LibraryGroup group;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final scope = AppScope.of(context);
    final colors = Theme.of(context).colorScheme;
    return Material(
      color: colors.surfaceContainerLow,
      borderRadius: BorderRadius.circular(26),
      clipBehavior: Clip.antiAlias,
      child: InkWell(
        onTap: onTap,
        child: Padding(
          padding: const EdgeInsets.all(12),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: <Widget>[
              Expanded(
                child: Row(
                  children: <Widget>[
                    Expanded(
                      child: MediaArtwork(
                        item: group.items.first,
                        libraryController: scope.libraryController,
                        borderRadius: 20,
                        iconSize: 36,
                      ),
                    ),
                    const SizedBox(width: 10),
                    Container(
                      width: 38,
                      decoration: BoxDecoration(
                        color: colors.surfaceContainerHigh,
                        borderRadius: BorderRadius.circular(18),
                      ),
                      child: const Center(child: Icon(Icons.chevron_right_rounded)),
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 10),
              Text(
                group.title,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: Theme.of(context).textTheme.titleMedium?.copyWith(
                      fontWeight: FontWeight.w800,
                    ),
              ),
              const SizedBox(height: 2),
              Text(
                group.subtitle,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: Theme.of(context).textTheme.bodySmall?.copyWith(
                      color: colors.onSurfaceVariant,
                    ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _LibraryGroup {
  const _LibraryGroup({
    required this.key,
    required this.title,
    required this.subtitle,
    required this.items,
  });

  final String key;
  final String title;
  final String subtitle;
  final List<MediaItem> items;
}

class _PlayingEqualizerIcon extends StatefulWidget {
  const _PlayingEqualizerIcon({required this.active});

  final bool active;

  @override
  State<_PlayingEqualizerIcon> createState() => _PlayingEqualizerIconState();
}

class _PlayingEqualizerIconState extends State<_PlayingEqualizerIcon>
    with SingleTickerProviderStateMixin {
  late final AnimationController _controller;

  @override
  void initState() {
    super.initState();
    _controller = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 920),
    );
    _sync();
  }

  @override
  void didUpdateWidget(covariant _PlayingEqualizerIcon oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.active != widget.active) {
      _sync();
    }
  }

  void _sync() {
    if (widget.active) {
      _controller.repeat();
    } else {
      _controller.animateTo(
        0,
        duration: const Duration(milliseconds: 220),
        curve: Curves.easeOutCubic,
      );
    }
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final color = IconTheme.of(context).color ??
        Theme.of(context).colorScheme.onSecondaryContainer;
    return SizedBox.square(
      dimension: 24,
      child: AnimatedBuilder(
        animation: _controller,
        builder: (_, _) => CustomPaint(
          painter: _EqualizerPainter(
            progress: widget.active ? _controller.value : 0,
            color: color,
          ),
        ),
      ),
    );
  }
}

class _EqualizerPainter extends CustomPainter {
  const _EqualizerPainter({required this.progress, required this.color});

  final double progress;
  final Color color;

  @override
  void paint(Canvas canvas, Size size) {
    final paint = Paint()
      ..color = color
      ..strokeCap = StrokeCap.round
      ..strokeWidth = math.max(2.6, size.width * 0.12);
    final baseline = size.height * 0.82;
    final phase = progress * math.pi * 2;
    const phases = <double>[0, 1.8, 3.6, 5.1];
    for (var i = 0; i < phases.length; i++) {
      final wave = (math.sin(phase + phases[i]) + 1) / 2;
      final height = size.height * (0.22 + 0.5 * wave);
      final x = size.width * (0.18 + i * 0.21);
      canvas.drawLine(
        Offset(x, baseline),
        Offset(x, baseline - height),
        paint,
      );
    }
  }

  @override
  bool shouldRepaint(covariant _EqualizerPainter oldDelegate) =>
      oldDelegate.progress != progress || oldDelegate.color != color;
}

class _EmptyLibrary extends StatelessWidget {
  const _EmptyLibrary({required this.title, required this.body});

  final String title;
  final String body;

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(32),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: <Widget>[
            Container(
              width: 92,
              height: 92,
              decoration: BoxDecoration(
                color: Theme.of(context).colorScheme.primaryContainer,
                borderRadius: BorderRadius.circular(30),
              ),
              child: Icon(
                Icons.library_music_rounded,
                size: 54,
                color: Theme.of(context).colorScheme.onPrimaryContainer,
              ),
            ),
            const SizedBox(height: 18),
            Text(
              title,
              textAlign: TextAlign.center,
              style: Theme.of(context).textTheme.titleLarge,
            ),
            const SizedBox(height: 8),
            Text(
              body,
              textAlign: TextAlign.center,
              style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                    color: Theme.of(context).colorScheme.onSurfaceVariant,
                  ),
            ),
          ],
        ),
      ),
    );
  }
}
