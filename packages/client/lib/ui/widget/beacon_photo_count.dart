import 'package:flutter/material.dart';

/// Tiny secondary metadata: image count (no emoji, not a gallery).
class BeaconPhotoCount extends StatelessWidget {
  const BeaconPhotoCount({
    required this.count,
    this.compact = true,
    super.key,
  });

  final int count;
  final bool compact;

  @override
  Widget build(BuildContext context) {
    if (count <= 0) return const SizedBox.shrink();

    final theme = Theme.of(context);
    final label = count > 99 ? '99+' : '$count';
    final style = theme.textTheme.labelSmall?.copyWith(
      color: theme.colorScheme.onSurfaceVariant,
    );

    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Icon(
          Icons.photo_library_outlined,
          size: compact ? 14 : 16,
          color: theme.colorScheme.onSurfaceVariant,
        ),
        SizedBox(width: compact ? 3 : 4),
        Text(label, style: style),
      ],
    );
  }
}
