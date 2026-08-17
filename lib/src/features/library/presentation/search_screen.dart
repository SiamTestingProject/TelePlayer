import 'dart:async';

import 'package:flutter/material.dart';

import '../../../app/app_scope.dart';
import '../../../app/error_panel.dart';
import '../models/media_item.dart';
import 'library_screen.dart';

class SearchScreen extends StatefulWidget {
  const SearchScreen({
    required this.onOpenPlayer,
    super.key,
  });

  final VoidCallback onOpenPlayer;

  @override
  State<SearchScreen> createState() => _SearchScreenState();
}

class _SearchScreenState extends State<SearchScreen> {
  final _searchController = TextEditingController();
  final _searchFocusNode = FocusNode();
  bool _requestedInitialLoad = false;
  String _query = '';

  @override
  void dispose() {
    _searchController.dispose();
    _searchFocusNode.dispose();
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
      if (!mounted) {
        return;
      }
      unawaited(AppScope.of(context).libraryController.load());
      _searchFocusNode.requestFocus();
    });
  }

  @override
  Widget build(BuildContext context) {
    final scope = AppScope.of(context);
    final library = scope.libraryController;
    final results = _searchResults(library.items);
    final colors = Theme.of(context).colorScheme;

    return Scaffold(
      backgroundColor: colors.surface,
      body: SafeArea(
        child: CustomScrollView(
          keyboardDismissBehavior: ScrollViewKeyboardDismissBehavior.onDrag,
          slivers: <Widget>[
            SliverToBoxAdapter(
              child: Padding(
                padding: const EdgeInsets.fromLTRB(22, 20, 18, 12),
                child: Text(
                  'Search',
                  style: Theme.of(context).textTheme.displaySmall?.copyWith(
                        fontWeight: FontWeight.w800,
                        letterSpacing: 0,
                      ),
                ),
              ),
            ),
            SliverToBoxAdapter(
              child: Padding(
                padding: const EdgeInsets.fromLTRB(16, 0, 16, 14),
                child: TextField(
                  key: const ValueKey<String>('library-search-field'),
                  controller: _searchController,
                  focusNode: _searchFocusNode,
                  textInputAction: TextInputAction.search,
                  onChanged: (value) => setState(() => _query = value),
                  decoration: InputDecoration(
                    hintText: 'Search songs, artists or files',
                    prefixIcon: const Icon(Icons.search_rounded),
                    suffixIcon: _query.isEmpty
                        ? null
                        : IconButton(
                            tooltip: 'Clear search',
                            onPressed: () {
                              _searchController.clear();
                              setState(() => _query = '');
                              _searchFocusNode.requestFocus();
                            },
                            icon: const Icon(Icons.close_rounded),
                          ),
                  ),
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
            if (!library.isLoading && _query.trim().isEmpty)
              const SliverFillRemaining(
                hasScrollBody: false,
                child: _SearchHint(),
              )
            else if (!library.isLoading && results.isEmpty)
              const SliverFillRemaining(
                hasScrollBody: false,
                child: _NoSearchResults(),
              )
            else
              SliverPadding(
                padding: const EdgeInsets.fromLTRB(16, 0, 16, 24),
                sliver: SliverList(
                  delegate: SliverChildBuilderDelegate(
                    (context, index) {
                      final item = results[index];
                      return Padding(
                        padding: const EdgeInsets.only(bottom: 10),
                        child: MediaLibraryTile(
                          key: ValueKey<String>('search-${item.messageKey}'),
                          item: item,
                          onTap: () => _open(scope, item),
                          onToggleFavorite: () {
                            scope.playerController.toggleFavoriteFor(item);
                            setState(() {});
                          },
                        ),
                      );
                    },
                    childCount: results.length,
                  ),
                ),
              ),
          ],
        ),
      ),
    );
  }

  List<MediaItem> _searchResults(List<MediaItem> items) {
    final query = _query.trim().toLowerCase();
    if (query.isEmpty) {
      return const <MediaItem>[];
    }
    final results = items.where((item) {
      if (item.kind != MediaKind.audio) {
        return false;
      }
      final artist = item.artist?.toLowerCase() ?? '';
      final album = item.album?.toLowerCase() ?? '';
      final source = item.sourceName?.toLowerCase() ?? '';
      return item.title.toLowerCase().contains(query) ||
          item.fileName.toLowerCase().contains(query) ||
          artist.contains(query) ||
          album.contains(query) ||
          source.contains(query) ||
          item.mimeType.toLowerCase().contains(query);
    }).toList(growable: true);
    results.sort(
      (left, right) => compareMediaItems(
        left,
        right,
        MediaSortOrder.alphabetical,
      ),
    );
    return results;
  }

  void _open(AppScope scope, MediaItem item) {
    unawaited(scope.playerController.open(item));
    widget.onOpenPlayer();
  }
}

class _SearchHint extends StatelessWidget {
  const _SearchHint();

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).colorScheme;
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(32),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: <Widget>[
            Icon(
              Icons.search_rounded,
              size: 58,
              color: colors.onSurfaceVariant,
            ),
            const SizedBox(height: 14),
            Text(
              'Search your library',
              style: Theme.of(context).textTheme.titleLarge?.copyWith(
                    fontWeight: FontWeight.w800,
                  ),
            ),
            const SizedBox(height: 8),
            Text(
              'Find songs by title, artist, album, source or file name.',
              textAlign: TextAlign.center,
              style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                    color: colors.onSurfaceVariant,
                  ),
            ),
          ],
        ),
      ),
    );
  }
}

class _NoSearchResults extends StatelessWidget {
  const _NoSearchResults();

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).colorScheme;
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(32),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: <Widget>[
            Icon(
              Icons.search_off_rounded,
              size: 58,
              color: colors.onSurfaceVariant,
            ),
            const SizedBox(height: 14),
            Text(
              'No songs found',
              style: Theme.of(context).textTheme.titleLarge?.copyWith(
                    fontWeight: FontWeight.w800,
                  ),
            ),
            const SizedBox(height: 8),
            Text(
              'Try a different song title, artist or file name.',
              textAlign: TextAlign.center,
              style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                    color: colors.onSurfaceVariant,
                  ),
            ),
          ],
        ),
      ),
    );
  }
}
