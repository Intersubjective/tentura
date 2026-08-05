import 'package:flutter/material.dart';

import 'package:tentura/design_system/components/tentura_status_text.dart';
import 'package:tentura/design_system/tentura_design_system.dart';
import 'package:tentura/features/my_work/domain/derive_offer_response_state.dart';
import 'package:tentura/features/my_work/domain/entity/my_work_card_view_model.dart';
import 'package:tentura/ui/l10n/l10n.dart';

class MyWorkOfferResponseRow extends StatelessWidget {
  const MyWorkOfferResponseRow({
    required this.viewModel,
    super.key,
  });

  final MyWorkCardViewModel viewModel;

  @override
  Widget build(BuildContext context) {
    if (viewModel.role != MyWorkCardRole.helpOffered) {
      return const SizedBox.shrink();
    }

    final l10n = L10n.of(context)!;
    final tt = context.tt;
    final state = deriveMyWorkOfferResponseState(
      stakeState: viewModel.stakeState,
      authorResponseType: viewModel.authorResponseType,
      beaconStatus: viewModel.beacon.status,
    );
    final presentation = _presentationForState(state, l10n);

    return Padding(
      padding: EdgeInsets.only(top: tt.tightGap),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(
            presentation.icon,
            size: tt.iconSize,
            color: tenturaToneColor(tt, presentation.tone),
          ),
          SizedBox(width: tt.iconTextGap),
          Expanded(
            child: TenturaStatusText(
              presentation.label,
              tone: presentation.tone,
              maxLines: null,
              overflow: TextOverflow.visible,
            ),
          ),
        ],
      ),
    );
  }
}

class _OfferResponsePresentation {
  const _OfferResponsePresentation({
    required this.label,
    required this.tone,
    required this.icon,
  });

  final String label;
  final TenturaTone tone;
  final IconData icon;
}

_OfferResponsePresentation _presentationForState(
  MyWorkOfferResponseState state,
  L10n l10n,
) {
  return switch (state) {
    MyWorkOfferResponseState.awaitingAuthor => _OfferResponsePresentation(
      label: l10n.myWorkOfferAwaitingAuthor,
      tone: TenturaTone.neutral,
      icon: Icons.hourglass_empty_outlined,
    ),
    MyWorkOfferResponseState.accepted => _OfferResponsePresentation(
      label: l10n.myWorkOfferAccepted,
      tone: TenturaTone.good,
      icon: Icons.check_circle_outline,
    ),
    MyWorkOfferResponseState.declined => _OfferResponsePresentation(
      label: l10n.myWorkOfferDeclined,
      tone: TenturaTone.neutral,
      icon: Icons.cancel_outlined,
    ),
    MyWorkOfferResponseState.softened => _OfferResponsePresentation(
      label: l10n.myWorkOfferSoftened,
      tone: TenturaTone.warn,
      icon: Icons.edit_note_outlined,
    ),
    MyWorkOfferResponseState.participationEnded => _OfferResponsePresentation(
      label: l10n.myWorkOfferParticipationEnded,
      tone: TenturaTone.warn,
      icon: Icons.person_off_outlined,
    ),
    MyWorkOfferResponseState.exited => _OfferResponsePresentation(
      label: l10n.myWorkOfferExited,
      tone: TenturaTone.neutral,
      icon: Icons.logout,
    ),
    MyWorkOfferResponseState.closedWithoutResponse => _OfferResponsePresentation(
      label: l10n.myWorkOfferClosedWithoutResponse,
      tone: TenturaTone.warn,
      icon: Icons.lock_outline,
    ),
  };
}
