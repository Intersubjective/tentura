import 'package:flutter/material.dart';

import 'package:tentura/features/my_work/domain/derive_my_work_cards.dart';
import 'package:tentura/features/my_work/ui/widget/my_work_card_status_strip.dart';
import 'package:tentura/features/my_work/ui/widget/my_work_status_line.dart';
import 'package:tentura/ui/l10n/l10n.dart';

import '../bloc/beacon_view_state.dart';

/// Operational status strip for the beacon view (coordination / inbox context).
class BeaconOperationalStatusStrip extends StatelessWidget {
  const BeaconOperationalStatusStrip({
    required this.state,
    super.key,
  });

  final BeaconViewState state;

  @override
  Widget build(BuildContext context) {
    final l10n = L10n.of(context)!;
    final beacon = state.beacon;

    TimelineCommitment? myCommitment;
    for (final c in state.commitments) {
      if (!c.isWithdrawn && c.user.id == state.myProfile.id) {
        myCommitment = c;
        break;
      }
    }
    final statusVm = myWorkCardViewModelForBeaconView(
      beacon: beacon,
      isBeaconMine: state.isBeaconMine,
      isCommitted: state.isCommitted,
      myCommitMessage: myCommitment?.message ?? '',
      myAuthorResponseType: myCommitment?.coordinationResponse,
      myCommitmentUpdatedAt: myCommitment?.updatedAt,
    );
    final statusLine = myWorkStatusLine(l10n: l10n, vm: statusVm);

    return MyWorkCardStatusStrip(
      data: statusLine,
    );
  }
}
