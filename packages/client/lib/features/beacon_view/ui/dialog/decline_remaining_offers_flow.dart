import 'package:flutter/material.dart';

import 'package:tentura/ui/l10n/l10n.dart';

import '../bloc/beacon_view_cubit.dart';
import 'help_offer_admission_reason_dialog.dart';

/// «Decline remaining offers» (#268, D10): one confirmation, with an editable
/// reason each declined person sees privately, then one server call. Does
/// nothing when no offer is waiting (or the viewer may not decline).
///
/// Offered right after the author sets «Enough help», and from the People
/// tab while it stays set. Accepted helpers, watchers and recipients are
/// never touched; backup offers are kept.
Future<void> beaconViewOfferDeclineRemainingOffers(
  BuildContext context,
  BeaconViewCubit cubit,
) async {
  final state = cubit.state;
  if (!state.canDeclineRemainingOffers) return;
  final l10n = L10n.of(context)!;
  final reason = await HelpOfferAdmissionReasonDialog.show(
    context,
    title: l10n.declineRemainingOffersTitle(
      state.remainingPendingOffers.length,
    ),
    explanatoryNote: l10n.declineRemainingOffersNote,
    hintText: l10n.helpOfferDeclineDialogHint,
    submitLabel: l10n.declineRemainingOffersConfirm,
    initialText: l10n.declineRemainingOffersDefaultReason,
    destructive: true,
  );
  if (reason == null || !context.mounted) return;
  await cubit.declineRemainingOffers(reason: reason);
}
