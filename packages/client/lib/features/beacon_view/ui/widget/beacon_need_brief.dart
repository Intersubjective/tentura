import 'package:flutter/material.dart';

import 'package:tentura/design_system/tentura_design_system.dart';
import 'package:tentura/domain/entity/beacon.dart';
import 'package:tentura/ui/l10n/l10n.dart';

/// One-line need summary under the author row on beacon detail (when [Beacon.hasNeedSummary]).
class BeaconNeedBrief extends StatelessWidget {
  const BeaconNeedBrief({required this.beacon, super.key});

  final Beacon beacon;

  @override
  Widget build(BuildContext context) {
    if (!beacon.hasNeedSummary) {
      return const SizedBox.shrink();
    }
    final l10n = L10n.of(context)!;
    final tt = context.tt;
    return Padding(
      padding: EdgeInsets.only(top: tt.rowGap / 2),
      child: Text(
        '${l10n.beaconNeedBriefPrefix} ${beacon.needSummary!.trim()}',
        style: TenturaText.body(tt.textMuted),
        softWrap: true,
        overflow: TextOverflow.visible,
      ),
    );
  }
}
