import 'package:flutter/material.dart';

import '../core/errors/error_message_mapper.dart';

class ErrorPanel extends StatelessWidget {
  const ErrorPanel({
    required this.error,
    this.onAction,
    super.key,
  });

  final Object error;
  final VoidCallback? onAction;

  @override
  Widget build(BuildContext context) {
    final friendly = const ErrorMessageMapper().map(error);
    final colors = Theme.of(context).colorScheme;
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: colors.errorContainer,
        borderRadius: BorderRadius.circular(8),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(Icons.error_outline, color: colors.onErrorContainer),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(
                  friendly.title,
                  style: Theme.of(context).textTheme.titleSmall?.copyWith(
                        color: colors.onErrorContainer,
                        fontWeight: FontWeight.w700,
                      ),
                ),
                const SizedBox(height: 4),
                Text(
                  friendly.body,
                  style: TextStyle(color: colors.onErrorContainer),
                ),
              ],
            ),
          ),
          if (friendly.actionLabel != null && onAction != null)
            TextButton(
              onPressed: onAction,
              child: Text(friendly.actionLabel!),
            ),
        ],
      ),
    );
  }
}
