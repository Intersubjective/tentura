import 'package:flutter/material.dart';

/// Relay note preview: muted, quoted, left rule only (no filled box).
class InboxCardNoteQuote extends StatelessWidget {
  const InboxCardNoteQuote({
    required this.text,
    super.key,
  });

  final String text;

  @override
  Widget build(BuildContext context) {
    if (text.trim().isEmpty) return const SizedBox.shrink();
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;

    return DecoratedBox(
      decoration: BoxDecoration(
        border: Border(
          left: BorderSide(
            color: scheme.primary.withValues(alpha: 0.45),
            width: 2,
          ),
        ),
      ),
      child: Padding(
        padding: const EdgeInsets.only(left: 8),
        child: Text(
          text.trim(),
          maxLines: 2,
          overflow: TextOverflow.ellipsis,
          style: theme.textTheme.bodySmall?.copyWith(
            color: scheme.onSurfaceVariant,
            fontStyle: FontStyle.italic,
            height: 1.35,
          ),
        ),
      ),
    );
  }
}
