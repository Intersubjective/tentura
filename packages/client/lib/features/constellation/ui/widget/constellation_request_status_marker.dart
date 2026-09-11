import 'package:flutter/material.dart';
import 'package:tentura_root/domain/entity/beacon_status.dart';

import 'package:tentura/design_system/tentura_design_system.dart';
import 'package:tentura/ui/l10n/l10n.dart';
import 'package:tentura/ui/test_ids.dart';

import '../../domain/entity/constellation_anchor_projection.dart';

/// Validated constellation request status presentation (C2 / D status table).
@immutable
class ConstellationRequestStatusPresentation {
  const ConstellationRequestStatusPresentation({
    required this.rawStatus,
    required this.status,
    required this.icon,
    required this.color,
    required this.label,
  });

  final int rawStatus;
  final BeaconStatus status;
  final IconData icon;
  final Color color;
  final String label;
}

/// Rejects unknown raw statuses before mapping; never paints unknown as Open.
ConstellationRequestStatusPresentation? constellationRequestStatusPresentation({
  required int rawStatus,
  required L10n l10n,
  required TenturaTokens tt,
}) {
  if (!isKnownConstellationBeaconStatus(rawStatus)) {
    return null;
  }
  final status = BeaconStatus.fromSmallint(rawStatus);
  return switch (status) {
    BeaconStatus.open => ConstellationRequestStatusPresentation(
      rawStatus: rawStatus,
      status: status,
      icon: Icons.circle_outlined,
      color: tt.border,
      label: l10n.constellationRequestStatusOpen,
    ),
    BeaconStatus.needsMoreHelp => ConstellationRequestStatusPresentation(
      rawStatus: rawStatus,
      status: status,
      icon: Icons.person_add_alt_1_outlined,
      color: tt.warn,
      label: l10n.constellationRequestStatusNeedsMoreHelp,
    ),
    BeaconStatus.enoughHelp => ConstellationRequestStatusPresentation(
      rawStatus: rawStatus,
      status: status,
      icon: Icons.check,
      color: tt.good,
      label: l10n.constellationRequestStatusEnoughHelp,
    ),
    BeaconStatus.reviewOpen => ConstellationRequestStatusPresentation(
      rawStatus: rawStatus,
      status: status,
      icon: Icons.schedule,
      color: tt.info,
      label: l10n.constellationRequestStatusWrappingUp,
    ),
    BeaconStatus.closed => ConstellationRequestStatusPresentation(
      rawStatus: rawStatus,
      status: status,
      icon: Icons.task_alt,
      color: tt.textMuted,
      label: l10n.constellationRequestStatusClosed,
    ),
    _ => null,
  };
}

/// Shared status + independent pin markers for map, text, and legend.
class ConstellationRequestStatusMarker extends StatelessWidget {
  const ConstellationRequestStatusMarker({
    required this.rawStatus,
    required this.isPinned,
    this.showStatus = true,
    this.showPin = true,
    this.iconSize,
    super.key,
  });

  final int? rawStatus;
  final bool isPinned;
  final bool showStatus;
  final bool showPin;
  final double? iconSize;

  @override
  Widget build(BuildContext context) {
    final tt = context.tt;
    final l10n = L10n.of(context)!;
    final size = iconSize ?? tt.iconSize * 0.85;
    final children = <Widget>[];

    if (showStatus && rawStatus != null) {
      final presentation = constellationRequestStatusPresentation(
        rawStatus: rawStatus!,
        l10n: l10n,
        tt: tt,
      );
      if (presentation != null) {
        children.add(
          Semantics(
            key: TestIds.key(TestIds.constellationRequestStatusMarker),
            label: presentation.label,
            child: Icon(
              presentation.icon,
              size: size,
              color: presentation.color,
            ),
          ),
        );
      }
    }

    if (showPin && isPinned) {
      if (children.isNotEmpty) {
        children.add(SizedBox(width: tt.tightGap / 2));
      }
      children.add(
        Semantics(
          identifier: TestIds.constellationPinMarker,
          key: TestIds.key(TestIds.constellationPinMarker),
          label: l10n.constellationPinMarkerSemantics,
          child: Icon(
            Icons.push_pin,
            size: size,
            color: tt.info,
          ),
        ),
      );
    }

    if (children.isEmpty) {
      return const SizedBox.shrink();
    }

    return Row(
      mainAxisSize: MainAxisSize.min,
      children: children,
    );
  }
}

/// Semantics fragments for text/list rows (status + optional pin).
List<String> constellationRequestMarkerSemantics({
  required L10n l10n,
  required TenturaTokens tt,
  required int? rawStatus,
  required bool isPinned,
}) {
  final parts = <String>[];
  if (rawStatus != null) {
    final presentation = constellationRequestStatusPresentation(
      rawStatus: rawStatus,
      l10n: l10n,
      tt: tt,
    );
    if (presentation != null) {
      parts.add(presentation.label);
    }
  }
  if (isPinned) {
    parts.add(l10n.constellationPinMarkerSemantics);
  }
  return parts;
}
