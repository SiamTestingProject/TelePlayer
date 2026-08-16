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
    const seed = Color(0xFF8B4E75);
    return MaterialApp(
      title: 'TelePlayer',
      debugShowCheckedModeBanner: false,
      theme: ThemeData(
        colorScheme: ColorScheme.fromSeed(seedColor: seed, brightness: Brightness.light),
        useMaterial3: true,
        navigationBarTheme: const NavigationBarThemeData(height: 76),
      ),
      darkTheme: ThemeData(
        colorScheme: ColorScheme.fromSeed(seedColor: seed, brightness: Brightness.dark),
        useMaterial3: true,
        navigationBarTheme: const NavigationBarThemeData(height: 76),
      ),
      home: const AppHome(),
    );
  }
}

class AppHome extends StatefulWidget {
  const AppHome({super.key});

  @override
  State<AppHome> createState() => _AppHomeState();
}

class _AppHomeState extends State<AppHome> {
  int _index = 0;
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

  @override
  Widget build(BuildContext context) {
    final scope = AppScope.of(context);
    return AnimatedBuilder(
      animation: Listenable.merge([
        scope.authController,
        scope.libraryController,
        scope.playerController,
        scope.settingsController,
      ]),
      builder: (context, _) {
        final authReady = scope.authController.step.kind == AuthStepKind.ready;
        final child = switch (_index) {
          0 => authReady
              ? LibraryScreen(
                  onOpenPlayer: () => setState(() => _index = 1),
                  onOpenSettings: () => setState(() => _index = 2),
                )
              : AuthScreen(onOpenSettings: () => setState(() => _index = 2)),
          1 => authReady
              ? PlayerScreen(onClose: () => setState(() => _index = 0))
              : AuthScreen(onOpenSettings: () => setState(() => _index = 2)),
          _ => SettingsScreen(onSaved: () => unawaited(scope.authController.initialize())),
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
                      onDestinationSelected: (value) => setState(() => _index = value),
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
                      onOpenPlayer: () => setState(() => _index = 1),
                    ),
                  NavigationBar(
                    selectedIndex: _index,
                    onDestinationSelected: (value) => setState(() => _index = value),
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
    return Padding(
      padding: const EdgeInsets.fromLTRB(12, 6, 12, 2),
      child: Material(
        color: colors.primaryContainer,
        borderRadius: BorderRadius.circular(24),
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
                    dimension: 56,
                    child: MediaArtwork(
                      item: item,
                      libraryController: scope.libraryController,
                      borderRadius: 16,
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
                                fontWeight: FontWeight.w700,
                              ),
                        ),
                        const SizedBox(height: 2),
                        Text(
                          item.artist ?? item.readableSize,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: Theme.of(context).textTheme.bodySmall,
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
    final controller = player.videoController;
    if (controller == null) {
      return IconButton.filled(
        tooltip: 'Play',
        onPressed: () => unawaited(player.togglePlay()),
        icon: const Icon(Icons.play_arrow_rounded),
      );
    }
    return AnimatedBuilder(
      animation: controller,
      builder: (context, _) {
        final playing = controller.value.isPlaying;
        return IconButton.filled(
          tooltip: playing ? 'Pause' : 'Play',
          onPressed: () => unawaited(player.togglePlay()),
          icon: Icon(playing ? Icons.pause_rounded : Icons.play_arrow_rounded),
        );
      },
    );
  }
}
