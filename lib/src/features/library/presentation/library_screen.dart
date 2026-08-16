import 'dart:async';
import 'dart:math';

import 'package:flutter/material.dart';

import '../../../app/app_scope.dart';
import '../../../app/error_panel.dart';
import '../models/channel_cache_progress.dart';
import '../models/media_item.dart';
import 'media_artwork.dart';

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
  final _searchController = TextEditingController();
  bool _requestedInitialLoad = false;
  MediaSortOrder _sortOrder = MediaSortOrder.newest;
  String _searchQuery = '';

  @override
  void dispose() {
    _searchController.dispose();
    super.dispose();
  }

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
                                letterSpacing: 0,
                              ),
                        ),
                      ),
                      IconButton.filledTonal(
                        tooltip: 'Cache all songs and album artwork',
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
                      const SizedBox(width: 8),
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
                child: Padding(
                  padding: const EdgeInsets.fromLTRB(16, 4, 16, 12),
                  child: _LibraryMixCard(
                    visibleCount: visibleItems.length,
                    totalCount: library.items.length,
                    isLoading: library.isLoading,
                    onShuffle: visibleItems.isEmpty
                        ? null
                        : () => _shuffle(scope, visibleItems),
                    onRefresh: library.isLoading
                        ? null
                        : () => unawaited(library.load()),
                  ),
                ),
              ),
              if (library.isCaching && library.cacheProgress != null)
                SliverToBoxAdapter(
                  child: Padding(
                    padding: const EdgeInsets.fromLTRB(16, 0, 16, 12),
                    child: _ChannelCacheBanner(
                      progress: library.cacheProgress!,
                    ),
                  ),
                ),
              SliverToBoxAdapter(
                child: Padding(
                  padding: const EdgeInsets.fromLTRB(16, 0, 16, 12),
                  child: _LibrarySortRow(
                    visibleCount: visibleItems.length,
                    sortOrder: _sortOrder,
                    onChanged: (order) => setState(() => _sortOrder = order),
                  ),
                ),
              ),
              SliverToBoxAdapter(
                child: Padding(
                  padding: const EdgeInsets.fromLTRB(16, 0, 16, 12),
                  child: _LibrarySearchField(
                    controller: _searchController,
                    onChanged: (value) => setState(() => _searchQuery = value),
                    onClear: _searchQuery.isEmpty
                        ? null
                        : () {
                            _searchController.clear();
                            setState(() => _searchQuery = '');
                          },
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
                  child: const _EmptyLibrary(),
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
    final filtered = items
        .where((item) => item.kind == MediaKind.audio)
        .toList(growable: true);
    final query = _searchQuery.trim().toLowerCase();
    if (query.isNotEmpty) {
      filtered.removeWhere((item) {
        final artist = item.artist?.toLowerCase() ?? '';
        return !item.title.toLowerCase().contains(query) &&
            !item.fileName.toLowerCase().contains(query) &&
            !artist.contains(query) &&
            !item.mimeType.toLowerCase().contains(query);
      });
    }
    filtered.sort((left, right) => compareMediaItems(left, right, _sortOrder));
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

  Future<void> _cacheAll(AppScope scope) async {
    final cached = await scope.libraryController.cacheAllChannels();
    if (!mounted) {
      return;
    }
    final failedThumbnails =
        scope.libraryController.cacheProgress?.failedThumbnails ?? 0;
    final message = cached
        ? failedThumbnails == 0
            ? '${scope.libraryController.items.length} songs and their best artwork are cached.'
            : '${scope.libraryController.items.length} songs cached. '
                '$failedThumbnails unavailable thumbnails were skipped.'
        : 'Channel caching stopped. Review the message above and try again.';
    ScaffoldMessenger.of(context)
      ..hideCurrentSnackBar()
      ..showSnackBar(SnackBar(content: Text(message)));
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
                  'Caching channel library',
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

class _LibraryMixCard extends StatelessWidget {
  const _LibraryMixCard({
    required this.visibleCount,
    required this.totalCount,
    required this.isLoading,
    required this.onShuffle,
    required this.onRefresh,
  });

  final int visibleCount;
  final int totalCount;
  final bool isLoading;
  final VoidCallback? onShuffle;
  final VoidCallback? onRefresh;

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).colorScheme;
    final countLabel = totalCount == visibleCount
        ? '$totalCount songs'
        : '$visibleCount of $totalCount songs';
    return AnimatedContainer(
      duration: const Duration(milliseconds: 220),
      curve: Curves.easeOutCubic,
      padding: const EdgeInsets.all(18),
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(36),
        gradient: LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: <Color>[
            colors.primaryContainer,
            colors.secondaryContainer.withValues(alpha: 0.88),
            colors.tertiaryContainer.withValues(alpha: 0.72),
          ],
        ),
        border: Border.all(color: colors.outlineVariant.withValues(alpha: 0.28)),
      ),
      child: Column(
        children: <Widget>[
          Row(
            children: <Widget>[
              Container(
                width: 76,
                height: 76,
                decoration: BoxDecoration(
                  color: colors.surface.withValues(alpha: 0.54),
                  borderRadius: BorderRadius.circular(24),
                ),
                child: Icon(
                  Icons.album_rounded,
                  color: colors.primary,
                  size: 40,
                ),
              ),
              const SizedBox(width: 16),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: <Widget>[
                    Text(
                      'Telegram Mix',
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: Theme.of(context).textTheme.headlineSmall?.copyWith(
                            color: colors.onPrimaryContainer,
                            fontWeight: FontWeight.w800,
                            letterSpacing: 0,
                          ),
                    ),
                    const SizedBox(height: 6),
                    Text(
                      countLabel,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: Theme.of(context).textTheme.bodyLarge?.copyWith(
                            color: colors.onPrimaryContainer.withValues(alpha: 0.78),
                          ),
                    ),
                  ],
                ),
              ),
            ],
          ),
          const SizedBox(height: 18),
          Row(
            children: <Widget>[
              Expanded(
                child: FilledButton.tonalIcon(
                  onPressed: onShuffle,
                  icon: const Icon(Icons.shuffle_rounded),
                  label: const Text('Shuffle'),
                ),
              ),
              const SizedBox(width: 10),
              IconButton.filledTonal(
                tooltip: 'Refresh',
                onPressed: onRefresh,
                icon: isLoading
                    ? const SizedBox.square(
                        dimension: 18,
                        child: CircularProgressIndicator(strokeWidth: 2),
                      )
                    : const Icon(Icons.refresh_rounded),
              ),
            ],
          ),
        ],
      ),
    );
  }
}

class _LibrarySortRow extends StatelessWidget {
  const _LibrarySortRow({
    required this.visibleCount,
    required this.sortOrder,
    required this.onChanged,
  });

  final int visibleCount;
  final MediaSortOrder sortOrder;
  final ValueChanged<MediaSortOrder> onChanged;

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).colorScheme;
    return Container(
      padding: const EdgeInsets.fromLTRB(16, 8, 8, 8),
      decoration: BoxDecoration(
        color: colors.surfaceContainerLow,
        borderRadius: BorderRadius.circular(30),
        border: Border.all(color: colors.outlineVariant.withValues(alpha: 0.24)),
      ),
      child: Row(
        children: <Widget>[
          Text(
            '$visibleCount shown',
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: Theme.of(context).textTheme.titleSmall?.copyWith(
                  color: colors.onSurfaceVariant,
                  fontWeight: FontWeight.w700,
                ),
          ),
          const SizedBox(width: 10),
          Expanded(
            child: SegmentedButton<MediaSortOrder>(
              key: const ValueKey<String>('library-sort-control'),
              showSelectedIcon: false,
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
              onSelectionChanged: (selection) => onChanged(selection.first),
            ),
          ),
        ],
      ),
    );
  }
}

class _LibrarySearchField extends StatelessWidget {
  const _LibrarySearchField({
    required this.controller,
    required this.onChanged,
    required this.onClear,
  });

  final TextEditingController controller;
  final ValueChanged<String> onChanged;
  final VoidCallback? onClear;

  @override
  Widget build(BuildContext context) {
    return TextField(
      controller: controller,
      textInputAction: TextInputAction.search,
      onChanged: onChanged,
      decoration: InputDecoration(
        hintText: 'Search library',
        prefixIcon: const Icon(Icons.search_rounded),
        suffixIcon: onClear == null
            ? null
            : IconButton(
                tooltip: 'Clear search',
                onPressed: onClear,
                icon: const Icon(Icons.close_rounded),
              ),
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
    final playing = scope.playerController.item?.id == item.id;
    final subtitle = item.artist?.trim().isNotEmpty == true
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
      duration: const Duration(milliseconds: 220),
      curve: Curves.easeOutCubic,
      decoration: BoxDecoration(
        color: tileColor,
        borderRadius: BorderRadius.circular(28),
        border: Border.all(
          color: playing
              ? colors.primary.withValues(alpha: 0.34)
              : colors.outlineVariant.withValues(alpha: 0.20),
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
                              color: titleColor,
                              fontWeight: FontWeight.w800,
                              letterSpacing: 0,
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
                const SizedBox(width: 6),
                IconButton.filledTonal(
                  tooltip: playing ? 'Now playing' : 'Play',
                  onPressed: onTap,
                  icon: Icon(
                    playing
                        ? Icons.equalizer_rounded
                        : Icons.play_arrow_rounded,
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

class _EmptyLibrary extends StatelessWidget {
  const _EmptyLibrary();

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
              'No songs found',
              style: Theme.of(context).textTheme.titleLarge,
            ),
            const SizedBox(height: 8),
            Text(
              'No Telegram audio matched this Library.',
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
