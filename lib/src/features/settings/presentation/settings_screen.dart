import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:permission_handler/permission_handler.dart';

import '../../../app/app_scope.dart';
import '../../../app/error_panel.dart';
import '../../update/application/app_update_controller.dart';
import '../../update/presentation/app_update_sheet.dart';
import '../models/app_settings.dart';

class SettingsScreen extends StatelessWidget {
  const SettingsScreen({this.onSaved, super.key});

  final VoidCallback? onSaved;

  bool get _showWindowsTdjsonPath =>
      defaultTargetPlatform == TargetPlatform.windows;

  @override
  Widget build(BuildContext context) {
    final scope = AppScope.of(context);
    final settingsController = scope.settingsController;
    final settings = settingsController.settings;
    final colors = Theme.of(context).colorScheme;

    return Scaffold(
      body: DecoratedBox(
        decoration: _settingsBackground(colors),
        child: SafeArea(
          child: Center(
            child: ListView(
              padding: const EdgeInsets.fromLTRB(16, 16, 16, 24),
              children: <Widget>[
                Center(
                  child: ConstrainedBox(
                    constraints: const BoxConstraints(maxWidth: 760),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: <Widget>[
                        Text(
                          'Settings',
                          style: Theme.of(context).textTheme.displaySmall?.copyWith(
                                fontWeight: FontWeight.w900,
                                letterSpacing: 0,
                              ),
                        ),
                        const SizedBox(height: 16),
                        if (settingsController.error != null) ...<Widget>[
                          ErrorPanel(error: settingsController.error!),
                          const SizedBox(height: 16),
                        ],
                        _SettingsDestinationCard(
                          icon: Icons.key_rounded,
                          title: 'Telegram',
                          subtitle: 'Account, API credentials and channel access',
                          onTap: () => _open(
                            context,
                            TelegramSettingsPage(onSaved: onSaved),
                          ),
                        ),
                        const SizedBox(height: 4),
                        _SettingsDestinationCard(
                          icon: Icons.tune_rounded,
                          title: 'Playback',
                          subtitle: 'Streaming, network and temporary storage',
                          onTap: () => _open(
                            context,
                            const PlaybackSettingsPage(),
                          ),
                        ),
                        const SizedBox(height: 4),
                        _SettingsDestinationCard(
                          icon: Icons.battery_saver_rounded,
                          title: 'Background activity',
                          subtitle: 'Battery optimization and uninterrupted playback',
                          onTap: () => _open(
                            context,
                            const BackgroundActivitySettingsPage(),
                          ),
                        ),
                        const SizedBox(height: 4),
                        _SettingsDestinationCard(
                          icon: Icons.system_update_alt_rounded,
                          title: 'Updates',
                          subtitle: 'GitHub release checks and downloads',
                          onTap: () => _open(
                            context,
                            const UpdatesSettingsPage(),
                          ),
                        ),
                        if (_showWindowsTdjsonPath) ...<Widget>[
                          const SizedBox(height: 4),
                          _SettingsDestinationCard(
                            icon: Icons.desktop_windows_rounded,
                            title: 'Windows',
                            subtitle: 'Local TDLib runtime configuration',
                            onTap: () => _open(
                              context,
                              WindowsSettingsPage(onSaved: onSaved),
                            ),
                          ),
                        ],
                      ],
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

  void _open(BuildContext context, Widget page) {
    unawaited(
      Navigator.of(context).push<void>(
        MaterialPageRoute<void>(builder: (_) => page),
      ),
    );
  }

}

class TelegramSettingsPage extends StatefulWidget {
  const TelegramSettingsPage({this.onSaved, super.key});

  final VoidCallback? onSaved;

  @override
  State<TelegramSettingsPage> createState() => _TelegramSettingsPageState();
}

class _TelegramSettingsPageState extends State<TelegramSettingsPage> {
  final _apiIdController = TextEditingController();
  final _apiHashController = TextEditingController();
  final _channelsController = TextEditingController();
  bool _seeded = false;
  bool _saving = false;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (_seeded) {
      return;
    }
    final settings = AppScope.of(context).settingsController.settings;
    _apiIdController.text = settings.apiId?.toString() ?? '';
    _apiHashController.text = settings.apiHash ?? '';
    _channelsController.text = settings.channelIds.join(', ');
    _seeded = true;
  }

  @override
  void dispose() {
    _apiIdController.dispose();
    _apiHashController.dispose();
    _channelsController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return _SettingsDetailScaffold(
      title: 'Telegram',
      subtitle: 'Account and channel access',
      icon: Icons.key_rounded,
      saving: _saving,
      onSave: _saving ? null : () => unawaited(_save()),
      children: <Widget>[
        TextField(
          controller: _apiIdController,
          keyboardType: TextInputType.number,
          decoration: const InputDecoration(
            labelText: 'Telegram API ID',
            prefixIcon: Icon(Icons.numbers_outlined),
          ),
        ),
        const SizedBox(height: 12),
        TextField(
          controller: _apiHashController,
          obscureText: true,
          decoration: const InputDecoration(
            labelText: 'Telegram API hash',
            prefixIcon: Icon(Icons.key_outlined),
          ),
        ),
        const SizedBox(height: 12),
        TextField(
          controller: _channelsController,
          decoration: const InputDecoration(
            labelText: 'Channel IDs',
            helperText: 'Separate multiple Telegram channel IDs with commas.',
            prefixIcon: Icon(Icons.forum_outlined),
          ),
        ),
      ],
    );
  }

  Future<void> _save() async {
    final settingsController = AppScope.of(context).settingsController;
    final current = settingsController.settings;
    final channels = _channelsController.text
        .split(',')
        .map((part) => int.tryParse(part.trim()))
        .whereType<int>()
        .toSet()
        .toList(growable: false);

    setState(() => _saving = true);
    await settingsController.save(
      AppSettings(
        apiId: int.tryParse(_apiIdController.text.trim()),
        apiHash: _apiHashController.text.trim(),
        channelIds: channels,
        cacheLimitMb: current.cacheLimitMb,
        preferWifi: current.preferWifi,
        windowsTdjsonPath: current.windowsTdjsonPath,
      ),
    );
    if (!mounted) {
      return;
    }
    setState(() => _saving = false);
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(content: Text('Telegram settings saved')),
    );
    widget.onSaved?.call();
  }
}

class PlaybackSettingsPage extends StatefulWidget {
  const PlaybackSettingsPage({super.key});

  @override
  State<PlaybackSettingsPage> createState() => _PlaybackSettingsPageState();
}

class _PlaybackSettingsPageState extends State<PlaybackSettingsPage> {
  final _cacheController = TextEditingController();
  bool _preferWifi = true;
  bool _seeded = false;
  bool _saving = false;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (_seeded) {
      return;
    }
    final settings = AppScope.of(context).settingsController.settings;
    _cacheController.text = settings.cacheLimitMb.toString();
    _preferWifi = settings.preferWifi;
    _seeded = true;
  }

  @override
  void dispose() {
    _cacheController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return _SettingsDetailScaffold(
      title: 'Playback',
      subtitle: 'Streaming and temporary storage',
      icon: Icons.tune_rounded,
      saving: _saving,
      onSave: _saving ? null : () => unawaited(_save()),
      children: <Widget>[
        const _SettingsInfoCard(
          icon: Icons.cleaning_services_rounded,
          title: 'Temporary song storage',
          body:
              'TelePlayer downloads only what playback needs. The TDLib media file is automatically removed from local storage after the song finishes or when you switch to another song. Album artwork and the library catalog remain cached so the interface stays fast.',
        ),
        const SizedBox(height: 14),
        TextField(
          controller: _cacheController,
          keyboardType: TextInputType.number,
          decoration: const InputDecoration(
            labelText: 'Cache limit MB',
            helperText:
                'Completed song audio is removed separately and is never retained by this setting.',
            prefixIcon: Icon(Icons.storage_outlined),
          ),
        ),
        const SizedBox(height: 10),
        SwitchListTile.adaptive(
          value: _preferWifi,
          onChanged: (value) => setState(() => _preferWifi = value),
          contentPadding: const EdgeInsets.symmetric(horizontal: 6),
          title: const Text('Prefer Wi-Fi'),
          subtitle: const Text('Prefer Wi-Fi for large Telegram media transfers.'),
          secondary: const Icon(Icons.wifi_outlined),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(24),
          ),
        ),
        const SizedBox(height: 10),
        Material(
          color: Theme.of(context).colorScheme.surfaceContainerHigh,
          borderRadius: BorderRadius.circular(24),
          clipBehavior: Clip.antiAlias,
          child: ListTile(
            onTap: () => unawaited(
              Navigator.of(context).push<void>(
                MaterialPageRoute<void>(
                  builder: (_) => const BackgroundActivitySettingsPage(),
                ),
              ),
            ),
            leading: const Icon(Icons.battery_saver_rounded),
            title: const Text('Background activity'),
            subtitle: const Text(
              'Battery optimization settings for smoother background playback.',
            ),
            trailing: const Icon(Icons.chevron_right_rounded),
          ),
        ),
      ],
    );
  }

  Future<void> _save() async {
    final settingsController = AppScope.of(context).settingsController;
    final current = settingsController.settings;
    final parsedCache = int.tryParse(_cacheController.text.trim());
    final cacheLimit = (parsedCache ?? current.cacheLimitMb).clamp(128, 32768).toInt();

    setState(() => _saving = true);
    await settingsController.save(
      AppSettings(
        apiId: current.apiId,
        apiHash: current.apiHash,
        channelIds: current.channelIds,
        cacheLimitMb: cacheLimit,
        preferWifi: _preferWifi,
        windowsTdjsonPath: current.windowsTdjsonPath,
      ),
    );
    if (!mounted) {
      return;
    }
    _cacheController.text = cacheLimit.toString();
    setState(() => _saving = false);
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(content: Text('Playback settings saved')),
    );
  }
}


class BackgroundActivitySettingsPage extends StatefulWidget {
  const BackgroundActivitySettingsPage({super.key});

  @override
  State<BackgroundActivitySettingsPage> createState() =>
      _BackgroundActivitySettingsPageState();
}

class _BackgroundActivitySettingsPageState
    extends State<BackgroundActivitySettingsPage> {
  PermissionStatus? _status;
  bool _busy = false;

  @override
  void initState() {
    super.initState();
    unawaited(_refreshStatus());
  }

  Future<void> _refreshStatus() async {
    if (kIsWeb || defaultTargetPlatform != TargetPlatform.android) {
      if (mounted) {
        setState(() => _status = PermissionStatus.granted);
      }
      return;
    }
    final status = await Permission.ignoreBatteryOptimizations.status;
    if (!mounted) {
      return;
    }
    setState(() => _status = status);
  }

  Future<void> _requestOrOpenSettings() async {
    if (kIsWeb || defaultTargetPlatform != TargetPlatform.android) {
      return;
    }
    final currentStatus = _status ?? await Permission.ignoreBatteryOptimizations.status;
    setState(() => _busy = true);
    try {
      if (currentStatus.isGranted) {
        await _refreshStatus();
      } else if (currentStatus.isPermanentlyDenied) {
        await openAppSettings();
      } else {
        final result = await Permission.ignoreBatteryOptimizations.request();
        if (!mounted) {
          return;
        }
        setState(() => _status = result);
        if (!result.isGranted && result.isPermanentlyDenied) {
          await openAppSettings();
          await _refreshStatus();
        }
      }
    } finally {
      if (mounted) {
        setState(() => _busy = false);
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).colorScheme;
    final unsupported = kIsWeb || defaultTargetPlatform != TargetPlatform.android;
    final status = _status;
    final isGranted = status?.isGranted == true || unsupported;
    final statusColor = isGranted
        ? Colors.green.shade700
        : colors.secondary;
    final statusLabel = unsupported
        ? 'Not needed on this device'
        : status == null
            ? 'Checking permission…'
            : isGranted
                ? 'Permission granted'
                : status.isPermanentlyDenied
                    ? 'Open Android settings'
                    : 'Not granted';

    return _SettingsDetailScaffold(
      title: 'Background activity',
      subtitle: 'Battery optimization and uninterrupted playback',
      icon: Icons.battery_saver_rounded,
      children: <Widget>[
        const _SettingsInfoCard(
          icon: Icons.info_outline_rounded,
          title: 'Why this matters',
          body:
              'Some Android devices aggressively limit background activity to save battery. Allowing TelePlayer to ignore battery optimization can reduce the chance of background playback being interrupted while the screen is off or the app is not open.',
        ),
        const SizedBox(height: 14),
        Container(
          padding: const EdgeInsets.all(16),
          decoration: BoxDecoration(
            color: colors.surfaceContainerHigh,
            borderRadius: BorderRadius.circular(24),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: <Widget>[
              Row(
                children: <Widget>[
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: <Widget>[
                        Text(
                          'Ignore battery optimization',
                          style: Theme.of(context).textTheme.titleMedium?.copyWith(
                                fontWeight: FontWeight.w800,
                              ),
                        ),
                        const SizedBox(height: 6),
                        Text(
                          statusLabel,
                          style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                                color: statusColor,
                                fontWeight: FontWeight.w700,
                              ),
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(width: 12),
                  FilledButton.icon(
                    onPressed: unsupported || _busy ? null : _requestOrOpenSettings,
                    icon: _busy
                        ? const SizedBox.square(
                            dimension: 18,
                            child: CircularProgressIndicator(strokeWidth: 2),
                          )
                        : Icon(
                            isGranted ? Icons.settings_outlined : Icons.battery_saver_outlined,
                          ),
                    label: Text(
                      unsupported
                          ? 'Unavailable'
                          : isGranted
                              ? 'Refresh'
                              : status?.isPermanentlyDenied == true
                                  ? 'Open settings'
                                  : 'Allow',
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 12),
              Text(
                unsupported
                    ? 'Battery optimization exemptions are only relevant on Android devices.'
                    : 'TelePlayer already keeps a foreground media playback notification active. This option adds another layer of protection on devices that still pause apps too aggressively.',
                style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                      color: colors.onSurfaceVariant,
                    ),
              ),
            ],
          ),
        ),
      ],
    );
  }
}

class UpdatesSettingsPage extends StatelessWidget {
  const UpdatesSettingsPage({super.key});

  @override
  Widget build(BuildContext context) {
    final controller = AppScope.of(context).updateController;
    return _SettingsDetailScaffold(
      title: 'Updates',
      subtitle: 'GitHub release checks',
      icon: Icons.system_update_alt_rounded,
      children: <Widget>[
        _AppUpdateTile(
          controller: controller,
          onPressed: () => unawaited(_checkForUpdates(context, controller)),
        ),
        const SizedBox(height: 14),
        const _SettingsInfoCard(
          icon: Icons.verified_user_outlined,
          title: 'Release source',
          body:
              'TelePlayer checks the configured GitHub repository for newer stable releases and opens the matching installer or APK when one is available.',
        ),
      ],
    );
  }

  Future<void> _checkForUpdates(
    BuildContext context,
    AppUpdateController controller,
  ) async {
    final update = await controller.check();
    if (!context.mounted) {
      return;
    }
    if (update != null) {
      await showAppUpdateSheet(
        context,
        controller: controller,
        update: update,
      );
      return;
    }
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(
          controller.message ?? 'TelePlayer could not check for updates.',
        ),
      ),
    );
  }
}

class WindowsSettingsPage extends StatefulWidget {
  const WindowsSettingsPage({this.onSaved, super.key});

  final VoidCallback? onSaved;

  @override
  State<WindowsSettingsPage> createState() => _WindowsSettingsPageState();
}

class _WindowsSettingsPageState extends State<WindowsSettingsPage> {
  final _tdjsonController = TextEditingController();
  bool _seeded = false;
  bool _saving = false;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (_seeded) {
      return;
    }
    _tdjsonController.text =
        AppScope.of(context).settingsController.settings.windowsTdjsonPath ?? '';
    _seeded = true;
  }

  @override
  void dispose() {
    _tdjsonController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return _SettingsDetailScaffold(
      title: 'Windows',
      subtitle: 'Local TDLib runtime',
      icon: Icons.desktop_windows_rounded,
      saving: _saving,
      onSave: _saving ? null : () => unawaited(_save()),
      children: <Widget>[
        TextField(
          controller: _tdjsonController,
          decoration: const InputDecoration(
            labelText: 'TDJSON DLL path',
            hintText: r'C:\tdlib\bin\tdjson.dll',
            helperText: 'Leave blank to use TelePlayer\'s automatic runtime path.',
            prefixIcon: Icon(Icons.folder_open_outlined),
          ),
        ),
      ],
    );
  }

  Future<void> _save() async {
    final settingsController = AppScope.of(context).settingsController;
    final current = settingsController.settings;
    final rawPath = _tdjsonController.text.trim();

    setState(() => _saving = true);
    await settingsController.save(
      AppSettings(
        apiId: current.apiId,
        apiHash: current.apiHash,
        channelIds: current.channelIds,
        cacheLimitMb: current.cacheLimitMb,
        preferWifi: current.preferWifi,
        windowsTdjsonPath: rawPath.isEmpty ? null : rawPath,
      ),
    );
    if (!mounted) {
      return;
    }
    setState(() => _saving = false);
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(content: Text('Windows settings saved')),
    );
    widget.onSaved?.call();
  }
}

class _SettingsDetailScaffold extends StatelessWidget {
  const _SettingsDetailScaffold({
    required this.title,
    required this.subtitle,
    required this.icon,
    required this.children,
    this.saving = false,
    this.onSave,
  });

  final String title;
  final String subtitle;
  final IconData icon;
  final List<Widget> children;
  final bool saving;
  final VoidCallback? onSave;

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).colorScheme;
    return Scaffold(
      appBar: AppBar(
        title: Text(title),
        actions: onSave == null
            ? null
            : <Widget>[
                Padding(
                  padding: const EdgeInsets.only(right: 12),
                  child: FilledButton.icon(
                    onPressed: onSave,
                    icon: saving
                        ? const SizedBox.square(
                            dimension: 18,
                            child: CircularProgressIndicator(strokeWidth: 2),
                          )
                        : const Icon(Icons.save_outlined),
                    label: const Text('Save'),
                  ),
                ),
              ],
      ),
      body: DecoratedBox(
        decoration: _settingsBackground(colors),
        child: SafeArea(
          top: false,
          child: Center(
            child: ListView(
              padding: const EdgeInsets.fromLTRB(20, 18, 20, 32),
              children: <Widget>[
                Center(
                  child: ConstrainedBox(
                    constraints: const BoxConstraints(maxWidth: 760),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: <Widget>[
                        _DetailHeader(icon: icon, title: title, subtitle: subtitle),
                        const SizedBox(height: 18),
                        Material(
                          color: colors.surfaceContainer.withValues(alpha: 0.90),
                          borderRadius: BorderRadius.circular(32),
                          clipBehavior: Clip.antiAlias,
                          child: Padding(
                            padding: const EdgeInsets.all(18),
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.stretch,
                              children: children,
                            ),
                          ),
                        ),
                      ],
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

class _DetailHeader extends StatelessWidget {
  const _DetailHeader({
    required this.icon,
    required this.title,
    required this.subtitle,
  });

  final IconData icon;
  final String title;
  final String subtitle;

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).colorScheme;
    return Row(
      children: <Widget>[
        Container(
          width: 64,
          height: 64,
          decoration: BoxDecoration(
            color: colors.primaryContainer,
            borderRadius: BorderRadius.circular(24),
          ),
          child: Icon(icon, color: colors.onPrimaryContainer, size: 34),
        ),
        const SizedBox(width: 16),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: <Widget>[
              Text(
                title,
                style: Theme.of(context).textTheme.headlineSmall?.copyWith(
                      fontWeight: FontWeight.w900,
                      letterSpacing: 0,
                    ),
              ),
              const SizedBox(height: 3),
              Text(
                subtitle,
                style: Theme.of(context).textTheme.bodyLarge?.copyWith(
                      color: colors.onSurfaceVariant,
                    ),
              ),
            ],
          ),
        ),
      ],
    );
  }
}

class _SettingsDestinationCard extends StatelessWidget {
  const _SettingsDestinationCard({
    required this.icon,
    required this.title,
    required this.subtitle,
    required this.onTap,
  });

  final IconData icon;
  final String title;
  final String subtitle;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).colorScheme;
    return Material(
      color: colors.surfaceContainer.withValues(alpha: 0.90),
      borderRadius: BorderRadius.circular(18),
      clipBehavior: Clip.antiAlias,
      child: InkWell(
        onTap: onTap,
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
          child: Row(
            children: <Widget>[
              Container(
                width: 48,
                height: 48,
                decoration: BoxDecoration(
                  color: colors.primaryContainer,
                  borderRadius: BorderRadius.circular(16),
                ),
                child: Icon(icon, color: colors.onPrimaryContainer, size: 25),
              ),
              const SizedBox(width: 14),
              Expanded(
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: <Widget>[
                    Text(
                      title,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: Theme.of(context).textTheme.titleMedium?.copyWith(
                            fontWeight: FontWeight.w800,
                            letterSpacing: 0,
                          ),
                    ),
                    const SizedBox(height: 1),
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
              const SizedBox(width: 8),
              Icon(
                Icons.chevron_right_rounded,
                size: 22,
                color: colors.onSurfaceVariant,
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _SettingsInfoCard extends StatelessWidget {
  const _SettingsInfoCard({
    required this.icon,
    required this.title,
    required this.body,
  });

  final IconData icon;
  final String title;
  final String body;

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).colorScheme;
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: colors.surfaceContainerHigh,
        borderRadius: BorderRadius.circular(24),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: <Widget>[
          Icon(icon, color: colors.primary),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: <Widget>[
                Text(
                  title,
                  style: Theme.of(context).textTheme.titleMedium?.copyWith(
                        fontWeight: FontWeight.w800,
                      ),
                ),
                const SizedBox(height: 5),
                Text(
                  body,
                  style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                        color: colors.onSurfaceVariant,
                      ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _AppUpdateTile extends StatelessWidget {
  const _AppUpdateTile({
    required this.controller,
    required this.onPressed,
  });

  final AppUpdateController controller;
  final VoidCallback onPressed;

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).colorScheme;
    return AnimatedBuilder(
      animation: controller,
      builder: (context, _) {
        final isChecking = controller.status == AppUpdateStatus.checking;
        final subtitle = switch (controller.status) {
          AppUpdateStatus.checking => 'Checking GitHub releases...',
          AppUpdateStatus.upToDate =>
            controller.message ?? 'TelePlayer is up to date.',
          AppUpdateStatus.updateAvailable =>
            controller.message ?? 'A newer TelePlayer release is available.',
          AppUpdateStatus.error =>
            controller.message ?? 'The update check failed.',
          AppUpdateStatus.opening => 'Opening the update download...',
          AppUpdateStatus.idle => 'Check for a newer GitHub release',
        };
        return Material(
          color: colors.surfaceContainerHigh,
          borderRadius: BorderRadius.circular(26),
          clipBehavior: Clip.antiAlias,
          child: ListTile(
            onTap: controller.isBusy ? null : onPressed,
            contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
            leading: const Icon(Icons.system_update_alt_rounded),
            title: const Text('Check for updates'),
            subtitle: Text(subtitle),
            trailing: isChecking
                ? const SizedBox.square(
                    dimension: 22,
                    child: CircularProgressIndicator(strokeWidth: 2.5),
                  )
                : const Icon(Icons.chevron_right_rounded),
          ),
        );
      },
    );
  }
}

BoxDecoration _settingsBackground(ColorScheme colors) {
  return BoxDecoration(
    gradient: LinearGradient(
      begin: Alignment.topCenter,
      end: Alignment.bottomCenter,
      colors: <Color>[
        colors.secondaryContainer.withValues(alpha: 0.44),
        colors.surface,
        colors.surface,
      ],
      stops: const <double>[0, 0.42, 1],
    ),
  );
}
