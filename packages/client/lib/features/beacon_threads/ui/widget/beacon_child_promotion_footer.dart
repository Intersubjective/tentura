import 'package:flutter/material.dart';

import 'package:tentura/app/router/root_router.dart';
import 'package:tentura/design_system/tentura_design_system.dart';
import 'package:tentura/ui/l10n/l10n.dart';

import 'child_beacon_preview_loader.dart';

/// Compact Chat link to a promoted child under its source bubble.
///
/// Resolves via [ChildBeaconPreviewLoader] (not involvement).
/// Full request cards stay on NOW ([BeaconChildRequestCard]).
class BeaconChildPromotionFooter extends StatefulWidget {
  const BeaconChildPromotionFooter({required this.childBeaconId, super.key});

  final String childBeaconId;

  @override
  State<BeaconChildPromotionFooter> createState() =>
      _BeaconChildPromotionFooterState();
}

class _BeaconChildPromotionFooterState
    extends State<BeaconChildPromotionFooter>
    with ChildBeaconPreviewLoader {
  @override
  String get childBeaconId => widget.childBeaconId;

  void _openChild(String beaconId) {
    context.router.push(BeaconViewRoute(id: beaconId));
  }

  @override
  Widget build(BuildContext context) {
    final l10n = L10n.of(context)!;
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;

    if (!childPreviewLoaded) {
      // Stable compact height while loading — avoid shrink → expand jump.
      return TenturaTextAction(
        label: l10n.beaconHierarchyNoticeChildCreated,
        tone: TenturaTone.neutral,
        icon: const Icon(Icons.subdirectory_arrow_right_outlined),
        flushStart: true,
        onPressed: null,
      );
    }

    final summary = childPreview;
    if (summary == null || summary.isTombstone) {
      return Semantics(
        container: true,
        label: l10n.beaconChildFooterUnavailable,
        child: Text(
          l10n.beaconChildFooterUnavailable,
          style: theme.textTheme.bodySmall?.copyWith(
            color: scheme.onSurfaceVariant,
          ),
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
        ),
      );
    }

    final title = summary.title?.trim().isNotEmpty == true
        ? summary.title!.trim()
        : l10n.beaconUntitled;

    return TenturaTextAction(
      label: title,
      tone: TenturaTone.info,
      icon: const Icon(Icons.subdirectory_arrow_right_outlined),
      flushStart: true,
      onPressed: () => _openChild(summary.beaconId),
    );
  }
}
