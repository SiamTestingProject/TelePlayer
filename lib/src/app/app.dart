import 'dart:async';

import 'package:flutter/material.dart';

import '../features/auth/models/auth_models.dart';
import '../features/auth/presentation/auth_screen.dart';
import '../features/library/presentation/library_screen.dart';
import '../features/library/presentation/media_artwork.dart';
import '../features/player/application/player_controller.dart';
import '../features/player/presentation/player_screen.dart';
import '../features/settings/presentation/settings_screen.dart';
import '../features/update/presentation/app_update_sheet.dart';
import 'app_scope.dart';

class TelePlayerApp extends StatelessWidget {
  const TelePlayerApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'TelePlayer',
      debugShowCheckedModeBanner: false,
      theme: _telePlayerTheme(Brightness.light),
      darkTheme: _telePlayerTheme(Brightness.dark),
      home: const AppHome(),
    );
  }
}

ThemeData _telePlayerTheme(Brightness brightness) {
  const seed = Color(0xFF2F6F68);
  final colors = ColorScheme.fromSeed(
    seedColor: seed,
    brightness: brightness,
  );
  final base = ThemeData(colorScheme: colors, useMaterial3: true);
  final inputBorder = OutlineInputBorder(
    borderRadius: BorderRadius.circular(26),
    borderSide: BorderSide(
      color: colors.outlineVariant.withValues(alpha: 0.56),
    ),
  );
  return base.copyWith(
    scaffoldBackgroundColor: colors.surface,
    appBarTheme: AppBarTheme(
      backgroundColor: Colors.transparent,
      foregroundColor: colors.onSurface,
      elevation: 0,
      centerTitle: false,
      surfaceTintColor: Colors.transparent,
      titleTextStyle: base.textTheme.titleLarge?.copyWith(
        color: colors.onSurface,
        fontWeight: FontWeight.w800,
        letterSpacing: 0,
      ),
    ),
    inputDecorationTheme: InputDecorationTheme(
      filled: true,
      fillColor: colors.surfaceContainerLow,
      border: inputBorder,
      enabledBorder: inputBorder,
      focusedBorder: inputBorder.copyWith(
        borderSide: BorderSide(color: colors.primary, width: 1.4),
      ),
      errorBorder: inputBorder.copyWith(
        borderSide: BorderSide(color: colors.error),
      ),
      focusedErrorBorder: inputBorder.copyWith(
        borderSide: BorderSide(color: colors.error, width: 1.4),
      ),
      contentPadding: const EdgeInsets.symmetric(horizontal: 18, vertical: 18),
    ),
    filledButtonTheme: FilledButtonThemeData(
      style: FilledButton.styleFrom(
        minimumSize: const Size(64, 52),
        padding: const EdgeInsets.symmetric(horizontal: 22, vertical: 16),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(26)),
        textStyle: base.textTheme.labelLarge?.copyWith(
          fontWeight: FontWeight.w800,
          letterSpacing: 0,
        ),
      ),
    ),
    iconButtonTheme: IconButtonThemeData(
      style: IconButton.styleFrom(
        minimumSize: const Size.square(46),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(18)),
      ),
    ),
    navigationBarTheme: NavigationBarThemeData(
      height: 78,
      backgroundColor: colors.surfaceContainer,
      indicatorColor: colors.primaryContainer,
      indicatorShape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(24),
      ),
    ),
    navigationRailTheme: NavigationRailThemeData(
      backgroundColor: colors.surfaceContainer,
      indicatorColor: colors.primaryContainer,
      indicatorShape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(24),
      ),
      selectedIconTheme: IconThemeData(color: colors.onPrimaryContainer),
      unselectedIconTheme: IconThemeData(color: colors.onSurfaceVariant),
    ),
    sliderTheme: base.sliderTheme.copyWith(
      trackHeight: 6,
      thumbShape: const RoundSliderThumbShape(enabledThumbRadius: 9),
    ),
    snackBarTheme: SnackBarThemeData(
      behavior: SnackBarBehavior.floating,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(22)),
    ),
  );
}

class AppHome extends StatefulWidget {
  const AppHome({super.key});

  @override
  State<AppHome> createState() => _AppHomeState();
}

class _AppHomeState extends State<AppHome> {
  int _index = 0;
  final List<int> _navigationHistory = <int>[0];
  bool _scheduledUpdateCheck = false;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (_scheduledUpdateCheck) {
      return;
    }
    _scheduledUpdateCheck = true;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) {
        unawaited(_checkForUpdateOnStartup());
      }
    });
  }

  Future<void> _checkForUpdateOnStartup() async {
    final controller = AppScope.of(context).updateController;
    final update = await controller.checkOnStartup();
    if (!mounted || update == null) {
      return;
    }
    await showAppUpdateSheet(
      context,
      controller: controller,
      update: update,
    );
  }

  void _navigateTo(int index) {
    if (index == _index) {
      return;
    }
    setState(() {
      _navigationHistory.add(index);
      _index = index;
    });
  }

  void _navigateBack() {
    if (_navigationHistory.length <= 1) {
      return;
    }
    setState(() {
      _navigationHistory.removeLast();
      _index = _navigationHistory.last;
    });
  }

  @override
  Widget build(BuildContext context) {
    final scope = AppScope.of(context);
    return PopScope<Object?>(
      canPop: _navigationHistory.length <= 1,
      onPopInvokedWithResult: (didPop, _) {
        if (!didPop) {
          _navigateBack();
        }
      },
      child: AnimatedBuilder(
        animation: Listenable.merge([
          scope.authController,
          scope.libraryController,
          scope.playerController,
          scope.settingsController,
        ]),
        builder: (context, _) {
          final authReady =
              scope.authController.step.kind == AuthStepKind.ready;
          final child = switch (_index) {
            0 => authReady
                ? LibraryScreen(onOpenPlayer: () => _navigateTo(1))
                : AuthScreen(onOpenSettings: () => _navigateTo(2)),
            1 => authReady
                ? PlayerScreen(onClose: _navigateBack)
                : AuthScreen(onOpenSettings: () => _navigateTo(2)),
            _ => SettingsScreen(
                onSaved: () =>
                    unawaited(scope.authController.initialize()),
              ),
          };
          return LayoutBuilder(
            builder: (context, constraints) {
              final wide = constraints.maxWidth >= 760;
              if (wide) {
                return Scaffold(
                  body: Row(
                    children: [
                      NavigationRail(
                        selectedIndex: _index,
                        onDestinationSelected: _navigateTo,
                        labelType: NavigationRailLabelType.all,
                        destinations: const [
                          NavigationRailDestination(
                            icon: Icon(Icons.library_music_outlined),
                            selectedIcon: Icon(Icons.library_music_rounded),
                            label: Text('Library'),
                          ),
                          NavigationRailDestination(
                            icon: Icon(Icons.play_circle_outline_rounded),
                            selectedIcon: Icon(Icons.play_circle_rounded),
                            label: Text('Player'),
                          ),
                          NavigationRailDestination(
                            icon: Icon(Icons.settings_outlined),
                            selectedIcon: Icon(Icons.settings),
                            label: Text('Settings'),
                          ),
                        ],
                      ),
                      const VerticalDivider(width: 1),
                      Expanded(child: child),
                    ],
                  ),
                );
              }
              if (authReady && _index == 1) {
                return child;
              }
              return Scaffold(
                body: child,
                bottomNavigationBar: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: <Widget>[
                    if (authReady &&
                        scope.playerController.item != null &&
                        _index != 1)
                      _MiniPlayer(
                        onOpenPlayer: () => _navigateTo(1),
                      ),
                    NavigationBar(
                      selectedIndex: _index,
                      onDestinationSelected: _navigateTo,
                      destinations: const [
                        NavigationDestination(
                          icon: Icon(Icons.library_music_outlined),
                          selectedIcon: Icon(Icons.library_music_rounded),
                          label: 'Library',
                        ),
                        NavigationDestination(
                          icon: Icon(Icons.play_circle_outline_rounded),
                          selectedIcon: Icon(Icons.play_circle_rounded),
                          label: 'Player',
                        ),
                        NavigationDestination(
                          icon: Icon(Icons.settings_outlined),
                          selectedIcon: Icon(Icons.settings_rounded),
                          label: 'Settings',
                        ),
                      ],
                    ),
                  ],
                ),
              );
            },
          );
        },
      ),
    );
  }

}

class _MiniPlayer extends StatelessWidget {
  const _MiniPlayer({required this.onOpenPlayer});

  final VoidCallback onOpenPlayer;

  @override
  Widget build(BuildContext context) {
    final scope = AppScope.of(context);
    final player = scope.playerController;
    final item = player.item!;
    final colors = Theme.of(context).colorScheme;
    final surfaceColor = Color.alphaBlend(
      colors.primary.withValues(alpha: 0.14),
      colors.surfaceContainerHigh,
    );
    return Padding(
      padding: const EdgeInsets.fromLTRB(12, 6, 12, 2),
      child: Material(
        color: surfaceColor,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(28),
          side: BorderSide(color: colors.outlineVariant.withValues(alpha: 0.28)),
        ),
        clipBehavior: Clip.antiAlias,
        child: InkWell(
          onTap: onOpenPlayer,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: <Widget>[
              if (player.isLoading) const LinearProgressIndicator(minHeight: 2),
              Padding(
                padding: const EdgeInsets.fromLTRB(12, 8, 8, 8),
                child: Row(
                  children: <Widget>[
                    SizedBox.square(
                      dimension: 58,
                      child: MediaArtwork(
                        item: item,
                        libraryController: scope.libraryController,
                        borderRadius: 18,
                        iconSize: 24,
                      ),
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: <Widget>[
                          Text(
                            item.title,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: Theme.of(context).textTheme.titleSmall?.copyWith(
                                  fontWeight: FontWeight.w800,
                                  letterSpacing: 0,
                                ),
                          ),
                          const SizedBox(height: 2),
                          Text(
                            item.artist ?? item.readableSize,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: Theme.of(context).textTheme.bodySmall?.copyWith(
                                  color: colors.onSurfaceVariant,
                                ),
                          ),
                        ],
                      ),
                    ),
                    IconButton(
                      tooltip: 'Previous',
                      onPressed: () => unawaited(player.playPrevious()),
                      icon: const Icon(Icons.skip_previous_rounded),
                    ),
                    _MiniPlayButton(player: player),
                    IconButton(
                      tooltip: 'Next',
                      onPressed: () => unawaited(player.playNext()),
                      icon: const Icon(Icons.skip_next_rounded),
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _MiniPlayButton extends StatelessWidget {
  const _MiniPlayButton({required this.player});

  final PlayerController player;

  @override
  Widget build(BuildContext context) {
    final playing = player.isPlaying;
    return IconButton.filled(
      tooltip: playing ? 'Pause' : 'Play',
      onPressed: () => unawaited(player.togglePlay()),
      icon: Icon(playing ? Icons.pause_rounded : Icons.play_arrow_rounded),
    );
  }
}
