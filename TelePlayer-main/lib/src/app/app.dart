import 'dart:async';

import 'package:flutter/material.dart';

import '../features/auth/models/auth_models.dart';
import '../features/auth/presentation/auth_screen.dart';
import '../features/library/presentation/library_screen.dart';
import '../features/player/presentation/player_screen.dart';
import '../features/settings/presentation/settings_screen.dart';
import 'app_scope.dart';

class TelegramMediaPlayerApp extends StatelessWidget {
  const TelegramMediaPlayerApp({super.key});

  @override
  Widget build(BuildContext context) {
    const seed = Color(0xFF126C71);
    return MaterialApp(
      title: 'Telegram Media Player',
      debugShowCheckedModeBanner: false,
      theme: ThemeData(
        colorScheme: ColorScheme.fromSeed(seedColor: seed, brightness: Brightness.light),
        useMaterial3: true,
      ),
      darkTheme: ThemeData(
        colorScheme: ColorScheme.fromSeed(seedColor: seed, brightness: Brightness.dark),
        useMaterial3: true,
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
              ? LibraryScreen(onOpenPlayer: () => setState(() => _index = 1))
              : AuthScreen(onOpenSettings: () => setState(() => _index = 2)),
          1 => authReady ? const PlayerScreen() : AuthScreen(onOpenSettings: () => setState(() => _index = 2)),
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
                          icon: Icon(Icons.video_library_outlined),
                          selectedIcon: Icon(Icons.video_library),
                          label: Text('Library'),
                        ),
                        NavigationRailDestination(
                          icon: Icon(Icons.smart_display_outlined),
                          selectedIcon: Icon(Icons.smart_display),
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
            return Scaffold(
              body: child,
              bottomNavigationBar: NavigationBar(
                selectedIndex: _index,
                onDestinationSelected: (value) => setState(() => _index = value),
                destinations: const [
                  NavigationDestination(
                    icon: Icon(Icons.video_library_outlined),
                    selectedIcon: Icon(Icons.video_library),
                    label: 'Library',
                  ),
                  NavigationDestination(
                    icon: Icon(Icons.smart_display_outlined),
                    selectedIcon: Icon(Icons.smart_display),
                    label: 'Player',
                  ),
                  NavigationDestination(
                    icon: Icon(Icons.settings_outlined),
                    selectedIcon: Icon(Icons.settings),
                    label: 'Settings',
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
