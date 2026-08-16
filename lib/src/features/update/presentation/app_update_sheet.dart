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
        initialChildSize: 0.68,
        minChildSize: 0.48,
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

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colors = theme.colorScheme;
    return Material(
      color: colors.surfaceContainer,
      clipBehavior: Clip.antiAlias,
      borderRadius: const BorderRadius.vertical(top: Radius.circular(38)),
      child: ListView(
        controller: widget.scrollController,
        padding: const EdgeInsets.fromLTRB(24, 12, 24, 28),
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
          const SizedBox(height: 24),
          Container(
            padding: const EdgeInsets.all(18),
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(34),
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
              children: [
                Container(
                  width: 70,
                  height: 70,
                  decoration: BoxDecoration(
                    color: colors.surface.withValues(alpha: 0.52),
                    borderRadius: BorderRadius.circular(24),
                  ),
                  child: Icon(
                    Icons.system_update_alt_rounded,
                    size: 40,
                    color: colors.primary,
                  ),
                ),
                const SizedBox(width: 16),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        'TelePlayer Update',
                        style: theme.textTheme.headlineSmall?.copyWith(
                          color: colors.onPrimaryContainer,
                          fontWeight: FontWeight.w900,
                          letterSpacing: 0,
                        ),
                      ),
                      const SizedBox(height: 4),
                      Text(
                        'v${widget.update.version}',
                        style: theme.textTheme.titleMedium?.copyWith(
                          color: colors.onPrimaryContainer.withValues(alpha: 0.78),
                          fontWeight: FontWeight.w800,
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(height: 26),
          Text(
            'Changelog',
            textAlign: TextAlign.center,
            style: theme.textTheme.displaySmall?.copyWith(
              fontWeight: FontWeight.w900,
              letterSpacing: 0,
            ),
          ),
          const SizedBox(height: 24),
          SizedBox(
            height: 24,
            child: CustomPaint(
              painter: _WaveDividerPainter(
                color: colors.primary.withValues(alpha: 0.75),
              ),
            ),
          ),
          const SizedBox(height: 26),
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
          const SizedBox(height: 26),
          Card(
            margin: EdgeInsets.zero,
            color: colors.surfaceContainerHigh,
            elevation: 0,
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(28),
            ),
            child: Padding(
              padding: const EdgeInsets.fromLTRB(24, 24, 24, 18),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    "What's New",
                    style: theme.textTheme.titleLarge?.copyWith(
                      color: colors.primary,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                  const SizedBox(height: 12),
                  for (var index = 0;
                      index < widget.update.changes.length;
                      index++) ...[
                    if (index > 0)
                      Divider(
                        height: 26,
                        color: colors.outlineVariant.withValues(alpha: 0.45),
                      ),
                    _ChangeItem(text: widget.update.changes[index]),
                  ],
                ],
              ),
            ),
          ),
          if (_error != null) ...[
            const SizedBox(height: 16),
            Text(
              _error!,
              textAlign: TextAlign.center,
              style: theme.textTheme.bodyMedium?.copyWith(color: colors.error),
            ),
          ],
          const SizedBox(height: 24),
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
          const SizedBox(height: 8),
          TextButton(
            onPressed: _isOpening ? null : () => Navigator.of(context).pop(),
            child: const Text('Later'),
          ),
        ],
      ),
    );
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

class _WaveDividerPainter extends CustomPainter {
  const _WaveDividerPainter({required this.color});

  final Color color;

  @override
  void paint(Canvas canvas, Size size) {
    final paint = Paint()
      ..color = color
      ..style = PaintingStyle.stroke
      ..strokeWidth = 4
      ..strokeCap = StrokeCap.round;
    final path = Path()..moveTo(0, size.height / 2);
    const waveWidth = 38.0;
    const amplitude = 7.0;
    var x = 0.0;
    while (x < size.width) {
      path
        ..quadraticBezierTo(
          x + waveWidth / 4,
          size.height / 2 + amplitude,
          x + waveWidth / 2,
          size.height / 2,
        )
        ..quadraticBezierTo(
          x + waveWidth * 0.75,
          size.height / 2 - amplitude,
          x + waveWidth,
          size.height / 2,
        );
      x += waveWidth;
    }
    canvas.drawPath(path, paint);
  }

  @override
  bool shouldRepaint(_WaveDividerPainter oldDelegate) {
    return oldDelegate.color != color;
  }
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
