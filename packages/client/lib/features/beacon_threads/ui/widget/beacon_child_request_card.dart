import 'package:flutter/material.dart';
import 'package:get_it/get_it.dart';
import 'package:tentura_root/domain/entity/beacon_hierarchy_summary.dart';

import 'package:tentura/design_system/tentura_design_system.dart';
import 'package:tentura/ui/l10n/l10n.dart';
import 'package:tentura/ui/navigation/app_navigator.dart';
import 'package:tentura/ui/widget/beacon_card_primitives.dart';
import 'package:tentura/ui/widget/beacon_request_preview_identity.dart';

class BeaconChildRequestCard extends StatelessWidget {
  const BeaconChildRequestCard({
    required this.summary,
    required this.currentUserId,
    super.key,
  });

  final BeaconHierarchySummary summary;
  final String currentUserId;

  @override
  Widget build(BuildContext context) {
    final l10n = L10n.of(context)!;
    final tt = context.tt;
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;

    if (summary.isTombstone) {
      return Semantics(
        container: true,
        label: l10n.beaconDeletedChild,
        child: BeaconCardShell(
          muted: true,
          child: Padding(
            padding: EdgeInsets.symmetric(vertical: tt.tightGap),
            child: Text(
              l10n.beaconDeletedChild,
              style: theme.textTheme.bodyMedium?.copyWith(
                color: scheme.onSurfaceVariant,
              ),
            ),
          ),
        ),
      );
    }

    final data = BeaconRequestPreviewData.fromHierarchySummary(
      l10n,
      summary,
      now: DateTime.now(),
    );

    return BeaconCardShell(
      onTap: () => GetIt.I<AppNavigator>().openBeacon(summary.beaconId),
      // #416: the visible title already names the card.
      tapSemanticsLabel: data.title.isEmpty ? null : '',
      child: BeaconRequestPreviewIdentity(
        data: data,
        currentUserId: currentUserId,
        showDescription: true,
      ),
    );
  }
}
