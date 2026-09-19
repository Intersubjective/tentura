import 'package:flutter/material.dart';

import 'package:tentura/features/inbox/ui/widget/request_attention_indicators.dart';
import 'package:tentura/features/my_work/domain/derive_my_work_card_attention.dart';
import 'package:tentura/features/my_work/domain/entity/my_work_card_view_model.dart';
import 'package:tentura/features/my_work/ui/bloc/my_work_cubit.dart';

/// U14c's [RequestAttentionIndicators], mounted on a My Desk card.
///
/// The facts come from [myWorkCardAttentionView] — the same derivation that
/// produces the rows the card's active-event block renders — so the dot and
/// the list cannot disagree (M1).
class MyWorkCardAttentionIndicators extends StatelessWidget {
  const MyWorkCardAttentionIndicators({required this.vm, super.key});

  final MyWorkCardViewModel vm;

  @override
  Widget build(BuildContext context) {
    final view = myWorkCardAttentionView(
      beaconId: vm.beaconId,
      attention: context.select(
        (MyWorkCubit c) => c.state.attentionByBeacon[vm.beaconId],
      ),
      viewerArchived: vm.viewerArchived,
    );
    return RequestAttentionIndicators(facts: view.facts);
  }
}
