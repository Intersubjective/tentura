import 'dart:async';

import 'package:flutter/material.dart';
import 'package:get_it/get_it.dart';
import 'package:tentura_root/domain/entity/beacon_status.dart';

import 'package:tentura/app/router/root_router.dart';
import 'package:tentura/domain/entity/beacon.dart';
import 'package:tentura/features/beacon_view/ui/dialog/help_offer_message_dialog.dart';
import 'package:tentura/features/beacon_view/ui/message/help_offer_messages.dart';
import 'package:tentura/features/forward/data/repository/forward_repository.dart';
import 'package:tentura/features/forward/domain/forward_draft_policy.dart';
import 'package:tentura/ui/effect/ui_effect.dart';
import 'package:tentura/ui/effect/ui_effect_port.dart';
import 'package:tentura/ui/l10n/l10n.dart';
import 'package:tentura/ui/utils/ui_utils.dart';

import '../../domain/entity/inbox_item.dart';
import '../../domain/enum.dart';
import '../bloc/inbox_cubit.dart';

bool inboxCardAllowsOfferHelp(InboxItem item) {
  final b = item.beacon;
  return b != null &&
      b.allowsNewHelpOfferAsNonAuthor &&
      item.status != InboxItemStatus.rejected;
}

Future<void> inboxOfferHelp(BuildContext context, Beacon beacon) async {
  final l10n = L10n.of(context)!;
  final useOfferHelpAnyway = beacon.status == BeaconStatus.enoughHelp;
  final outcome = await HelpOfferMessageDialog.show(
    context,
    title: useOfferHelpAnyway
        ? l10n.dialogOfferHelpAnywayTitle
        : l10n.dialogOfferHelpTitle,
    hintText: l10n.hintOfferHelpMessage,
    allowEmptyMessage: false,
    showHelpTypeChips: true,
    automaticSlugs: beacon.needs,
  );
  if (outcome == null || !context.mounted) return;
  final ok = await GetIt.I<ForwardRepository>().offerHelp(
    beaconId: beacon.id,
    message: outcome.message,
    helpTypes: outcome.helpTypesWire,
  );
  if (!context.mounted || !ok) return;
  GetIt.I<UiEffectPort>().emit(
    ShowMessage(HelpOfferedForwardNudgeMessage(beacon.id)),
  );
}

Future<void> inboxForwardItem(BuildContext context, InboxItem item) async {
  final hadOutgoingEdgeBefore = item.isForwardedByMe;
  await context.router.push(ForwardBeaconRoute(beaconId: item.beaconId));
  if (!context.mounted) return;
  final cubit = context.read<InboxCubit>();
  InboxItem? afterItem;
  for (final e in cubit.state.items) {
    if (e.beaconId == item.beaconId) {
      afterItem = e;
      break;
    }
  }
  final hasOutgoingEdgeAfter = afterItem?.isForwardedByMe ?? false;
  final offerHelpAllowed =
      afterItem != null && inboxCardAllowsOfferHelp(afterItem);
  if (!shouldNudgeOfferHelpAfterForwardVisit(
    hadOutgoingEdgeBefore: hadOutgoingEdgeBefore,
    hasOutgoingEdgeAfter: hasOutgoingEdgeAfter,
    offerHelpAllowed: offerHelpAllowed,
  )) {
    return;
  }
  final l10n = L10n.of(context)!;
  showSnackBar(
    context,
    text: l10n.nudgeOfferHelpAfterForward,
    action: SnackBarAction(
      label: l10n.labelOfferHelp,
      onPressed: () => unawaited(inboxOfferHelp(context, afterItem!.beacon!)),
    ),
  );
}
