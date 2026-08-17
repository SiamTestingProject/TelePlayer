import 'dart:math' as math;

import 'package:flutter/material.dart';

import '../application/app_update_controller.dart';
import '../models/app_update.dart';

Future<void> showAppUpdateSheet(
  BuildContext context, {
  required AppUpdateController controller,
  required AppUpdate update,
}) {
  return showModalBottomSheet<void>(
    context: context,
    isScrollControlled: true,
    useSafeArea: true,
    backgroundColor: Colors.transparent,
    constraints: const BoxConstraints(maxWidth: 720),
    builder: (context) {
      return DraggableScrollableSheet(
        initialChildSize: 0.78,
        minChildSize: 0.52,
        maxChildSize: 0.96,
        expand: false,
        builder: (context, scrollController) {
          return _AppUpdateSheet(
            controller: controller,
            update: update,
            scrollController: scrollController,
          );
        },
      );
    },
  );
}

class _AppUpdateSheet extends StatefulWidget {
  const _AppUpdateSheet({
    required this.controller,
    required this.update,
    required this.scrollController,
  });

  final AppUpdateController controller;
  final AppUpdate update;
  final ScrollController scrollController;

  @override
  State<_AppUpdateSheet> createState() => _AppUpdateSheetState();
}

class _AppUpdateSheetState extends State<_AppUpdateSheet> {
  bool _isOpening = false;
  String? _error;
  AppUpdateAsset? _selectedAsset;

  @override
  void initState() {
    super.initState();
    final androidAssets = widget.update.androidAssets;
    _selectedAsset = widget.update.preferredAndroidAsset ??
        (androidAssets.isEmpty ? null : androidAssets.first);
    widget.controller.addListener(_controllerChanged);
  }

  @override
  void dispose() {
    widget.controller.removeListener(_controllerChanged);
    super.dispose();
  }

  void _controllerChanged() {
    if (mounted) {
      setState(() {});
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colors = theme.colorScheme;
    final androidAssets = widget.update.androidAssets;
    final selectedAsset = _selectedAsset;
    final activeDownload = widget.controller.downloadAssetSelection;
    final progress = activeDownload?.uri == selectedAsset?.uri
        ? widget.controller.downloadProgress
        : null;
    final isDownloading = widget.controller.status == AppUpdateStatus.downloading;
    final isDownloaded = widget.controller.status == AppUpdateStatus.downloaded &&
        activeDownload?.uri == selectedAsset?.uri;

    return Material(
      color: colors.surfaceContainer,
      clipBehavior: Clip.antiAlias,
      borderRadius: const BorderRadius.vertical(top: Radius.circular(38)),
      child: SingleChildScrollView(
        controller: widget.scrollController,
        child: Padding(
          padding: const EdgeInsets.fromLTRB(24, 12, 24, 28),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Center(
                child: Container(
                  width: 56,
                  height: 5,
                  decoration: BoxDecoration(
                    color: colors.onSurfaceVariant.withValues(alpha: 0.55),
                    borderRadius: BorderRadius.circular(99),
                  ),
                ),
              ),
              const SizedBox(height: 18),
              Row(
                children: [
                  Container(
                    width: 58,
                    height: 58,
                    decoration: BoxDecoration(
                      color: colors.primaryContainer,
                      borderRadius: BorderRadius.circular(22),
                    ),
                    child: Icon(
                      Icons.system_update_alt_rounded,
                      size: 32,
                      color: colors.onPrimaryContainer,
                    ),
                  ),
                  const SizedBox(width: 14),
                  Expanded(
                    child: Text(
                      'Changelog',
                      style: theme.textTheme.displaySmall?.copyWith(
                        fontWeight: FontWeight.w900,
                        letterSpacing: 0,
                      ),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 18),
              Row(
                children: [
                  Container(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 18,
                      vertical: 10,
                    ),
                    decoration: BoxDecoration(
                      color: colors.primaryContainer,
                      borderRadius: BorderRadius.circular(28),
                    ),
                    child: Text(
                      'v${widget.update.version}',
                      style: theme.textTheme.titleMedium?.copyWith(
                        color: colors.onPrimaryContainer,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                  ),
                  const Spacer(),
                  Text(
                    _formatDate(widget.update.publishedAt),
                    style: theme.textTheme.titleMedium?.copyWith(
                      color: colors.onSurfaceVariant,
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 22),
              Card(
                margin: EdgeInsets.zero,
                color: colors.surfaceContainerHigh,
                elevation: 0,
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(28),
                ),
                child: Padding(
                  padding: const EdgeInsets.fromLTRB(24, 22, 24, 20),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        "What's New",
                        style: theme.textTheme.titleLarge?.copyWith(
                          color: colors.primary,
                          fontWeight: FontWeight.w800,
                        ),
                      ),
                      const SizedBox(height: 12),
                      for (var index = 0;
                          index < widget.update.changes.length;
                          index++) ...[
                        if (index > 0)
                          Divider(
                            height: 24,
                            color: colors.outlineVariant.withValues(alpha: 0.45),
                          ),
                        _ChangeItem(text: widget.update.changes[index]),
                      ],
                    ],
                  ),
                ),
              ),
              if (androidAssets.isNotEmpty) ...[
                const SizedBox(height: 22),
                Text(
                  'Choose Android version',
                  style: theme.textTheme.titleLarge?.copyWith(
                    fontWeight: FontWeight.w800,
                  ),
                ),
                const SizedBox(height: 6),
                Text(
                  'The APK downloads directly inside TelePlayer. ARM64 is recommended for most modern Android phones.',
                  style: theme.textTheme.bodyMedium?.copyWith(
                    color: colors.onSurfaceVariant,
                    height: 1.35,
                  ),
                ),
                const SizedBox(height: 14),
                Wrap(
                  spacing: 10,
                  runSpacing: 10,
                  children: [
                    for (final asset in androidAssets)
                      ChoiceChip(
                        selected: selectedAsset?.uri == asset.uri,
                        onSelected: isDownloading
                            ? null
                            : (_) {
                                setState(() {
                                  _selectedAsset = asset;
                                  _error = null;
                                });
                              },
                        avatar: Icon(
                          _assetIcon(asset.type),
                          size: 18,
                        ),
                        label: Text(
                          asset.sizeBytes == null
                              ? asset.label
                              : '${asset.label} • ${_formatBytes(asset.sizeBytes!)}',
                        ),
                      ),
                  ],
                ),
              ],
              if (progress != null) ...[
                const SizedBox(height: 22),
                _DownloadProgressCard(
                  progress: progress,
                  asset: selectedAsset!,
                ),
              ],
              if (_error != null ||
                  widget.controller.status == AppUpdateStatus.error) ...[
                const SizedBox(height: 16),
                Text(
                  _error ?? widget.controller.message ?? 'Update failed.',
                  textAlign: TextAlign.center,
                  style: theme.textTheme.bodyMedium?.copyWith(color: colors.error),
                ),
              ],
              const SizedBox(height: 24),
              if (androidAssets.isNotEmpty)
                FilledButton.icon(
                  onPressed: isDownloading || isDownloaded || selectedAsset == null
                      ? null
                      : _downloadUpdate,
                  icon: isDownloading
                      ? const SizedBox.square(
                          dimension: 18,
                          child: CircularProgressIndicator(strokeWidth: 2),
                        )
                      : Icon(
                          isDownloaded
                              ? Icons.download_done_rounded
                              : Icons.download_rounded,
                        ),
                  label: Text(
                    isDownloading
                        ? 'Downloading ${activeDownload?.label ?? ''}...'
                        : isDownloaded
                            ? '${selectedAsset?.label ?? ''} downloaded'
                            : 'Download ${selectedAsset?.label ?? 'update'}',
                  ),
                )
              else
                FilledButton.icon(
                  onPressed: _isOpening ? null : _openUpdate,
                  icon: _isOpening
                      ? const SizedBox.square(
                          dimension: 18,
                          child: CircularProgressIndicator(strokeWidth: 2),
                        )
                      : Icon(
                          widget.update.isDirectDownload
                              ? Icons.download_rounded
                              : Icons.open_in_new_rounded,
                        ),
                  label: Text(
                    widget.update.isDirectDownload
                        ? 'Download update'
                        : 'Open release page',
                  ),
                ),
              if (isDownloaded && widget.controller.downloadedPath != null) ...[
                const SizedBox(height: 10),
                Text(
                  'Saved inside TelePlayer updates storage as ${selectedAsset?.name}.',
                  textAlign: TextAlign.center,
                  style: theme.textTheme.bodySmall?.copyWith(
                    color: colors.onSurfaceVariant,
                  ),
                ),
              ],
              const SizedBox(height: 8),
              TextButton(
                onPressed: isDownloading || _isOpening
                    ? null
                    : () => Navigator.of(context).pop(),
                child: const Text('Later'),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Future<void> _downloadUpdate() async {
    final asset = _selectedAsset;
    if (asset == null) {
      return;
    }
    setState(() {
      _error = null;
    });
    final downloaded = await widget.controller.downloadUpdateAsset(asset);
    if (!mounted || downloaded) {
      return;
    }
    setState(() {
      _error = widget.controller.message;
    });
  }

  Future<void> _openUpdate() async {
    setState(() {
      _isOpening = true;
      _error = null;
    });
    final opened = await widget.controller.openUpdate(widget.update);
    if (!mounted) {
      return;
    }
    if (opened) {
      Navigator.of(context).pop();
      return;
    }
    setState(() {
      _isOpening = false;
      _error = widget.controller.message;
    });
  }
}

class _DownloadProgressCard extends StatelessWidget {
  const _DownloadProgressCard({
    required this.progress,
    required this.asset,
  });

  final AppUpdateDownloadProgress progress;
  final AppUpdateAsset asset;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colors = theme.colorScheme;
    final fraction = progress.fraction ?? 0.0;
    final percentage = (fraction * 100).clamp(0, 100).round();
    final total = progress.totalBytes;
    return Container(
      padding: const EdgeInsets.all(18),
      decoration: BoxDecoration(
        color: colors.surfaceContainerHigh,
        borderRadius: BorderRadius.circular(26),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            children: [
              Expanded(
                child: Text(
                  progress.isComplete
                      ? '${asset.label} download complete'
                      : 'Downloading ${asset.label}',
                  style: theme.textTheme.titleMedium?.copyWith(
                    fontWeight: FontWeight.w800,
                  ),
                ),
              ),
              Text(
                '$percentage%',
                style: theme.textTheme.titleMedium?.copyWith(
                  color: colors.primary,
                  fontWeight: FontWeight.w900,
                ),
              ),
            ],
          ),
          const SizedBox(height: 14),
          SizedBox(
            height: 34,
            child: _DownloadWave(
              progress: fraction,
              animate: !progress.isComplete,
            ),
          ),
          const SizedBox(height: 12),
          Wrap(
            alignment: WrapAlignment.spaceBetween,
            spacing: 12,
            runSpacing: 6,
            children: [
              Text(
                total == null
                    ? _formatBytes(progress.receivedBytes)
                    : '${_formatBytes(progress.receivedBytes)} / ${_formatBytes(total)}',
                style: theme.textTheme.bodyMedium?.copyWith(
                  fontWeight: FontWeight.w700,
                ),
              ),
              Text(
                progress.isComplete
                    ? 'Complete'
                    : '${_formatBytes(progress.bytesPerSecond.round())}/s',
                style: theme.textTheme.bodyMedium?.copyWith(
                  color: colors.onSurfaceVariant,
                  fontWeight: FontWeight.w700,
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }
}

class _DownloadWave extends StatefulWidget {
  const _DownloadWave({
    required this.progress,
    required this.animate,
  });

  final double progress;
  final bool animate;

  @override
  State<_DownloadWave> createState() => _DownloadWaveState();
}

class _DownloadWaveState extends State<_DownloadWave>
    with SingleTickerProviderStateMixin {
  late final AnimationController _controller;

  @override
  void initState() {
    super.initState();
    _controller = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 900),
    );
    if (widget.animate) {
      _controller.repeat();
    }
  }

  @override
  void didUpdateWidget(covariant _DownloadWave oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (widget.animate && !_controller.isAnimating) {
      _controller.repeat();
    } else if (!widget.animate && _controller.isAnimating) {
      _controller.stop();
    }
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).colorScheme;
    return AnimatedBuilder(
      animation: _controller,
      builder: (context, _) => CustomPaint(
        painter: _DownloadWavePainter(
          progress: widget.progress,
          phase: _controller.value * math.pi * 2,
          activeColor: colors.primary,
          trackColor: colors.surfaceContainerHighest,
        ),
      ),
    );
  }
}

class _DownloadWavePainter extends CustomPainter {
  const _DownloadWavePainter({
    required this.progress,
    required this.phase,
    required this.activeColor,
    required this.trackColor,
  });

  final double progress;
  final double phase;
  final Color activeColor;
  final Color trackColor;

  @override
  void paint(Canvas canvas, Size size) {
    final centerY = size.height / 2;
    final track = Paint()
      ..color = trackColor
      ..strokeWidth = 6
      ..strokeCap = StrokeCap.round
      ..style = PaintingStyle.stroke;
    canvas.drawLine(
      Offset(3, centerY),
      Offset(size.width - 3, centerY),
      track,
    );

    final activeWidth = (size.width * progress.clamp(0.0, 1.0))
        .clamp(0.0, size.width)
        .toDouble();
    if (activeWidth <= 0) {
      return;
    }
    final wave = Path();
    const amplitude = 5.0;
    const wavelength = 34.0;
    for (double x = 0; x <= activeWidth; x += 2) {
      final y = centerY +
          math.sin((x / wavelength * math.pi * 2) + phase) * amplitude;
      if (x == 0) {
        wave.moveTo(x, y);
      } else {
        wave.lineTo(x, y);
      }
    }
    final paint = Paint()
      ..color = activeColor
      ..strokeWidth = 6
      ..strokeCap = StrokeCap.round
      ..strokeJoin = StrokeJoin.round
      ..style = PaintingStyle.stroke;
    canvas.drawPath(wave, paint);
    canvas.drawCircle(
      Offset(activeWidth, centerY),
      7,
      Paint()..color = activeColor,
    );
  }

  @override
  bool shouldRepaint(covariant _DownloadWavePainter oldDelegate) {
    return oldDelegate.progress != progress ||
        oldDelegate.phase != phase ||
        oldDelegate.activeColor != activeColor ||
        oldDelegate.trackColor != trackColor;
  }
}

class _ChangeItem extends StatelessWidget {
  const _ChangeItem({required this.text});

  final String text;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colors = theme.colorScheme;
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Padding(
          padding: const EdgeInsets.only(top: 8),
          child: Container(
            width: 9,
            height: 9,
            decoration: BoxDecoration(
              color: colors.primary,
              shape: BoxShape.circle,
            ),
          ),
        ),
        const SizedBox(width: 16),
        Expanded(
          child: Text(
            text,
            style: theme.textTheme.bodyLarge?.copyWith(height: 1.45),
          ),
        ),
      ],
    );
  }
}

IconData _assetIcon(AppUpdateAssetType type) => switch (type) {
      AppUpdateAssetType.arm64 => Icons.memory_rounded,
      AppUpdateAssetType.arm32 => Icons.memory_outlined,
      AppUpdateAssetType.x86_64 => Icons.computer_rounded,
      AppUpdateAssetType.universal => Icons.android_rounded,
      AppUpdateAssetType.windowsInstaller => Icons.desktop_windows_rounded,
      AppUpdateAssetType.other => Icons.download_rounded,
    };

String _formatBytes(int bytes) {
  if (bytes < 1024) {
    return '$bytes B';
  }
  final kb = bytes / 1024;
  if (kb < 1024) {
    return '${kb.toStringAsFixed(kb >= 100 ? 0 : 1)} KB';
  }
  final mb = kb / 1024;
  if (mb < 1024) {
    return '${mb.toStringAsFixed(mb >= 100 ? 0 : 1)} MB';
  }
  final gb = mb / 1024;
  return '${gb.toStringAsFixed(gb >= 100 ? 0 : 1)} GB';
}

String _formatDate(DateTime? value) {
  if (value == null) {
    return 'New release';
  }
  final local = value.toLocal();
  final month = local.month.toString().padLeft(2, '0');
  final day = local.day.toString().padLeft(2, '0');
  return '${local.year}-$month-$day';
}
