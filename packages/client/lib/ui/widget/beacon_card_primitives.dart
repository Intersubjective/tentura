import 'package:flutter/material.dart';

import 'package:tentura/domain/entity/beacon.dart';
import 'package:tentura/ui/utils/ui_utils.dart';
import 'package:tentura/ui/widget/beacon_identity_tile.dart';

/// Surface, shape, and optional whole-card tap for beacon list cards.
///
/// When [onTap] is non-null, uses [Material] + [InkWell] (ripple). When null,
/// uses a [DecoratedBox] with a light shadow (inbox-style).
class BeaconCardShell extends StatelessWidget {
  const BeaconCardShell({
    required this.child,
    this.onTap,
    this.muted = false,
    this.color,
    super.key,
  });

  final Widget child;
  final VoidCallback? onTap;
  final bool muted;
  final Color? color;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final padded = Padding(
      padding: kPaddingAllS,
      child: child,
    );

    if (onTap != null) {
      final bg =
          color ??
          (muted
              ? scheme.surfaceContainerHighest.withValues(alpha: 0.45)
              : scheme.surfaceContainer);
      return Material(
        color: bg,
        borderRadius: BorderRadius.circular(8),
        elevation: muted ? 0 : 0.5,
        shadowColor: scheme.shadow.withValues(alpha: 0.12),
        child: InkWell(
          onTap: onTap,
          borderRadius: BorderRadius.circular(8),
          child: padded,
        ),
      );
    }

    return DecoratedBox(
      decoration: BoxDecoration(
        color: color ?? scheme.surfaceContainerLowest,
        borderRadius: BorderRadius.circular(8),
        boxShadow: [
          BoxShadow(
            color: scheme.shadow.withValues(alpha: 0.08),
            blurRadius: 4,
            offset: const Offset(0, 1),
          ),
        ],
      ),
      child: padded,
    );
  }
}

/// Identity tile, title column, and trailing slot (e.g. overflow menu).
///
/// [subline] is typically [Text] or a [Row] with avatar + author name.
class BeaconCardHeaderRow extends StatelessWidget {
  const BeaconCardHeaderRow({
    required this.beacon,
    required this.subline,
    required this.menu,
    this.titleMaxLines = 1,
    super.key,
  });

  final Beacon beacon;
  final Widget subline;
  final Widget menu;
  final int titleMaxLines;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;

    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        BeaconIdentityTile(beacon: beacon),
        const SizedBox(width: kSpacingSmall),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                beacon.title.isEmpty ? '—' : beacon.title,
                style: theme.textTheme.titleMedium?.copyWith(
                  fontWeight: FontWeight.w700,
                  color: scheme.onSurface,
                ),
                maxLines: titleMaxLines,
                overflow: TextOverflow.ellipsis,
              ),
              const SizedBox(height: 2),
              subline,
            ],
          ),
        ),
        menu,
      ],
    );
  }
}

/// Uppercase rounded status chip (My Work pills + inbox lifecycle/coordination).
class BeaconCardPill extends StatelessWidget {
  const BeaconCardPill({
    required this.label,
    this.emphasized = false,
    this.backgroundColor,
    this.foregroundColor,
    super.key,
  });

  final String label;
  final bool emphasized;
  final Color? backgroundColor;
  final Color? foregroundColor;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final bg =
        backgroundColor ??
        (emphasized ? scheme.primaryContainer : scheme.surfaceContainerHigh);
    final fg =
        foregroundColor ??
        (emphasized ? scheme.onPrimaryContainer : scheme.onSurfaceVariant);

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
      decoration: BoxDecoration(
        color: bg,
        borderRadius: BorderRadius.circular(999),
      ),
      child: Text(
        label.toUpperCase(),
        style: Theme.of(context).textTheme.labelSmall?.copyWith(
          fontWeight: FontWeight.w700,
          fontSize: 11,
          letterSpacing: 0.2,
          color: fg,
        ),
      ),
    );
  }
}

/// Icon + child row for metadata strips (topic, commitments, photos, insights).
///
/// Use [mainAxisSize] [MainAxisSize.max] with an [Expanded] child for a
/// full-width context line; default [MainAxisSize.min] fits [Wrap] children.
class BeaconCardMetaItem extends StatelessWidget {
  const BeaconCardMetaItem({
    required this.icon,
    required this.child,
    this.mainAxisSize = MainAxisSize.min,
    super.key,
  });

  final IconData icon;
  final Widget child;
  final MainAxisSize mainAxisSize;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Row(
      mainAxisSize: mainAxisSize,
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Icon(icon, size: 16, color: scheme.onSurfaceVariant),
        const SizedBox(width: 4),
        child,
      ],
    );
  }
}
