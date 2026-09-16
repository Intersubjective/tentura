import 'package:flutter/material.dart';
import 'package:tentura_root/domain/entity/beacon_access.dart';

import 'package:tentura/design_system/tentura_design_system.dart';
import 'package:tentura/domain/entity/beacon.dart';
import 'package:tentura/ui/l10n/l10n.dart';

/// Informational line for observers whose access comes only from a related
/// (parent/child) request. Applied and forwarded access are explained
/// elsewhere, so they take priority and hide this banner.
class RequestAccessReasonBanner extends StatelessWidget {
  const RequestAccessReasonBanner({
    required this.beacon,
    super.key,
  });

  final Beacon beacon;

  @override
  Widget build(BuildContext context) {
    if (beacon.accessLevel != BeaconAccessLevel.observer) {
      return const SizedBox.shrink();
    }

    final reasons = BeaconAccessReason.decode(beacon.accessReasons);
    if (reasons.contains(BeaconAccessReason.applied) ||
        reasons.contains(BeaconAccessReason.forwarded) ||
        !(reasons.contains(BeaconAccessReason.contextChild) ||
            reasons.contains(BeaconAccessReason.contextAncestor))) {
      return const SizedBox.shrink();
    }

    final l10n = L10n.of(context)!;
    final tt = context.tt;
    final scheme = Theme.of(context).colorScheme;

    return Padding(
      padding: EdgeInsets.only(bottom: tt.cardGap),
      child: TenturaTechCard(
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Icon(
              Icons.info_outline,
              size: tt.iconSize,
              color: scheme.onSurfaceVariant,
            ),
            SizedBox(width: tt.iconTextGap),
            Expanded(
              child: Text(
                l10n.requestAccessViaRelatedRequest,
                style: TenturaText.bodySmall(scheme.onSurfaceVariant),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
