import 'dart:async';

import 'package:flutter/material.dart';
import 'package:tentura_root/domain/entity/beacon_status.dart';

import 'package:tentura/app/router/root_router.dart';
import 'package:tentura/features/beacon_view/ui/bloc/beacon_view_cubit.dart';
import 'package:tentura/features/beacon_view/ui/dialog/help_offer_message_dialog.dart';
import 'package:tentura/features/forward/domain/forward_draft_policy.dart';
import 'package:tentura/ui/l10n/l10n.dart';
import 'package:tentura/ui/utils/ui_utils.dart';

/// Whether Forward should appear in request overflow chrome.
bool beaconViewAllowsForwardAction({
  required BeaconViewState state,
  required bool showBeaconContent,
  required bool showInitialLoading,
}) {
  if (!showBeaconContent || showInitialLoading) return false;
  return state.beacon.allowsForward;
}

Future<void> beaconViewOpenForwardThenMaybeNudgeOfferHelp(
  BuildContext context,
  BeaconViewCubit cubit,
  L10n l10n,
) async {
  final hadOutgoingEdgeBefore = cubit.state.hasForwardedThisBeaconOnce;
  final id = cubit.state.beacon.id;
  await context.router.push(ForwardBeaconRoute(beaconId: id));
  if (!context.mounted) return;
  final s = cubit.state;
  final offerHelpAllowed = !s.isHelpOffered &&
      !s.isBeaconMine &&
      s.beacon.allowsNewHelpOfferAsNonAuthor &&
      s.beacon.status == BeaconStatus.open;
  if (!shouldNudgeOfferHelpAfterForwardVisit(
    hadOutgoingEdgeBefore: hadOutgoingEdgeBefore,
    hasOutgoingEdgeAfter: s.hasForwardedThisBeaconOnce,
    offerHelpAllowed: offerHelpAllowed,
  )) {
    return;
  }
  showSnackBar(
    context,
    text: l10n.nudgeOfferHelpAfterForward,
    action: SnackBarAction(
      label: l10n.labelOfferHelp,
      onPressed: () => unawaited(
        _runOfferHelpAfterForwardNudge(context, cubit, l10n),
      ),
    ),
  );
}

Future<void> _runOfferHelpAfterForwardNudge(
  BuildContext context,
  BeaconViewCubit cubit,
  L10n l10n,
) async {
  if (!context.mounted) return;
  final useOfferHelpAnyway =
      cubit.state.beacon.status == BeaconStatus.enoughHelp;
  final outcome = await HelpOfferMessageDialog.show(
    context,
    title: useOfferHelpAnyway
        ? l10n.dialogOfferHelpAnywayTitle
        : l10n.dialogOfferHelpTitle,
    hintText: l10n.hintOfferHelpMessage,
    allowEmptyMessage: false,
    showHelpTypeChips: true,
    automaticSlugs: cubit.state.beacon.needs,
  );
  if (outcome != null && context.mounted) {
    await cubit.offerHelp(
      message: outcome.message,
      helpTypes: outcome.helpTypesWire,
    );
  }
}

VoidCallback? beaconViewForwardOverflowAction({
  required BuildContext context,
  required BeaconViewState state,
  required BeaconViewCubit cubit,
  required L10n l10n,
  required bool showBeaconManagementOverflow,
  required bool showBeaconContent,
  required bool showInitialLoading,
}) {
  if (!showBeaconManagementOverflow) return null;
  if (!beaconViewAllowsForwardAction(
    state: state,
    showBeaconContent: showBeaconContent,
    showInitialLoading: showInitialLoading,
  )) {
    return null;
  }
  return () => unawaited(
        beaconViewOpenForwardThenMaybeNudgeOfferHelp(context, cubit, l10n),
      );
}
