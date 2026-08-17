import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:permission_handler/permission_handler.dart';

import '../features/auth/models/auth_models.dart';
import '../features/auth/presentation/auth_screen.dart';
import '../features/library/models/media_item.dart';
import '../features/library/presentation/library_screen.dart';
import '../features/library/presentation/media_artwork.dart';
import '../features/library/presentation/search_screen.dart';
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
  static const int _libraryIndex = 0;
  static const int _searchIndex = 1;
  static const int _settingsIndex = 2;
  static const int _playerIndex = 3;

  int _index = _libraryIndex;
  final List<int> _navigationHistory = <int>[_libraryIndex];
  bool _scheduledStartupChecks = false;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (_scheduledStartupChecks) {
      return;
    }
    _scheduledStartupChecks = true;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) {
        unawaited(_runStartupChecks());
      }
    });
  }

  Future<void> _runStartupChecks() async {
    await _checkNotificationPermissionOnStartup();
    if (mounted) {
      await _checkForUpdateOnStartup();
    }
  }

  Future<void> _checkNotificationPermissionOnStartup() async {
    if (kIsWeb || defaultTargetPlatform != TargetPlatform.android) {
      return;
    }

    final status = await Permission.notification.status;
    if (!mounted || status.isGranted) {
      return;
    }

    final shouldGrant = await showDialog<bool>(
      context: context,
      barrierDismissible: false,
      builder: (dialogContext) {
        return AlertDialog(
          icon: const Icon(Icons.notifications_active_outlined, size: 36),
          title: const Text('Notification permission required'),
          content: const Text(
            'TelePlayer needs notification permission so Android can show '
            'the ongoing playback notification and media controls. TelePlayer '
            'uses a media playback foreground service so songs can continue '
            'playing while the app is in the background.',
          ),
          actions: <Widget>[
            TextButton(
              onPressed: () => Navigator.of(dialogContext).pop(false),
              child: const Text('Skip'),
            ),
            FilledButton(
              onPressed: () => Navigator.of(dialogContext).pop(true),
              child: Text(
                status.isPermanentlyDenied ? 'Open settings' : 'Grant permission',
              ),
            ),
          ],
        );
      },
    );

    if (shouldGrant != true || !mounted) {
      return;
    }

    if (status.isPermanentlyDenied) {
      await openAppSettings();
      return;
    }

    final result = await Permission.notification.request();
    if (!mounted || result.isGranted) {
      return;
    }

    if (result.isPermanentlyDenied) {
      final openSettings = await showDialog<bool>(
        context: context,
        builder: (dialogContext) => AlertDialog(
          title: const Text('Enable notifications in Settings'),
          content: const Text(
            'Android is not allowing TelePlayer notifications. Open the app '
            'settings and enable notifications so the playback notification '
            'and media controls can stay available in the background.',
          ),
          actions: <Widget>[
            TextButton(
              onPressed: () => Navigator.of(dialogContext).pop(false),
              child: const Text('Not now'),
            ),
            FilledButton(
              onPressed: () => Navigator.of(dialogContext).pop(true),
              child: const Text('Open settings'),
            ),
          ],
        ),
      );
      if (openSettings == true) {
        await openAppSettings();
      }
    }
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
            _libraryIndex => authReady
                ? LibraryScreen(
                    onOpenPlayer: () => _navigateTo(_playerIndex),
                  )
                : AuthScreen(
                    onOpenSettings: () => _navigateTo(_settingsIndex),
                  ),
            _searchIndex => authReady
                ? SearchScreen(
                    onOpenPlayer: () => _navigateTo(_playerIndex),
                  )
                : AuthScreen(
                    onOpenSettings: () => _navigateTo(_settingsIndex),
                  ),
            _settingsIndex => SettingsScreen(
                onSaved: () =>
                    unawaited(scope.authController.initialize()),
              ),
            _playerIndex => authReady
                ? PlayerScreen(onClose: _navigateBack)
                : AuthScreen(
                    onOpenSettings: () => _navigateTo(_settingsIndex),
                  ),
            _ => const SizedBox.shrink(),
          };
          return LayoutBuilder(
            builder: (context, constraints) {
              final wide = constraints.maxWidth >= 760;
              if (wide) {
                return Scaffold(
                  body: Row(
                    children: [
                      NavigationRail(
                        selectedIndex: _index == _playerIndex ? null : _index,
                        onDestinationSelected: _navigateTo,
                        labelType: NavigationRailLabelType.all,
                        destinations: const [
                          NavigationRailDestination(
                            icon: Icon(Icons.library_music_outlined),
                            selectedIcon: Icon(Icons.library_music_rounded),
                            label: Text('Library'),
                          ),
                          NavigationRailDestination(
                            icon: Icon(Icons.search_rounded),
                            selectedIcon: Icon(Icons.manage_search_rounded),
                            label: Text('Search'),
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
              final mobilePage = authReady && _index == _playerIndex
                  ? child
                  : Scaffold(
                      body: child,
                      bottomNavigationBar: Column(
                        mainAxisSize: MainAxisSize.min,
                        children: <Widget>[
                          if (authReady &&
                              scope.playerController.item != null &&
                              _index != _playerIndex)
                            _MiniPlayer(
                              onOpenPlayer: () => _navigateTo(_playerIndex),
                              item: scope.playerController.item!,
                              items: scope.libraryController.items,
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
                                icon: Icon(Icons.search_rounded),
                                selectedIcon: Icon(Icons.manage_search_rounded),
                                label: 'Search',
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
              return AnimatedSwitcher(
                duration: const Duration(milliseconds: 420),
                reverseDuration: const Duration(milliseconds: 360),
                switchInCurve: Curves.easeOutCubic,
                switchOutCurve: Curves.easeInCubic,
                layoutBuilder: (currentChild, previousChildren) => Stack(
                  fit: StackFit.expand,
                  children: <Widget>[
                    ...previousChildren,
                    ?currentChild,
                  ],
                ),
                transitionBuilder: (transitionChild, animation) {
                  final key = transitionChild.key;
                  final isPlayer = key is ValueKey<int> &&
                      key.value == _playerIndex;
                  if (isPlayer) {
                    final curved = CurvedAnimation(
                      parent: animation,
                      curve: Curves.easeOutCubic,
                      reverseCurve: Curves.easeInCubic,
                    );
                    return FadeTransition(
                      opacity: curved,
                      child: SlideTransition(
                        position: Tween<Offset>(
                          begin: const Offset(0, 0.045),
                          end: Offset.zero,
                        ).animate(curved),
                        child: ScaleTransition(
                          scale: Tween<double>(begin: 0.985, end: 1).animate(curved),
                          child: transitionChild,
                        ),
                      ),
                    );
                  }
                  return FadeTransition(opacity: animation, child: transitionChild);
                },
                child: KeyedSubtree(
                  key: ValueKey<int>(_index),
                  child: mobilePage,
                ),
              );
            },
          );
        },
      ),
    );
  }

}

class _MiniPlayer extends StatefulWidget {
  const _MiniPlayer({
    required this.onOpenPlayer,
    required this.item,
    required this.items,
  });

  final VoidCallback onOpenPlayer;
  final MediaItem item;
  final List<MediaItem> items;

  @override
  State<_MiniPlayer> createState() => _MiniPlayerState();
}

class _MiniPlayerState extends State<_MiniPlayer>
    with TickerProviderStateMixin {
  static const double _switchVelocity = 500;
  static const double _dismissVelocity = 640;
  static const Duration _switchDuration = Duration(milliseconds: 280);
  static const Duration _snapDuration = Duration(milliseconds: 220);

  late final AnimationController _horizontalController;
  late final AnimationController _verticalController;
  late final ValueNotifier<double> _horizontalOffsetListenable;
  late final ValueNotifier<double> _verticalOffsetListenable;
  late MediaItem _displayedItem;
  Animation<double>? _horizontalAnimation;
  Animation<double>? _verticalAnimation;
  MediaItem? _transitionItem;
  double _transitionDirection = -1;
  double _horizontalOffset = 0;
  double _verticalOffset = 0;
  double _travel = 1;
  double _surfaceHeight = 84;
  String? _pendingSwitchKey;
  bool _dismissed = false;
  bool _acceptingHorizontalDrag = false;
  bool _acceptingVerticalDrag = false;
  int _animationGeneration = 0;
  int _verticalGestureGeneration = 0;

  @override
  void initState() {
    super.initState();
    _displayedItem = widget.item;
    _horizontalOffsetListenable = ValueNotifier<double>(0);
    _verticalOffsetListenable = ValueNotifier<double>(0);
    _horizontalController = AnimationController(
      vsync: this,
      duration: _switchDuration,
    )..addListener(_tickHorizontalAnimation);
    _verticalController = AnimationController(
      vsync: this,
      duration: _snapDuration,
    )..addListener(_tickVerticalAnimation);
  }

  @override
  void didUpdateWidget(covariant _MiniPlayer oldWidget) {
    super.didUpdateWidget(oldWidget);
    final targetKey = widget.item.messageKey;
    if (_dismissed) {
      _dismissed = false;
      _setVerticalOffset(0);
    }

    if (_pendingSwitchKey == targetKey) {
      // open() publishes its target before the native source is ready. Keep
      // the user-controlled slide running instead of restarting it on the
      // loading/buffering rebuild, and retain any refreshed metadata.
      if (_displayedItem.messageKey == targetKey) {
        _displayedItem = widget.item;
      }
      return;
    }

    if (targetKey == _displayedItem.messageKey) {
      _displayedItem = widget.item;
      return;
    }

    if (_transitionItem?.messageKey == targetKey) {
      _transitionItem = widget.item;
      return;
    }

    // A system control or a second track request superseded a swipe that was
    // still settling. Invalidate only that stale visual transaction.
    _pendingSwitchKey = null;
    _acceptingHorizontalDrag = false;
    _animationGeneration += 1;
    _horizontalController.stop();
    _horizontalAnimation = null;
    _setHorizontalOffset(0);
    _transitionItem = widget.item;
    _transitionDirection =
        _adjacentItem(_displayedItem, -1)?.messageKey == targetKey ? 1 : -1;
    final generation = _animationGeneration;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted &&
          generation == _animationGeneration &&
          _transitionItem?.messageKey == targetKey) {
        unawaited(_animateExternalSwitch(targetKey, generation));
      }
    });
  }

  void _tickHorizontalAnimation() {
    final animation = _horizontalAnimation;
    if (!mounted || animation == null) {
      return;
    }
    _setHorizontalOffset(animation.value);
  }

  void _tickVerticalAnimation() {
    final animation = _verticalAnimation;
    if (!mounted || animation == null) {
      return;
    }
    _setVerticalOffset(animation.value);
  }

  void _setHorizontalOffset(double value) {
    _horizontalOffset = value;
    if (_horizontalOffsetListenable.value != value) {
      _horizontalOffsetListenable.value = value;
    }
  }

  void _setVerticalOffset(double value) {
    _verticalOffset = value;
    if (_verticalOffsetListenable.value != value) {
      _verticalOffsetListenable.value = value;
    }
  }

  MediaItem? _adjacentItem(MediaItem current, int direction) {
    final audioItems = widget.items
        .where((candidate) => candidate.kind == MediaKind.audio)
        .toList(growable: false);
    if (audioItems.length < 2) {
      return null;
    }
    final currentIndex = audioItems.indexWhere(
      (candidate) => candidate.messageKey == current.messageKey,
    );
    if (currentIndex < 0) {
      return audioItems.first;
    }
    final rawIndex = (currentIndex + direction) % audioItems.length;
    return audioItems[rawIndex < 0 ? rawIndex + audioItems.length : rawIndex];
  }

  void _handleHorizontalDragStart(DragStartDetails _) {
    _acceptingHorizontalDrag = _pendingSwitchKey == null &&
        _transitionItem == null &&
        _verticalOffset == 0;
    if (!_acceptingHorizontalDrag) {
      return;
    }
    // Let a rapid follow-up gesture take control of a harmless snap-back
    // animation at its current position.
    _horizontalController.stop();
    _horizontalAnimation = null;
  }

  void _handleHorizontalDragUpdate(DragUpdateDetails details) {
    final player = AppScope.of(context).playerController;
    if (!_acceptingHorizontalDrag ||
        _pendingSwitchKey != null ||
        _transitionItem != null ||
        _verticalOffset > 0) {
      return;
    }
    final nextOffset = (_horizontalOffset + details.delta.dx)
        .clamp(-_travel, _travel)
        .toDouble();
    final target = nextOffset < 0
        ? _adjacentItem(_displayedItem, 1)
        : _adjacentItem(_displayedItem, -1);
    if (target == null) {
      return;
    }
    unawaited(player.prepareForTransition(target));
    _setHorizontalOffset(nextOffset);
  }

  Future<void> _handleHorizontalDragEnd(DragEndDetails details) async {
    if (!_acceptingHorizontalDrag) {
      return;
    }
    _acceptingHorizontalDrag = false;
    final player = AppScope.of(context).playerController;
    if (_transitionItem != null || _pendingSwitchKey != null) {
      return;
    }
    final velocity = details.primaryVelocity ?? 0;
    final crossedDistance = _horizontalOffset.abs() >= _travel * 0.18;
    final crossedVelocity = velocity.abs() >= _switchVelocity;
    final direction = crossedVelocity ? velocity.sign : _horizontalOffset.sign;
    final target = direction < 0
        ? _adjacentItem(_displayedItem, 1)
        : _adjacentItem(_displayedItem, -1);
    if ((!crossedDistance && !crossedVelocity) || target == null) {
      await _animateHorizontal(_horizontalOffset, 0, _snapDuration);
      return;
    }

    // Start the serialized append/seek handoff as soon as the swipe commits.
    // PlayerController keeps the old source playing while it prepares this
    // target, so the visual settle time no longer adds an avoidable audio gap.
    unawaited(player.prepareForTransition(target));
    final targetKey = target.messageKey;
    _pendingSwitchKey = targetKey;
    unawaited(player.open(target));
    final destination = direction < 0 ? -_travel : _travel;
    await _animateHorizontal(
      _horizontalOffset,
      destination,
      _switchDuration,
    );
    if (!mounted || _pendingSwitchKey != targetKey) {
      return;
    }
    setState(() {
      _displayedItem = widget.item.messageKey == targetKey
          ? widget.item
          : target;
      _transitionItem = null;
      _pendingSwitchKey = null;
      _horizontalAnimation = null;
      _setHorizontalOffset(0);
    });
  }

  void _handleHorizontalDragCancel() {
    final wasAccepted = _acceptingHorizontalDrag;
    _acceptingHorizontalDrag = false;
    if (wasAccepted && _transitionItem == null && _pendingSwitchKey == null) {
      unawaited(_animateHorizontal(_horizontalOffset, 0, _snapDuration));
    }
  }

  void _handleVerticalDragStart(DragStartDetails _) {
    _verticalGestureGeneration += 1;
    _acceptingVerticalDrag = _pendingSwitchKey == null &&
        _transitionItem == null &&
        !_horizontalController.isAnimating &&
        _horizontalOffset == 0;
    if (!_acceptingVerticalDrag) {
      return;
    }
    // A new pull can grab the mini-player while it is springing back. Stopping
    // the old ticker prevents it from fighting the user's finger.
    _verticalController.stop();
    _verticalAnimation = null;
  }

  void _handleVerticalDragUpdate(DragUpdateDetails details) {
    if (!_acceptingVerticalDrag ||
        _horizontalController.isAnimating ||
        _transitionItem != null) {
      return;
    }
    var nextOffset = _verticalOffset + (details.primaryDelta ?? details.delta.dy);
    if (nextOffset < 0) {
      nextOffset *= 0.08;
    }
    nextOffset = nextOffset.clamp(0.0, _surfaceHeight).toDouble();
    _setVerticalOffset(nextOffset);
  }

  Future<void> _handleVerticalDragEnd(DragEndDetails details) async {
    if (!_acceptingVerticalDrag) {
      return;
    }
    _acceptingVerticalDrag = false;
    final gestureGeneration = _verticalGestureGeneration;
    if (_horizontalController.isAnimating || _transitionItem != null) {
      return;
    }
    final velocity = details.primaryVelocity ?? 0;
    final projectedOffset = _verticalOffset + (velocity * 0.12);
    final shouldDismiss = projectedOffset >= _surfaceHeight * 0.42 ||
        velocity >= _dismissVelocity;
    if (!shouldDismiss) {
      await _animateVertical(0, _snapDuration);
      return;
    }
    await _animateVertical(_surfaceHeight, const Duration(milliseconds: 240));
    if (mounted && gestureGeneration == _verticalGestureGeneration) {
      setState(() => _dismissed = true);
    }
  }

  void _handleVerticalDragCancel() {
    final wasAccepted = _acceptingVerticalDrag;
    _acceptingVerticalDrag = false;
    if (wasAccepted) {
      unawaited(_animateVertical(0, _snapDuration));
    }
  }

  Future<void> _animateExternalSwitch(String targetKey, int generation) async {
    final target = _transitionItem;
    if (target == null || target.messageKey != targetKey) {
      return;
    }
    final destination = _transitionDirection < 0 ? -_travel : _travel;
    await _animateHorizontal(0, destination, _switchDuration);
    if (!mounted ||
        generation != _animationGeneration ||
        _transitionItem?.messageKey != targetKey) {
      return;
    }
    setState(() {
      _displayedItem = target;
      _transitionItem = null;
      _horizontalAnimation = null;
      _setHorizontalOffset(0);
    });
  }

  Future<void> _animateHorizontal(
    double from,
    double to,
    Duration duration,
  ) async {
    _horizontalController
      ..stop()
      ..duration = duration;
    _horizontalAnimation = Tween<double>(begin: from, end: to).animate(
      CurvedAnimation(parent: _horizontalController, curve: Curves.easeOutCubic),
    );
    try {
      await _horizontalController.forward(from: 0).orCancel;
    } on TickerCanceled {
      // A newer controller item superseded this visual transition.
    }
  }

  Future<void> _animateVertical(double target, Duration duration) async {
    _verticalController
      ..stop()
      ..duration = duration;
    _verticalAnimation = Tween<double>(
      begin: _verticalOffset,
      end: target,
    ).animate(
      CurvedAnimation(parent: _verticalController, curve: Curves.easeOutCubic),
    );
    try {
      await _verticalController.forward(from: 0).orCancel;
    } on TickerCanceled {
      // A new drag takes control from the settling animation.
    }
  }

  @override
  void dispose() {
    _animationGeneration += 1;
    _verticalGestureGeneration += 1;
    _horizontalController
      ..removeListener(_tickHorizontalAnimation)
      ..dispose();
    _verticalController
      ..removeListener(_tickVerticalAnimation)
      ..dispose();
    _horizontalOffsetListenable.dispose();
    _verticalOffsetListenable.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final scope = AppScope.of(context);
    final player = scope.playerController;
    final colors = Theme.of(context).colorScheme;
    final surfaceColor = Color.alphaBlend(
      colors.primary.withValues(alpha: 0.14),
      colors.surfaceContainerHigh,
    );

    if (_dismissed) {
      return const SizedBox.shrink();
    }

    return LayoutBuilder(
      builder: (context, constraints) {
        _travel = (constraints.maxWidth - 24).clamp(1.0, double.infinity);
        // 76 logical pixels of material plus the surrounding 6/2 padding.
        // The layout collapses by this exact amount as the card moves behind
        // the navigation bar, so there is no jump at dismissal time.
        _surfaceHeight = 84;

        MediaItem? leftItem;
        MediaItem? rightItem;
        if (_transitionItem != null) {
          if (_transitionDirection > 0) {
            leftItem = _transitionItem;
          } else {
            rightItem = _transitionItem;
          }
        } else {
          leftItem = _adjacentItem(_displayedItem, -1);
          rightItem = _adjacentItem(_displayedItem, 1);
        }

        Widget card(MediaItem item, {required bool interactive}) {
          return SizedBox(
            width: _travel,
            height: 74,
            child: IgnorePointer(
              ignoring: !interactive,
              child: InkWell(
                onTap: widget.onOpenPlayer,
                child: Padding(
                  padding: const EdgeInsets.fromLTRB(12, 8, 8, 8),
                  child: Row(
                    children: <Widget>[
                      SizedBox.square(
                        dimension: 58,
                        child: MediaArtwork(
                          key: ValueKey<String>(
                            'mini-art-${item.messageKey}',
                          ),
                          item: item,
                          libraryController: scope.libraryController,
                          borderRadius: 18,
                          iconSize: 24,
                        ),
                      ),
                      const SizedBox(width: 12),
                      Expanded(
                        child: Column(
                          mainAxisAlignment: MainAxisAlignment.center,
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: <Widget>[
                            Text(
                              item.title,
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              style: Theme.of(context)
                                  .textTheme
                                  .titleSmall
                                  ?.copyWith(
                                    fontWeight: FontWeight.w800,
                                    letterSpacing: 0,
                                  ),
                            ),
                            const SizedBox(height: 2),
                            Text(
                              item.artist ?? item.readableSize,
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              style: Theme.of(context)
                                  .textTheme
                                  .bodySmall
                                  ?.copyWith(
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
              ),
            ),
          );
        }

        Widget cardOrSpace(MediaItem? item, {required bool interactive}) {
          return item == null
              ? SizedBox(width: _travel, height: 74)
              : card(item, interactive: interactive);
        }

        final strip = SizedBox(
          width: _travel * 3,
          height: 74,
          child: Row(
            children: <Widget>[
              cardOrSpace(leftItem, interactive: false),
              card(_displayedItem, interactive: true),
              cardOrSpace(rightItem, interactive: false),
            ],
          ),
        );
        final horizontalCarousel = SizedBox(
          height: 74,
          child: ClipRect(
            child: ValueListenableBuilder<double>(
              valueListenable: _horizontalOffsetListenable,
              child: strip,
              builder: (context, horizontalOffset, child) {
                return Transform.translate(
                  offset: Offset(-_travel + horizontalOffset, 0),
                  child: OverflowBox(
                    alignment: Alignment.centerLeft,
                    minWidth: _travel * 3,
                    maxWidth: _travel * 3,
                    minHeight: 74,
                    maxHeight: 74,
                    child: child,
                  ),
                );
              },
            ),
          ),
        );
        final surface = GestureDetector(
          behavior: HitTestBehavior.translucent,
          onHorizontalDragStart: _handleHorizontalDragStart,
          onHorizontalDragUpdate: _handleHorizontalDragUpdate,
          onHorizontalDragEnd: _handleHorizontalDragEnd,
          onHorizontalDragCancel: _handleHorizontalDragCancel,
          onVerticalDragStart: _handleVerticalDragStart,
          onVerticalDragUpdate: _handleVerticalDragUpdate,
          onVerticalDragEnd: _handleVerticalDragEnd,
          onVerticalDragCancel: _handleVerticalDragCancel,
          child: Padding(
            padding: const EdgeInsets.fromLTRB(12, 6, 12, 2),
            child: Material(
              color: surfaceColor,
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(28),
                side: BorderSide(
                  color: colors.outlineVariant.withValues(alpha: 0.28),
                ),
              ),
              clipBehavior: Clip.antiAlias,
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: <Widget>[
                  SizedBox(
                    height: 2,
                    child: player.isLoading
                        ? const LinearProgressIndicator(minHeight: 2)
                        : null,
                  ),
                  horizontalCarousel,
                ],
              ),
            ),
          ),
        );

        // Only the lightweight clip/transform wrapper rebuilds on animation
        // ticks. Artwork and controls remain as stable children, avoiding the
        // per-frame FutureBuilder churn that made rapid swipes look jittery.
        return ValueListenableBuilder<double>(
          valueListenable: _verticalOffsetListenable,
          child: surface,
          builder: (context, verticalOffset, child) {
            final verticalProgress =
                (verticalOffset / _surfaceHeight).clamp(0.0, 1.0);
            return ClipRect(
              child: Align(
                alignment: Alignment.topCenter,
                heightFactor: 1 - verticalProgress,
                child: Opacity(
                  opacity: 1 - (verticalProgress * 0.28),
                  child: Transform.scale(
                    scale: 1 - (verticalProgress * 0.018),
                    alignment: Alignment.bottomCenter,
                    child: child,
                  ),
                ),
              ),
            );
          },
        );
      },
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
