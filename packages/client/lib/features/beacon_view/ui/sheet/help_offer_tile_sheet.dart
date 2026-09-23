import 'dart:async';

import 'package:flutter/material.dart';

import 'package:tentura/design_system/tentura_design_system.dart';
import 'package:tentura/domain/entity/beacon.dart';
import 'package:tentura/domain/entity/commitment_stake_state.dart';
import 'package:tentura/domain/entity/profile.dart';
import 'package:tentura/features/beacon_view/domain/use_case/beacon_view_case.dart';
import 'package:tentura/features/beacon_view/ui/bloc/help_offer_tile_sheet_cubit.dart';
import 'package:tentura/features/beacon_view/ui/dialog/help_offer_admission_reason_dialog.dart';
import 'package:tentura/features/beacon_view/ui/dialog/help_offer_role_label_dialog.dart';
import 'package:tentura/features/beacon_view/ui/widget/help_offer_tile.dart';
import 'package:tentura/features/profile/ui/bloc/profile_cubit.dart';
import 'package:tentura/ui/effect/ui_effect_port.dart';
import 'package:tentura/ui/l10n/l10n.dart';

/// Opens a People-tab-identical help-offer card for admission from My Desk.
Future<void> showHelpOfferTileSheet({
  required BuildContext context,
  required String beaconId,
  required String offerUserId,
  required Profile myProfile,
  Beacon? initialBeacon,
  BeaconViewCase? beaconViewCase,
  UiEffectPort? effects,
}) {
  return showTenturaAdaptiveSheet<void>(
    context: context,
    builder: (sheetContext) {
      return BlocProvider(
        create: (_) {
          final cubit = HelpOfferTileSheetCubit(
            beaconId: beaconId,
            offerUserId: offerUserId,
            myProfile: myProfile,
            initialBeacon: initialBeacon,
            beaconViewCase: beaconViewCase,
            effects: effects,
          );
          unawaited(cubit.load());
          return cubit;
        },
        child: const _HelpOfferTileSheetBody(),
      );
    },
  );
}

class _HelpOfferTileSheetBody extends StatelessWidget {
  const _HelpOfferTileSheetBody();

  @override
  Widget build(BuildContext context) {
    final l10n = L10n.of(context)!;
    final tt = context.tt;
    return SafeArea(
      child: Padding(
        padding: EdgeInsets.all(tt.cardPadding.left),
        child: BlocBuilder<HelpOfferTileSheetCubit, HelpOfferTileSheetState>(
          builder: (context, state) {
            if (state.isLoading && state.offer == null) {
              return const SizedBox(
                height: 160,
                child: Center(child: CircularProgressIndicator()),
              );
            }
            if (state.loadError != null && state.offer == null) {
              return Padding(
                padding: EdgeInsets.symmetric(vertical: tt.sectionGap),
                child: TenturaStatusText(l10n.beaconViewLoadErrorBody),
              );
            }
            final offer = state.offer;
            if (offer == null) {
              return Padding(
                padding: EdgeInsets.symmetric(vertical: tt.sectionGap),
                child: TenturaStatusText(l10n.myWorkObligationOfferMissing),
              );
            }
            final cubit = context.read<HelpOfferTileSheetCubit>();
            final canManage = cubit.canManageOffer;
            return SingleChildScrollView(
              child: HelpOfferTile(
                helpOffer: offer,
                beaconId: state.beaconId,
                beaconAuthor: state.beacon.author,
                beaconAuthorId: state.beacon.author.id,
                isAuthorView: state.isAuthorOrSteward,
                isMine: offer.user.id == state.myProfile.id,
                participant: state.participant,
                onEditRole: cubit.canEditRole
                    ? () async {
                        final next = await HelpOfferRoleLabelDialog.show(
                          context,
                          initialText: offer.roleLabel ?? '',
                        );
                        if (next == null || !context.mounted) return;
                        await cubit.setRoleLabel(next);
                      }
                    : null,
                onAccept: canManage
                    ? () async {
                        final ok = await cubit.accept();
                        if (ok && context.mounted) Navigator.of(context).pop();
                      }
                    : null,
                onDecline: canManage
                    ? () async {
                        final reason = await HelpOfferAdmissionReasonDialog.show(
                          context,
                          title: l10n.helpOfferDeclineDialogTitle,
                          hintText: l10n.helpOfferDeclineDialogHint,
                        );
                        if (reason == null || !context.mounted) return;
                        final ok = await cubit.decline(reason: reason);
                        if (ok && context.mounted) Navigator.of(context).pop();
                      }
                    : null,
                onReleaseCommitment:
                    canManage &&
                        offer.stakeState == CommitmentStakeState.acknowledged
                    ? () async {
                        final reason =
                            await HelpOfferAdmissionReasonDialog.show(
                          context,
                          title: l10n.helpOfferReleaseDialogTitle,
                          hintText: l10n.helpOfferReleaseDialogHint,
                        );
                        if (reason == null || !context.mounted) return;
                        final ok = await cubit.release(reason: reason);
                        if (ok && context.mounted) Navigator.of(context).pop();
                      }
                    : null,
              ),
            );
          },
        ),
      ),
    );
  }
}

/// Convenience for My Desk: resolves [myProfile] from [ProfileCubit] when present.
Future<void> showHelpOfferTileSheetFromDesk({
  required BuildContext context,
  required String beaconId,
  required String offerUserId,
  required Beacon beacon,
}) async {
  Profile myProfile;
  try {
    myProfile = context.read<ProfileCubit>().state.profile;
  } on ProviderNotFoundException {
    myProfile = GetIt.I<ProfileCubit>().state.profile;
  }
  await showHelpOfferTileSheet(
    context: context,
    beaconId: beaconId,
    offerUserId: offerUserId,
    myProfile: myProfile,
    initialBeacon: beacon,
  );
}
