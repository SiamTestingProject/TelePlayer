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
    return Scaffold(
      appBar: AppBar(title: const Text('Settings')),
      body: SafeArea(
        child: ListView(
          padding: const EdgeInsets.all(20),
          children: [
            ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 720),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  if (settingsController.error != null) ...[
                    ErrorPanel(error: settingsController.error!),
                    const SizedBox(height: 16),
                  ],
                  TextField(
                    controller: _apiIdController,
                    keyboardType: TextInputType.number,
                    decoration: const InputDecoration(
                      labelText: 'Telegram API ID',
                      prefixIcon: Icon(Icons.numbers_outlined),
                      border: OutlineInputBorder(),
                    ),
                  ),
                  const SizedBox(height: 12),
                  TextField(
                    controller: _apiHashController,
                    obscureText: true,
                    decoration: const InputDecoration(
                      labelText: 'Telegram API hash',
                      prefixIcon: Icon(Icons.key_outlined),
                      border: OutlineInputBorder(),
                    ),
                  ),
                  const SizedBox(height: 12),
                  TextField(
                    controller: _channelsController,
                    decoration: const InputDecoration(
                      labelText: 'Channel IDs',
                      prefixIcon: Icon(Icons.forum_outlined),
                      border: OutlineInputBorder(),
                    ),
                  ),
                  const SizedBox(height: 12),
                  TextField(
                    controller: _cacheController,
                    keyboardType: TextInputType.number,
                    decoration: const InputDecoration(
                      labelText: 'Cache limit MB',
                      prefixIcon: Icon(Icons.storage_outlined),
                      border: OutlineInputBorder(),
                    ),
                  ),
                  if (_showWindowsTdjsonPath) ...[
                    const SizedBox(height: 12),
                    TextField(
                      controller: _tdjsonController,
                      decoration: const InputDecoration(
                        labelText: 'TDJSON DLL path',
                        hintText: r'C:\tdlib\bin\tdjson.dll',
                        prefixIcon: Icon(Icons.folder_open_outlined),
                        border: OutlineInputBorder(),
                      ),
                    ),
                  ],
                  const SizedBox(height: 8),
                  SwitchListTile(
                    value: _preferWifi,
                    onChanged: (value) => setState(() => _preferWifi = value),
                    contentPadding: EdgeInsets.zero,
                    title: const Text('Prefer Wi-Fi'),
                    secondary: const Icon(Icons.wifi_outlined),
                  ),
                  const SizedBox(height: 16),
                  FilledButton.icon(
                    onPressed: settingsController.isLoading ? null : () => unawaited(_save()),
                    icon: const Icon(Icons.save_outlined),
                    label: const Text('Save'),
                  ),
                  const SizedBox(height: 28),
                  Text(
                    'TelePlayer',
                    style: Theme.of(context).textTheme.titleMedium,
                  ),
                  const SizedBox(height: 8),
                  _AppUpdateTile(
                    controller: AppScope.of(context).updateController,
                    onPressed: _checkForUpdates,
                  ),
                ],
              ),
            ),
          ],
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

class _AppUpdateTile extends StatelessWidget {
  const _AppUpdateTile({
    required this.controller,
    required this.onPressed,
  });

  final AppUpdateController controller;
  final VoidCallback onPressed;

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: controller,
      builder: (context, _) {
        final isChecking = controller.status == AppUpdateStatus.checking;
        final subtitle = switch (controller.status) {
          AppUpdateStatus.checking => 'Checking GitHub releases...',
          AppUpdateStatus.upToDate => controller.message ?? 'TelePlayer is up to date.',
          AppUpdateStatus.updateAvailable =>
            controller.message ?? 'A newer TelePlayer release is available.',
          AppUpdateStatus.error =>
            controller.message ?? 'The update check failed.',
          AppUpdateStatus.opening => 'Opening the update download...',
          AppUpdateStatus.idle => 'Check for a newer GitHub release',
        };
        return Card(
          margin: EdgeInsets.zero,
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
