import 'package:flutter/material.dart';

/// Compact outlined CTA for the left slot of inbox / beacon action rows (Not for
/// me, Watch, Move to inbox, etc.): matches surface + border treatment.
class SideOutlineCtaButton extends StatelessWidget {
  const SideOutlineCtaButton({
    required this.label,
    required this.icon,
    required this.onPressed,
    super.key,
  });

  final String label;
  final IconData icon;
  final Future<void> Function() onPressed;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    return OutlinedButton(
      onPressed: () async {
        await onPressed();
      },
      style: OutlinedButton.styleFrom(
        padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 9),
        minimumSize: Size.zero,
        tapTargetSize: MaterialTapTargetSize.shrinkWrap,
        foregroundColor: scheme.onSurfaceVariant,
        side: BorderSide(
          color: scheme.outlineVariant.withValues(alpha: 0.65),
        ),
        backgroundColor: scheme.surfaceContainerHigh.withValues(alpha: 0.55),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: 24),
          const SizedBox(width: 6),
          ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 180),
            child: Text(
              label,
              style: theme.textTheme.labelMedium?.copyWith(
                fontWeight: FontWeight.w700,
              ),
              overflow: TextOverflow.ellipsis,
              maxLines: 1,
            ),
          ),
        ],
      ),
    );
  }
}
