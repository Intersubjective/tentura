import 'dart:async';

import 'package:flutter/material.dart';
import 'package:get_it/get_it.dart';

import 'package:tentura/app/router/root_router.dart';
import 'package:tentura/consts.dart';
import 'package:tentura/features/invitation/ui/bloc/invitation_cubit.dart';
import 'package:tentura/ui/dialog/share_code_dialog.dart';
import 'package:tentura/ui/l10n/l10n.dart';
import 'package:tentura/ui/utils/ui_utils.dart';

/// «Invite new person»: mints an invite tied to [beaconId] (a plain one when
/// it is empty) and shows its share dialog.
///
/// Shared by the Forward picker and a Post's participants «Позвать» (#715),
/// which opens this dialog directly instead of the Forward screen.
Future<void> runBeaconInviteFlow(
  BuildContext context, {
  required InvitationCubit invitations,
  required String beaconId,
  required bool isPost,
}) async {
  final l10n = L10n.of(context)!;

  final invitation = await invitations.createInvitation(
    addresseeName: '',
    beaconId: beaconId.isNotEmpty ? beaconId : null,
  );
  if (invitation == null || !context.mounted) return;

  await WidgetsBinding.instance.endOfFrame;
  if (!context.mounted) return;

  // A request invite says what it does: who it brings in, to what, and
  // that the link is single-use with a limited life (#452).
  final forBeacon = beaconId.isNotEmpty;
  // The dialog opens at once on the compiled default and corrects its day
  // count when the served lifetime arrives.
  final servedDays = invitations.inviteTtlDays();
  String body(int days) => isPost
      ? l10n.forwardInviteDialogBodyPost(days)
      : l10n.forwardInviteDialogBody(days);
  final used = await ShareCodeDialog.show(
    context,
    header: !forBeacon
        ? l10n.labelInvitationCode
        : isPost
        ? l10n.forwardInviteDialogTitlePost
        : l10n.forwardInviteDialogTitle,
    caption: forBeacon ? body(kInvitationDefaultTTL ~/ 24) : null,
    captionUpdate: forBeacon ? servedDays.then(body) : null,
    link: inviteShareUri(invitation.id),
  );
  // Closed without Copy, Share, a hand selection of the link (#605) or a
  // visible QR: the link never left the dialog, so drop the invite
  // instead of leaving a silent one (#454).
  if (!used) {
    await invitations.deleteInvitationById(invitation.id);
    return;
  }
  if (!context.mounted) return;
  showSnackBar(
    context,
    text: l10n.forwardInviteCreatedHint,
    action: SnackBarAction(
      label: l10n.forwardViewInvitations,
      onPressed: () => unawaited(GetIt.I<RootRouter>().openInvitations()),
    ),
  );
}
