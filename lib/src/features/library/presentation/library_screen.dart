import 'dart:async';
import 'dart:math';

import 'package:flutter/material.dart';

import '../../../app/app_scope.dart';
import '../../../app/error_panel.dart';
import '../models/media_item.dart';
import 'media_artwork.dart';

enum _LibraryFilter { songs, videos, all }

class LibraryScreen extends StatefulWidget {
  const LibraryScreen({
    required this.onOpenPlayer,
    required this.onOpenSettings,
    super.key,
  });

  final VoidCallback onOpenPlayer;
  final VoidCallback onOpenSettings;

  @override
  State<LibraryScreen> createState() => _LibraryScreenState();
}

class _LibraryScreenState extends State<LibraryScreen> {
  bool _requestedInitialLoad = false;
  bool _sortByTitle = false;
  _LibraryFilter _filter = _LibraryFilter.songs;

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
    final visibleItems = _visibleItems(library.items);
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
                  padding: const EdgeInsets.fromLTRB(22, 20, 18, 8),
                  child: Row(
                    children: <Widget>[
                      Expanded(
                        child: Text(
                          'Library',
                          style: Theme.of(context).textTheme.displaySmall?.copyWith(
                                fontWeight: FontWeight.w800,
                                letterSpacing: -1.2,
                              ),
                        ),
                      ),
                      IconButton.filledTonal(
                        tooltip: 'Settings',
                        onPressed: widget.onOpenSettings,
                        icon: const Icon(Icons.settings_rounded),
                      ),
                    ],
                  ),
                ),
              ),
              SliverToBoxAdapter(
                child: SizedBox(
                  height: 66,
                  child: ListView(
                    scrollDirection: Axis.horizontal,
                    padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 8),
                    children: <Widget>[
                      _FilterPill(
                        label: 'SONGS',
                        selected: _filter == _LibraryFilter.songs,
                        onSelected: () => setState(() => _filter = _LibraryFilter.songs),
                      ),
                      _FilterPill(
                        label: 'VIDEOS',
                        selected: _filter == _LibraryFilter.videos,
                        onSelected: () => setState(() => _filter = _LibraryFilter.videos),
                      ),
                      _FilterPill(
                        label: 'ALL MEDIA',
                        selected: _filter == _LibraryFilter.all,
                        onSelected: () => setState(() => _filter = _LibraryFilter.all),
                      ),
                    ],
                  ),
                ),
              ),
              SliverToBoxAdapter(
                child: Container(
                  margin: const EdgeInsets.fromLTRB(16, 4, 16, 12),
                  padding: const EdgeInsets.all(10),
                  decoration: BoxDecoration(
                    color: colors.surfaceContainerLow,
                    borderRadius: BorderRadius.circular(30),
                  ),
                  child: Row(
                    children: <Widget>[
                      FilledButton.tonalIcon(
                        onPressed: visibleItems.isEmpty
                            ? null
                            : () => _shuffle(scope, visibleItems),
                        icon: const Icon(Icons.shuffle_rounded),
                        label: const Text('Shuffle'),
                      ),
                      const Spacer(),
                      IconButton.filledTonal(
                        tooltip: _sortByTitle ? 'Sort by newest' : 'Sort by title',
                        onPressed: () => setState(() => _sortByTitle = !_sortByTitle),
                        icon: Icon(
                          _sortByTitle
                              ? Icons.schedule_rounded
                              : Icons.sort_by_alpha_rounded,
                        ),
                      ),
                      const SizedBox(width: 6),
                      IconButton.filledTonal(
                        tooltip: 'Refresh',
                        onPressed: library.isLoading
                            ? null
                            : () => unawaited(library.load()),
                        icon: const Icon(Icons.refresh_rounded),
                      ),
                    ],
                  ),
                ),
              ),
              if (library.error != null)
                SliverPadding(
                  padding: const EdgeInsets.fromLTRB(16, 0, 16, 12),
                  sliver: SliverToBoxAdapter(
                    child: ErrorPanel(
                      error: library.error!,
                      onAction: () => unawaited(library.load()),
                    ),
                  ),
                ),
              if (library.isLoading)
                const SliverToBoxAdapter(child: LinearProgressIndicator()),
              if (!library.isLoading && visibleItems.isEmpty)
                SliverFillRemaining(
                  hasScrollBody: false,
                  child: _EmptyLibrary(filter: _filter),
                )
              else
                SliverPadding(
                  padding: const EdgeInsets.fromLTRB(16, 2, 16, 24),
                  sliver: SliverList(
                    delegate: SliverChildBuilderDelegate(
                      (context, index) {
                        final item = visibleItems[index];
                        return Padding(
                          padding: const EdgeInsets.only(bottom: 10),
                          child: _MediaTile(
                            item: item,
                            onTap: () => _open(scope, item),
                          ),
                        );
                      },
                      childCount: visibleItems.length,
                    ),
                  ),
                ),
            ],
          ),
        ),
      ),
    );
  }

  List<MediaItem> _visibleItems(List<MediaItem> items) {
    final filtered = switch (_filter) {
      _LibraryFilter.songs =>
        items.where((item) => item.kind == MediaKind.audio).toList(),
      _LibraryFilter.videos =>
        items.where((item) => item.kind != MediaKind.audio).toList(),
      _LibraryFilter.all => items.toList(),
    };
    if (_sortByTitle) {
      filtered.sort(
        (left, right) => left.title.toLowerCase().compareTo(
              right.title.toLowerCase(),
            ),
      );
    }
    return filtered;
  }

  void _open(AppScope scope, MediaItem item) {
    unawaited(scope.playerController.open(item));
    widget.onOpenPlayer();
  }

  void _shuffle(AppScope scope, List<MediaItem> items) {
    if (!scope.playerController.shuffleEnabled) {
      scope.playerController.toggleShuffle();
    }
    _open(scope, items[Random().nextInt(items.length)]);
  }
}

class _FilterPill extends StatelessWidget {
  const _FilterPill({
    required this.label,
    required this.selected,
    required this.onSelected,
  });

  final String label;
  final bool selected;
  final VoidCallback onSelected;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(right: 10),
      child: ChoiceChip(
        label: Text(label),
        selected: selected,
        showCheckmark: false,
        onSelected: (_) => onSelected(),
        labelStyle: Theme.of(context).textTheme.labelLarge?.copyWith(
              fontWeight: FontWeight.w700,
            ),
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(24)),
      ),
    );
  }
}

class _MediaTile extends StatelessWidget {
  const _MediaTile({required this.item, required this.onTap});

  final MediaItem item;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final scope = AppScope.of(context);
    final colors = Theme.of(context).colorScheme;
    final subtitle = item.artist?.trim().isNotEmpty == true
        ? item.artist!
        : '${item.readableSize} · ${_typeLabel(item)}';
    return Material(
      color: colors.surfaceContainerLow,
      borderRadius: BorderRadius.circular(26),
      clipBehavior: Clip.antiAlias,
      child: InkWell(
        onTap: onTap,
        child: Padding(
          padding: const EdgeInsets.all(12),
          child: Row(
            children: <Widget>[
              SizedBox.square(
                dimension: 76,
                child: Hero(
                  tag: 'artwork-${item.id}',
                  child: MediaArtwork(
                    item: item,
                    libraryController: scope.libraryController,
                    borderRadius: 18,
                    iconSize: 30,
                  ),
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
                            fontWeight: FontWeight.w700,
                          ),
                    ),
                    const SizedBox(height: 5),
                    Text(
                      subtitle,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                            color: colors.onSurfaceVariant,
                          ),
                    ),
                  ],
                ),
              ),
              PopupMenuButton<String>(
                tooltip: 'Media actions',
                icon: const Icon(Icons.more_vert_rounded),
                onSelected: (_) => onTap(),
                itemBuilder: (context) => const <PopupMenuEntry<String>>[
                  PopupMenuItem<String>(
                    value: 'play',
                    child: ListTile(
                      contentPadding: EdgeInsets.zero,
                      leading: Icon(Icons.play_arrow_rounded),
                      title: Text('Play now'),
                    ),
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }

  String _typeLabel(MediaItem item) {
    if (item.kind == MediaKind.audio) {
      return 'Audio';
    }
    if (item.isSplit) {
      return '${item.parts.length} parts';
    }
    return 'Video';
  }
}

class _EmptyLibrary extends StatelessWidget {
  const _EmptyLibrary({required this.filter});

  final _LibraryFilter filter;

  @override
  Widget build(BuildContext context) {
    final label = switch (filter) {
      _LibraryFilter.songs => 'No songs found',
      _LibraryFilter.videos => 'No videos found',
      _LibraryFilter.all => 'No media found',
    };
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(32),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: <Widget>[
            Icon(
              Icons.library_music_rounded,
              size: 64,
              color: Theme.of(context).colorScheme.primary,
            ),
            const SizedBox(height: 16),
            Text(label, style: Theme.of(context).textTheme.titleLarge),
            const SizedBox(height: 8),
            const Text(
              'Pull down to refresh the configured Telegram channels.',
              textAlign: TextAlign.center,
            ),
          ],
        ),
      ),
    );
  }
}
