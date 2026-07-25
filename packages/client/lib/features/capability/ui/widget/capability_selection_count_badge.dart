import 'package:flutter/material.dart';

import 'package:tentura/design_system/tentura_design_system.dart';

/// Compact selection-count pill used on capability accordion headers.
class CapabilitySelectionCountBadge extends StatelessWidget {
  const CapabilitySelectionCountBadge({
    required this.count,
    this.preExisting = false,
    super.key,
  });

  final int count;
  final bool preExisting;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final tt = context.tt;
    final cs = theme.colorScheme;
    final bg = preExisting ? cs.secondaryContainer : cs.primaryContainer;
    final fg = preExisting ? cs.onSecondaryContainer : cs.onPrimaryContainer;
    final text = preExisting ? '★ $count' : '$count';
    return Padding(
      padding: EdgeInsets.only(left: tt.tightGap),
      child: Material(
        color: bg,
        borderRadius: BorderRadius.circular(TenturaRadii.avatar),
        child: Padding(
          padding: EdgeInsets.symmetric(
            horizontal: tt.tightGap,
            vertical: tt.tightGap / 2,
          ),
          child: Text(
            text,
            style: theme.textTheme.labelSmall?.copyWith(
              color: fg,
              fontWeight: FontWeight.w600,
            ),
          ),
        ),
      ),
    );
  }
}

/// Keeps a fixed badge footprint so headers do not shift when counts appear.
class CapabilityReservedCountSlot extends StatelessWidget {
  const CapabilityReservedCountSlot({
    required this.visible,
    required this.count,
    this.preExisting = false,
    super.key,
  });

  final bool visible;
  final int count;
  final bool preExisting;

  @override
  Widget build(BuildContext context) {
    return Stack(
      alignment: Alignment.centerRight,
      children: [
        const Opacity(
          opacity: 0,
          child: CapabilitySelectionCountBadge(
            count: 9,
            preExisting: true,
          ),
        ),
        if (visible)
          CapabilitySelectionCountBadge(
            count: count,
            preExisting: preExisting,
          ),
      ],
    );
  }
}
