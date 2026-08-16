import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';

import '../../../app/app_scope.dart';
import '../../../app/error_panel.dart';
import '../../update/application/app_update_controller.dart';
import '../../update/presentation/app_update_sheet.dart';
import '../models/app_settings.dart';

class SettingsScreen extends StatefulWidget {
  const SettingsScreen({this.onSaved, super.key});

  final VoidCallback? onSaved;

  @override
  State<SettingsScreen> createState() => _SettingsScreenState();
}

class _SettingsScreenState extends State<SettingsScreen> {
  final _apiIdController = TextEditingController();
  final _apiHashController = TextEditingController();
  final _channelsController = TextEditingController();
  final _cacheController = TextEditingController();
  final _tdjsonController = TextEditingController();
  bool _preferWifi = true;
  bool _didSeed = false;

  bool get _showWindowsTdjsonPath => defaultTargetPlatform == TargetPlatform.windows;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (_didSeed) {
      return;
    }
    final settings = AppScope.of(context).settingsController.settings;
    _apiIdController.text = settings.apiId?.toString() ?? '';
    _apiHashController.text = settings.apiHash ?? '';
    _channelsController.text = settings.channelIds.join(', ');
    _cacheController.text = settings.cacheLimitMb.toString();
    _tdjsonController.text = settings.windowsTdjsonPath ?? '';
    _preferWifi = settings.preferWifi;
    _didSeed = true;
  }

  @override
  void dispose() {
    _apiIdController.dispose();
    _apiHashController.dispose();
    _channelsController.dispose();
    _cacheController.dispose();
    _tdjsonController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final settingsController = AppScope.of(context).settingsController;
    final colors = Theme.of(context).colorScheme;
    return Scaffold(
      body: DecoratedBox(
        decoration: BoxDecoration(
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
        ),
        child: SafeArea(
          child: Center(
            child: ListView(
              padding: const EdgeInsets.fromLTRB(20, 20, 20, 28),
              children: <Widget>[
                Center(
                  child: ConstrainedBox(
                    constraints: const BoxConstraints(maxWidth: 760),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: <Widget>[
                        _SettingsHeader(
                          isSaving: settingsController.isLoading,
                          onSave: settingsController.isLoading
                              ? null
                              : () => unawaited(_save()),
                        ),
                        const SizedBox(height: 18),
                        const _SettingsHero(),
                        const SizedBox(height: 18),
                        if (settingsController.error != null) ...<Widget>[
                          ErrorPanel(error: settingsController.error!),
                          const SizedBox(height: 16),
                        ],
                        _SettingsSection(
                          icon: Icons.key_rounded,
                          title: 'Telegram',
                          subtitle: 'Account and channel access',
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
                                prefixIcon: Icon(Icons.forum_outlined),
                              ),
                            ),
                          ],
                        ),
                        const SizedBox(height: 14),
                        _SettingsSection(
                          icon: Icons.tune_rounded,
                          title: 'Playback',
                          subtitle: 'Streaming and cache behavior',
                          children: <Widget>[
                            TextField(
                              controller: _cacheController,
                              keyboardType: TextInputType.number,
                              decoration: const InputDecoration(
                                labelText: 'Cache limit MB',
                                prefixIcon: Icon(Icons.storage_outlined),
                              ),
                            ),
                            const SizedBox(height: 10),
                            SwitchListTile.adaptive(
                              value: _preferWifi,
                              onChanged: (value) => setState(() => _preferWifi = value),
                              contentPadding: const EdgeInsets.symmetric(horizontal: 6),
                              title: const Text('Prefer Wi-Fi'),
                              secondary: const Icon(Icons.wifi_outlined),
                              shape: RoundedRectangleBorder(
                                borderRadius: BorderRadius.circular(24),
                              ),
                            ),
                          ],
                        ),
                        if (_showWindowsTdjsonPath) ...<Widget>[
                          const SizedBox(height: 14),
                          _SettingsSection(
                            icon: Icons.desktop_windows_rounded,
                            title: 'Windows',
                            subtitle: 'Local TDLib runtime',
                            children: <Widget>[
                              TextField(
                                controller: _tdjsonController,
                                decoration: const InputDecoration(
                                  labelText: 'TDJSON DLL path',
                                  hintText: r'C:\tdlib\bin\tdjson.dll',
                                  prefixIcon: Icon(Icons.folder_open_outlined),
                                ),
                              ),
                            ],
                          ),
                        ],
                        const SizedBox(height: 14),
                        _SettingsSection(
                          icon: Icons.system_update_alt_rounded,
                          title: 'Updates',
                          subtitle: 'GitHub release checks',
                          children: <Widget>[
                            _AppUpdateTile(
                              controller: AppScope.of(context).updateController,
                              onPressed: _checkForUpdates,
                            ),
                          ],
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

  Future<void> _save() async {
    final currentSettings = AppScope.of(context).settingsController.settings;
    final channels = _channelsController.text
        .split(',')
        .map((part) => int.tryParse(part.trim()))
        .whereType<int>()
        .toList(growable: false);
    final tdjsonPath = _tdjsonController.text.trim();
    final settings = AppSettings(
      apiId: int.tryParse(_apiIdController.text.trim()),
      apiHash: _apiHashController.text.trim(),
      channelIds: channels,
      cacheLimitMb: int.tryParse(_cacheController.text.trim()) ?? 4096,
      preferWifi: _preferWifi,
      windowsTdjsonPath: _showWindowsTdjsonPath
          ? (tdjsonPath.isEmpty ? null : tdjsonPath)
          : currentSettings.windowsTdjsonPath,
    );
    await AppScope.of(context).settingsController.save(settings);
    if (!mounted) {
      return;
    }
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(content: Text('Settings saved')),
    );
    widget.onSaved?.call();
  }

  Future<void> _checkForUpdates() async {
    final controller = AppScope.of(context).updateController;
    final update = await controller.check();
    if (!mounted) {
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

class _SettingsHeader extends StatelessWidget {
  const _SettingsHeader({
    required this.isSaving,
    required this.onSave,
  });

  final bool isSaving;
  final VoidCallback? onSave;

  @override
  Widget build(BuildContext context) {
    return Row(
      children: <Widget>[
        Expanded(
          child: Text(
            'Settings',
            style: Theme.of(context).textTheme.displaySmall?.copyWith(
                  fontWeight: FontWeight.w900,
                  letterSpacing: 0,
                ),
          ),
        ),
        FilledButton.icon(
          onPressed: onSave,
          icon: isSaving
              ? const SizedBox.square(
                  dimension: 18,
                  child: CircularProgressIndicator(strokeWidth: 2),
                )
              : const Icon(Icons.save_outlined),
          label: const Text('Save'),
        ),
      ],
    );
  }
}

class _SettingsHero extends StatelessWidget {
  const _SettingsHero();

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).colorScheme;
    return Container(
      padding: const EdgeInsets.all(18),
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(36),
        gradient: LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: <Color>[
            colors.primaryContainer,
            colors.secondaryContainer.withValues(alpha: 0.86),
            colors.tertiaryContainer.withValues(alpha: 0.68),
          ],
        ),
      ),
      child: Row(
        children: <Widget>[
          Container(
            width: 74,
            height: 74,
            decoration: BoxDecoration(
              color: colors.surface.withValues(alpha: 0.52),
              borderRadius: BorderRadius.circular(24),
            ),
            child: Icon(
              Icons.equalizer_rounded,
              size: 42,
              color: colors.primary,
            ),
          ),
          const SizedBox(width: 16),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: <Widget>[
                Text(
                  'TelePlayer',
                  style: Theme.of(context).textTheme.headlineSmall?.copyWith(
                        color: colors.onPrimaryContainer,
                        fontWeight: FontWeight.w900,
                        letterSpacing: 0,
                      ),
                ),
                const SizedBox(height: 5),
                Text(
                  'Telegram music, tuned your way',
                  style: Theme.of(context).textTheme.bodyLarge?.copyWith(
                        color: colors.onPrimaryContainer.withValues(alpha: 0.76),
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

class _SettingsSection extends StatelessWidget {
  const _SettingsSection({
    required this.icon,
    required this.title,
    required this.subtitle,
    required this.children,
  });

  final IconData icon;
  final String title;
  final String subtitle;
  final List<Widget> children;

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).colorScheme;
    return Material(
      color: colors.surfaceContainer.withValues(alpha: 0.88),
      borderRadius: BorderRadius.circular(32),
      clipBehavior: Clip.antiAlias,
      child: Padding(
        padding: const EdgeInsets.all(18),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: <Widget>[
            Row(
              children: <Widget>[
                Container(
                  width: 48,
                  height: 48,
                  decoration: BoxDecoration(
                    color: colors.primaryContainer,
                    borderRadius: BorderRadius.circular(18),
                  ),
                  child: Icon(icon, color: colors.onPrimaryContainer),
                ),
                const SizedBox(width: 13),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: <Widget>[
                      Text(
                        title,
                        style: Theme.of(context).textTheme.titleLarge?.copyWith(
                              fontWeight: FontWeight.w900,
                              letterSpacing: 0,
                            ),
                      ),
                      const SizedBox(height: 2),
                      Text(
                        subtitle,
                        style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                              color: colors.onSurfaceVariant,
                            ),
                      ),
                    ],
                  ),
                ),
              ],
            ),
            const SizedBox(height: 16),
            ...children,
          ],
        ),
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
          AppUpdateStatus.upToDate => controller.message ?? 'TelePlayer is up to date.',
          AppUpdateStatus.updateAvailable =>
            controller.message ?? 'A newer TelePlayer release is available.',
          AppUpdateStatus.error => controller.message ?? 'The update check failed.',
          AppUpdateStatus.opening => 'Opening the update download...',
          AppUpdateStatus.idle => 'Check for a newer GitHub release',
        };
        return Material(
          color: colors.surfaceContainerHigh,
          borderRadius: BorderRadius.circular(26),
          clipBehavior: Clip.antiAlias,
          child: ListTile(
            onTap: controller.isBusy ? null : onPressed,
            leading: const Icon(Icons.system_update_alt_rounded),
            title: const Text('App updates'),
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
