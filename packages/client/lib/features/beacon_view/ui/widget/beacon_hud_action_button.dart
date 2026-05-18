import 'package:flutter/material.dart';

/// Compact beacon HUD action control (matches operational header rail, e.g. Forward).
class BeaconHudActionButton extends StatelessWidget {
  const BeaconHudActionButton({
    required this.icon,
    required this.label,
    super.key,
    this.onPressed,
    this.filled = false,
  });

  final IconData icon;
  final String label;
  final VoidCallback? onPressed;
  final bool filled;

  @override
  Widget build(BuildContext context) {
    final labelStyle = Theme.of(context).textTheme.labelMedium;
    if (filled) {
      return FilledButton.icon(
        onPressed: onPressed,
        icon: Icon(icon, size: 16),
        label: Text(
          label,
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
        ),
        style: FilledButton.styleFrom(
          textStyle: labelStyle,
          padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 8),
          visualDensity: VisualDensity.compact,
        ),
      );
    }
    return OutlinedButton.icon(
      onPressed: onPressed,
      icon: Icon(icon, size: 16),
      label: Text(
        label,
        maxLines: 1,
        overflow: TextOverflow.ellipsis,
        style: labelStyle,
      ),
      style: OutlinedButton.styleFrom(
        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 8),
        visualDensity: VisualDensity.compact,
      ),
    );
  }
}

/// Icon-only HUD action (same chrome as [BeaconHudActionButton], for compact slots).
class BeaconHudIconActionButton extends StatelessWidget {
  const BeaconHudIconActionButton({
    required this.icon,
    required this.tooltip,
    super.key,
    this.onPressed,
  });

  final IconData icon;
  final String tooltip;
  final VoidCallback? onPressed;

  @override
  Widget build(BuildContext context) {
    return Semantics(
      button: true,
      label: tooltip,
      child: Tooltip(
        message: tooltip,
        child: OutlinedButton(
          onPressed: onPressed,
          style: OutlinedButton.styleFrom(
            minimumSize: const Size(44, 40),
            padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 8),
            visualDensity: VisualDensity.compact,
          ),
          child: Icon(icon, size: 16),
        ),
      ),
    );
  }
}
