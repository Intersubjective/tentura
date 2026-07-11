import 'dart:async';
import 'package:tentura_root/domain/entity/beacon_status.dart';

import 'package:flutter/material.dart';
import 'package:tentura/app/router/root_router.dart';
import 'package:tentura/design_system/tentura_design_system.dart';
import 'package:tentura/domain/entity/beacon_room_consts.dart';
import 'package:tentura/domain/entity/coordination_item.dart';
import 'package:tentura/features/beacon/ui/dialog/beacon_delete_dialog.dart';
import 'package:tentura/features/beacon/ui/util/beacon_lifecycle_ui.dart';
import 'package:tentura/features/beacon/ui/util/beacon_lineage_overflow_actions.dart';
import 'package:tentura/features/beacon/ui/widget/beacon_overflow_menu.dart';
import 'package:tentura/features/beacon_room/ui/bloc/room_cubit.dart';
import 'package:tentura/features/beacon_room/ui/widget/beacon_room_body.dart'
    show showBeaconRoomUpdatePlanSheet;
import 'package:tentura/features/beacon_room/ui/widget/beacon_room_poll_sheet.dart';
import 'package:tentura/features/beacon_view/ui/widget/coordination_item_composer_sheet.dart';
import 'package:tentura/features/beacon_view/ui/widget/coordination_target_candidates.dart';
import 'package:tentura/features/beacon_view/ui/presenter/beacon_hud_author_action.dart';
import 'package:tentura/features/beacon_view/ui/bloc/beacon_view_cubit.dart';
import 'package:tentura/features/beacon_view/ui/dialog/help_offer_message_dialog.dart';
import 'package:tentura/features/beacon_view/ui/util/beacon_closure_readiness.dart';
import 'package:tentura/features/beacon_view/ui/util/help_offer_types_wire.dart';
import 'package:tentura/features/inbox/domain/enum.dart';
import 'package:tentura/features/inbox/ui/widget/rejection_dialog.dart';
import 'package:tentura/ui/bloc/screen_cubit.dart';
import 'package:tentura/features/beacon/ui/sheet/beacon_share_sheet.dart';
import 'package:tentura/ui/l10n/l10n.dart';
import 'package:tentura/ui/utils/ui_utils.dart';

import 'beacon_hud_author_confirm_sheets.dart';
import 'beacon_view_status_bottom_sheet.dart';
import 'package:tentura/features/beacon/ui/sheet/beacon_close_confirm_sheet.dart'
    show showBeaconCloseConfirmSheet;

/// Initial help offer dialog + [BeaconViewCubit.offerHelp].
Future<void> beaconViewRunInitialHelpOfferDialog(
  BuildContext context,
  BeaconViewCubit cubit,
  L10n l10n,
) async {
  if (!context.mounted) return;
  final useOfferHelpAnyway =
      cubit.state.beacon.status ==
      BeaconStatus.enoughHelp;
  final outcome = await HelpOfferMessageDialog.show(
    context,
    title: useOfferHelpAnyway
        ? l10n.dialogOfferHelpAnywayTitle
        : l10n.dialogOfferHelpTitle,
    hintText: l10n.hintOfferHelpMessage,
    allowEmptyMessage: true,
    showHelpTypeChips: true,
  );
  if (outcome != null && context.mounted) {
    await cubit.offerHelp(
      message: outcome.message,
      helpTypes: outcome.helpTypesWire,
    );
  }
}

/// Edit active help offer dialog + [BeaconViewCubit.offerHelp].
Future<void> beaconViewRunEditHelpOfferDialog(
  BuildContext context,
  BeaconViewCubit cubit,
  L10n l10n,
) async {
  if (!context.mounted) return;
  final offer = cubit.state.myActiveHelpOffer;
  if (offer == null) return;
  final outcome = await HelpOfferMessageDialog.show(
    context,
    title: l10n.beaconHeaderUpdateHelpOffer,
    hintText: l10n.hintOfferHelpMessage,
    initialText: offer.message,
    allowEmptyMessage: true,
    showHelpTypeChips: true,
    initialHelpTypeSlugs: helpOfferStoredHelpTypeSlugs(offer.helpType),
    automaticSlugs: cubit.state.beacon.needs,
  );
  if (outcome != null && context.mounted) {
    await cubit.offerHelp(
      message: outcome.message,
      helpTypes: normalizeOfferHelpTypesWire(outcome.helpTypesWire),
    );
  }
}

Future<void> beaconViewOpenForwardThenMaybeNudgeOfferHelp(
  BuildContext context,
  BeaconViewCubit cubit,
  L10n l10n,
) async {
  final id = cubit.state.beacon.id;
  final didForward = await context.router.push<bool>(
    ForwardBeaconRoute(beaconId: id),
  );
  if (!context.mounted || didForward != true) return;
  final s = cubit.state;
  if (s.isHelpOffered ||
      s.isBeaconMine ||
      !s.beacon.allowsNewHelpOfferAsNonAuthor ||
      s.beacon.status != BeaconStatus.open) {
    return;
  }
  showSnackBar(
    context,
    text: l10n.nudgeOfferHelpAfterForward,
    action: SnackBarAction(
      label: l10n.labelOfferHelp,
      onPressed: () => unawaited(
        beaconViewRunInitialHelpOfferDialog(context, cubit, l10n),
      ),
    ),
  );
}

bool forwardInPrimaryCta(BeaconViewState state) {
  final b = state.beacon;
  if (state.isBeaconMine || b.status != BeaconStatus.open) {
    return false;
  }
  if (!state.isHelpOffered && b.allowsNewHelpOfferAsNonAuthor) {
    return true;
  }
  if (state.isHelpOffered && !b.allowsWithdrawWhileHelpOffered) {
    return true;
  }
  return false;
}

bool hideOfferHelpWithdrawFromOverflow(BeaconViewState state) {
  final b = state.beacon;
  if (state.isBeaconMine || b.status != BeaconStatus.open) {
    return false;
  }
  if (!state.isHelpOffered && b.allowsNewHelpOfferAsNonAuthor) {
    return true;
  }
  if (state.isHelpOffered && b.allowsWithdrawWhileHelpOffered) {
    return true;
  }
  return false;
}

bool _authorLifecycleToggleEnabled(BeaconViewState state) {
  final b = state.beacon;
  if (b.status == BeaconStatus.open && b.isListed) {
    return state.closureActionPriority != ClosureActionPriority.hidden;
  }
  return true;
}

(String, TenturaTone) beaconViewRoomAppBarStatus(L10n l10n, int roomUnread) {
  if (roomUnread > 0) {
    return (
      '${l10n.beaconRoomTitle} · ${l10n.beaconRoomUnreadDividerCount(roomUnread)}',
      TenturaTone.info,
    );
  }
  return (l10n.inboxCardRoomUnread(0), TenturaTone.neutral);
}

String beaconViewRoomAppBarTooltip(BeaconViewState state, L10n l10n) {
  if (state.canNavigateBeaconRoom) {
    return l10n.beaconRoomOpen;
  }
  if (state.isRoomAdmissionBlocked) {
    return state.coordinationDeniesRoomAdmission
        ? l10n.beaconRoomNoAdmission
        : l10n.beaconRoomWaitingForApproval;
  }
  return l10n.beaconViewRoomAccessUnavailableBanner;
}

Future<void> beaconViewRunAuthorCloseSheet({
  required BuildContext context,
  required BeaconViewCubit cubit,
  required L10n l10n,
  required void Function() onOpenPeopleTab,
  required void Function([CoordinationItem? focusItem]) onEnterRoomSurface,
}) async {
  if (!context.mounted) return;
  var summary = buildClosureConfirmationSummary(cubit.state);

  Future<bool> attemptClose(bool expected) async {
    final result = await cubit.closeBeacon(
      expectedRequiresReviewWindow: expected,
    );
    if (!context.mounted || result == null) return false;
    if (result.branchMismatch) {
      if (!context.mounted) return false;
      summary = buildClosureConfirmationSummary(cubit.state);
      return showBeaconCloseConfirmSheet(
        context: context,
        summary: summary,
        isLoading: cubit.state.isLoading,
        onCloseBeacon: attemptClose,
        onOpenPeople: onOpenPeopleTab,
        onResolveRoom: cubit.state.canNavigateBeaconRoom
            ? () => onEnterRoomSurface()
            : null,
      );
    }
    return true;
  }

  await showBeaconCloseConfirmSheet(
    context: context,
    summary: summary,
    isLoading: cubit.state.isLoading,
    onCloseBeacon: attemptClose,
    onOpenPeople: onOpenPeopleTab,
    onResolveRoom: cubit.state.canNavigateBeaconRoom
        ? () => onEnterRoomSurface()
        : null,
  );
}

Future<void> beaconViewHandleAuthorHudAction({
  required BuildContext context,
  required BeaconViewCubit cubit,
  required L10n l10n,
  required BeaconHudAuthorAction action,
  required void Function() onOpenPeopleTab,
  required void Function() onActivatePeopleAttention,
  required void Function(CoordinationItem item) onFocusCoordinationItem,
  required void Function() onOpenItemsTab,
  required void Function([CoordinationItem? focusItem]) onEnterRoomSurface,
}) async {
  if (!context.mounted || cubit.state.isLoading) return;
  final expected = deriveBeaconHudAuthorAction(cubit.state);
  if (expected != action) return;

  switch (action) {
    case BeaconHudAuthorAction.resolveBlocker:
      final blocker = cubit.state.openCoordinationBlocker;
      if (blocker != null) {
        onFocusCoordinationItem(blocker);
      } else {
        onOpenItemsTab();
      }
    case BeaconHudAuthorAction.reviewOffers:
      // [onActivatePeopleAttention] already selects People and sets attention
      // (expands "Willing to help"). Do not call [onOpenPeopleTab] here — it
      // routes through _setTab, which clears attention when already on People.
      onActivatePeopleAttention();
    case BeaconHudAuthorAction.markEnoughHelp:
      final confirmed = await showBeaconHudMarkEnoughHelpConfirmSheet(
        context: context,
      );
      if (!context.mounted) return;
      if (!confirmed) return;
      if (deriveBeaconHudAuthorAction(cubit.state) !=
          BeaconHudAuthorAction.markEnoughHelp) {
        return;
      }
      await cubit.setBeaconStatus(BeaconStatus.enoughHelp);
    case BeaconHudAuthorAction.wrapUpForReview:
      await beaconViewRunAuthorCloseSheet(
        context: context,
        cubit: cubit,
        l10n: l10n,
        onOpenPeopleTab: onOpenPeopleTab,
        onEnterRoomSurface: onEnterRoomSurface,
      );
    case BeaconHudAuthorAction.reviewContributions:
      final beaconId = cubit.state.beacon.id;
      await context.router.push(ReviewContributionsRoute(id: beaconId));
      if (context.mounted) {
        await cubit.refreshReviewWindowInfo();
      }
    case BeaconHudAuthorAction.closeNow:
      final canClose = cubit.state.reviewWindowInfo?.canCloseNow == true;
      final confirmed = await showBeaconHudCloseNowConfirmSheet(
        context: context,
        canCloseNow: canClose,
      );
      if (!context.mounted) return;
      if (!confirmed) return;
      if (deriveBeaconHudAuthorAction(cubit.state) !=
          BeaconHudAuthorAction.closeNow) {
        return;
      }
      await cubit.closeBeaconNow();
    case BeaconHudAuthorAction.forward:
      await beaconViewOpenForwardThenMaybeNudgeOfferHelp(context, cubit, l10n);
  }
}

bool beaconViewShowsRequestStatusOverflow(BeaconViewState state) {
  if (!state.isAuthorOrSteward) return false;
  final lifecycle = state.beacon.status;
  return lifecycle == BeaconStatus.draft ||
      lifecycle.isOpenFamily ||
      lifecycle == BeaconStatus.reviewOpen;
}

bool canShowCreatePromise(BeaconViewState state) {
  final b = state.beacon;
  if (b.status != BeaconStatus.open) return false;
  if (!state.isAuthorOrSteward && !state.hasRoomAdmission) return false;
  return hasPublishedPromiseTargets(
    participants: state.roomParticipants,
    myUserId: state.myProfile.id,
    isAuthorOrSteward: state.isAuthorOrSteward,
  );
}

VoidCallback? beaconViewRoomCreatePromiseAction({
  required BuildContext context,
  required BeaconViewState state,
  required String beaconId,
  required VoidCallback onSaved,
  required bool inRoomSurface,
}) {
  if (!inRoomSurface || !canShowCreatePromise(state)) return null;
  return () => unawaited(
        showCoordinationItemComposerSheet(
          context,
          kind: CoordinationItemKind.promise,
          beaconId: beaconId,
          participants: state.roomParticipants,
          beaconAuthorId: state.beacon.author.id,
          myUserId: state.myProfile.id,
          isAuthorOrSteward: state.isAuthorOrSteward,
          useRootNavigator: true,
          enableDrag: false,
          onSaved: onSaved,
        ),
      );
}

VoidCallback? beaconViewRoomCreatePollAction({
  required BuildContext context,
  required RoomCubit? roomCubit,
  required bool inRoomSurface,
}) {
  if (!inRoomSurface || roomCubit == null || roomCubit.isClosed) return null;
  return () => unawaited(showBeaconRoomPollSheet(context, cubit: roomCubit));
}

/// Room-level "Update plan" — only for members allowed to edit the plan
/// (author / steward / admitted), matching the pinned-now strip's edit gate.
VoidCallback? beaconViewRoomUpdatePlanAction({
  required BuildContext context,
  required RoomCubit? roomCubit,
  required bool inRoomSurface,
}) {
  if (!inRoomSurface || roomCubit == null || roomCubit.isClosed) return null;
  final myUserId = roomCubit.state.myUserId;
  if (myUserId.isEmpty) return null;
  var canEdit = false;
  for (final p in roomCubit.state.participants) {
    if (p.userId == myUserId) {
      canEdit = p.role == BeaconParticipantRoleBits.author ||
          p.role == BeaconParticipantRoleBits.steward ||
          p.roomAccess == RoomAccessBits.admitted;
      break;
    }
  }
  if (!canEdit) return null;
  final l10n = L10n.of(context)!;
  return () =>
      unawaited(showBeaconRoomUpdatePlanSheet(context, roomCubit, l10n));
}

Widget beaconViewAppBarOverflow({
  required BuildContext context,
  required BeaconViewState state,
  required BeaconViewCubit cubit,
  required ScreenCubit screenCubit,
  required L10n l10n,
  required Future<void> Function() onAuthorManageStatus,
  required bool inRoomSurface,
  required VoidCallback onItemsTabRefresh,
  RoomCubit? roomCubit,
}) {
  final b = state.beacon;
  final beaconId = b.id;
  final hideOverflowForward = forwardInPrimaryCta(state);
  final hideOfferHelpWithdraw = hideOfferHelpWithdrawFromOverflow(state);
  final showBeaconManagementOverflow = !inRoomSurface;
  final onCreatePromise = beaconViewRoomCreatePromiseAction(
    context: context,
    state: state,
    beaconId: beaconId,
    onSaved: onItemsTabRefresh,
    inRoomSurface: inRoomSurface,
  );
  final onCreatePoll = beaconViewRoomCreatePollAction(
    context: context,
    roomCubit: roomCubit,
    inRoomSurface: inRoomSurface,
  );
  final onUpdatePlan = beaconViewRoomUpdatePlanAction(
    context: context,
    roomCubit: roomCubit,
    inRoomSurface: inRoomSurface,
  );

  if (state.isBeaconMine) {
    final hideHudForward = forwardShownInAuthorHud(state);
    return BeaconOverflowMenu(
      beacon: b,
      onShare: showBeaconManagementOverflow && b.allowsForward
          ? () => unawaited(showBeaconShareSheet(context, beacon: b))
          : null,
      onRequestStatus: showBeaconManagementOverflow &&
              beaconViewShowsRequestStatusOverflow(state)
          ? () async {
              if (!context.mounted) return;
              await cubit.refreshReviewWindowInfo();
              if (!context.mounted) return;
              await onAuthorManageStatus();
            }
          : null,
      onEdit: showBeaconManagementOverflow && beaconAllowsEdit(b)
          ? () => unawaited(
              context.router.push(BeaconCreateRoute(editId: beaconId)),
            )
          : null,
      onCreateFrom: showBeaconManagementOverflow && beaconAllowsLineageOverflow(b)
          ? () async {
              await runBeaconCreateFromAction(
                context,
                fork: () => cubit.forkFromThis(),
              );
            }
          : null,
      onCreatePromise: onCreatePromise,
      onCreatePoll: onCreatePoll,
      onUpdatePlan: onUpdatePlan,
      onForward: showBeaconManagementOverflow &&
              b.allowsForward &&
              !hideHudForward
          ? () => unawaited(
              beaconViewOpenForwardThenMaybeNudgeOfferHelp(context, cubit, l10n),
            )
          : null,
      onForwardsGraph: showBeaconManagementOverflow
          ? () => screenCubit.showForwardsGraphFor(beaconId)
          : null,
      onDraftReview: state.showDraftEvaluationCta
          ? () => unawaited(
              context.router.push(
                ReviewContributionsRoute(id: beaconId, draft: true),
              ),
            )
          : null,
      onDelete: showBeaconManagementOverflow
          ? () async {
              if (!context.mounted) return;
              if (await BeaconDeleteDialog.show(
                    context,
                    status: b.status,
                    hasEverHadCommitter: beaconDeleteBlockedByCommitters(b),
                  ) ??
                  false) {
                if (!context.mounted) return;
                await cubit.delete(beaconId);
              }
            }
          : null,
    );
  }

  return BeaconOverflowMenu(
    beacon: b,
    onRequestStatus: showBeaconManagementOverflow &&
            state.isAuthorOrSteward &&
            beaconViewShowsRequestStatusOverflow(state)
        ? () async {
            if (!context.mounted) return;
            await cubit.refreshReviewWindowInfo();
            if (!context.mounted) return;
            await onAuthorManageStatus();
          }
        : null,
    onCreatePromise: onCreatePromise,
    onCreatePoll: onCreatePoll,
    onUpdatePlan: onUpdatePlan,
    onOfferHelp:
        !hideOfferHelpWithdraw &&
            !state.isHelpOffered &&
            b.allowsNewHelpOfferAsNonAuthor
        ? () async {
            await beaconViewRunInitialHelpOfferDialog(context, cubit, l10n);
          }
        : null,
    onWithdraw:
        !hideOfferHelpWithdraw &&
            state.isHelpOffered &&
            b.allowsWithdrawWhileHelpOffered
        ? () async {
            if (!context.mounted) return;
            final outcome = await HelpOfferMessageDialog.show(
              context,
              title: l10n.dialogWithdrawHelpOfferTitle,
              hintText: l10n.hintWithdrawReason,
              allowEmptyMessage: true,
              requireWithdrawReason: true,
            );
            if (outcome?.withdrawReasonWire != null && context.mounted) {
              await cubit.withdraw(
                message: outcome!.message,
                withdrawReason: outcome.withdrawReasonWire!,
              );
            }
          }
        : null,
    onForward: showBeaconManagementOverflow && !hideOverflowForward
        ? () => unawaited(
            beaconViewOpenForwardThenMaybeNudgeOfferHelp(context, cubit, l10n),
          )
        : null,
    onForwardsGraph: showBeaconManagementOverflow
        ? () => screenCubit.showForwardsGraphFor(beaconId)
        : null,
    onCreateFrom: showBeaconManagementOverflow && beaconAllowsLineageOverflow(b)
        ? () async {
            await runBeaconCreateFromAction(
              context,
              fork: () => cubit.forkFromThis(),
            );
          }
        : null,
    onDraftReview: state.showDraftEvaluationCta
        ? () => unawaited(
            context.router.push(
              ReviewContributionsRoute(id: beaconId, draft: true),
            ),
          )
        : null,
    onWatch: !state.isHelpOffered && state.inboxStatus == InboxItemStatus.needsMe
        ? () => unawaited(cubit.moveToWatching())
        : null,
    onStopWatching:
        !state.isHelpOffered && state.inboxStatus == InboxItemStatus.watching
        ? () => unawaited(cubit.stopWatching())
        : null,
    onCantHelp:
        state.inboxStatus == InboxItemStatus.needsMe ||
            state.inboxStatus == InboxItemStatus.watching
        ? () async {
            if (!context.mounted) return;
            final msg = await showRejectionDialog(context);
            if (context.mounted && msg != null) {
              await cubit.rejectInbox(message: msg);
            }
          }
        : null,
    onMoveToInbox: state.inboxStatus == InboxItemStatus.rejected
        ? () => unawaited(cubit.unrejectInbox())
        : null,
    onComplaint: () => screenCubit.showComplaint(beaconId),
  );
}
