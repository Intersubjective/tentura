import 'dart:async';

import 'package:flutter/material.dart';
import 'package:tentura_root/domain/entity/beacon_status.dart';

import 'package:tentura/app/router/root_router.dart';
import 'package:tentura/domain/entity/coordination_item.dart';
import 'package:tentura/features/beacon/ui/dialog/beacon_delete_dialog.dart';
import 'package:tentura/features/beacon/ui/util/beacon_delete_ui.dart';
import 'package:tentura/features/beacon/ui/util/beacon_lifecycle_ui.dart';
import 'package:tentura/features/beacon/ui/util/beacon_lineage_overflow_actions.dart';
import 'package:tentura/features/beacon/ui/widget/beacon_overflow_menu.dart';
import 'package:tentura/features/beacon_threads/ui/bloc/room_cubit.dart';
import 'package:tentura/features/beacon_plan/ui/bloc/plan_cubit.dart';
import 'package:tentura/features/beacon_plan/ui/widget/beacon_plan_page.dart';
import 'package:tentura/features/beacon_threads/ui/widget/beacon_room_body.dart'
    show showBeaconRoomUpdatePlanSheet;
import 'package:tentura/features/beacon_view/ui/presenter/beacon_hud_author_action.dart';
import 'package:tentura/features/closure/domain/entity/closure_member.dart';
import 'package:tentura/features/closure/ui/screen/closure_review_page.dart';
import 'package:tentura/features/beacon_view/ui/bloc/beacon_view_cubit.dart';
import 'package:tentura/features/beacon_view/ui/dialog/help_offer_message_dialog.dart';
import 'package:tentura/features/beacon_view/ui/dialog/decline_remaining_offers_flow.dart';
import 'package:tentura/features/beacon_view/ui/util/beacon_closure_readiness.dart';
import 'package:tentura/features/beacon_view/ui/util/help_offer_types_wire.dart';
import 'package:tentura/features/beacon_view/ui/widget/beacon_view_forward_overflow.dart';
import 'package:tentura/features/inbox/domain/enum.dart';
import 'package:tentura/features/inbox/ui/widget/rejection_dialog.dart';
import 'package:tentura/ui/bloc/screen_cubit.dart';
import 'package:tentura/design_system/tentura_design_system.dart';
import 'package:tentura/ui/l10n/l10n.dart';
import 'package:tentura/ui/presenter/beacon_phase_presenter.dart';

import 'beacon_hud_author_confirm_sheets.dart';
import 'beacon_view_constants.dart';
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
      cubit.state.beacon.status == BeaconStatus.enoughHelp;
  final outcome = await HelpOfferMessageDialog.show(
    context,
    title: useOfferHelpAnyway
        ? l10n.dialogOfferHelpAnywayTitle
        : l10n.dialogOfferHelpTitle,
    hintText: l10n.hintOfferHelpMessage,
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

BeaconPhaseStatusPresentation beaconViewRoomAppBarPhaseStatus(
  L10n l10n, {
  required int memberCount,
}) {
  if (memberCount <= 0) {
    return const BeaconPhaseStatusPresentation(
      slot1: '',
      slot1Tone: TenturaTone.neutral,
    );
  }
  return BeaconPhaseStatusPresentation(
    slot1: l10n.beaconRoomMemberCount(memberCount),
    slot1Tone: TenturaTone.neutral,
  );
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
  required void Function() onOpenGeneralThread,
}) async {
  if (!context.mounted) return;
  if (!closeReviewWindowExpectationKnown(cubit.state)) return;
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
            ? onOpenGeneralThread
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
        ? onOpenGeneralThread
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
  required void Function() onOpenGeneralThread,
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
      if (await cubit.setBeaconStatus(BeaconStatus.enoughHelp) &&
          context.mounted) {
        await beaconViewOfferDeclineRemainingOffers(context, cubit);
      }
    case BeaconHudAuthorAction.wrapUpForReview:
      await beaconViewRunAuthorCloseSheet(
        context: context,
        cubit: cubit,
        l10n: l10n,
        onOpenPeopleTab: onOpenPeopleTab,
        onOpenGeneralThread: onOpenGeneralThread,
      );
    case BeaconHudAuthorAction.sumUp:
      await beaconViewOpenClosureReview(context.router, cubit);
    case BeaconHudAuthorAction.closeNow:
      final confirmed = await showBeaconCloseNowConfirmSheet(
        context: context,
        canCloseNow: cubit.state.closureState?.canCloseNow == true,
      );
      if (!context.mounted) return;
      if (!confirmed) return;
      if (deriveBeaconHudAuthorAction(cubit.state) !=
          BeaconHudAuthorAction.closeNow) {
        return;
      }
      await cubit.closeBeaconNow();
  }
}

/// Opens the wrap-up review for the viewer's closure role (author: «Close & sum up»;
/// member: support colleagues), then reloads the Request: Close now or
/// Return to work on that page change its lifecycle.
Future<void> beaconViewOpenClosureReview(
  StackRouter router,
  BeaconViewCubit cubit,
) async {
  final state = cubit.state;
  final closure = state.closureState;
  if (closure == null) return;
  final author = state.beacon.author;
  await openClosureReview(
    router,
    beaconId: state.beacon.id,
    role: closure.role,
    viewerId: state.myProfile.id,
    author: ClosureMember(
      id: author.id,
      displayName: author.shownName,
      avatarId: author.hasAvatar ? author.image!.id : null,
    ),
  );
  if (cubit.isClosed) return;
  await cubit.refreshAfterClosureReview();
}

bool beaconViewShowsRequestStatusOverflow(BeaconViewState state) {
  if (!state.isAuthorOrSteward) return false;
  final lifecycle = state.beacon.status;
  return lifecycle == BeaconStatus.draft ||
      lifecycle.isOpenFamily ||
      lifecycle == BeaconStatus.reviewOpen;
}

VoidCallback? beaconViewRoomCreatePromiseAction({
  required BuildContext context,
  required BeaconViewState state,
  required BeaconViewCubit beaconViewCubit,
  required String beaconId,
  required VoidCallback onSaved,
  required bool inRoomSurface,
}) {
  return null;
}

/// Room-level "Update plan" — only for members allowed to edit the plan
/// (author / steward / admitted), matching the pinned-now strip's edit gate.
VoidCallback? beaconViewRoomUpdatePlanAction({
  required BuildContext context,
  required RoomCubit? roomCubit,
  required bool inRoomSurface,
}) {
  if (!inRoomSurface || roomCubit == null || roomCubit.isClosed) return null;
  if (!roomCubit.state.canUpdatePlan) return null;
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
  required VoidCallback onActivityLog,
  required bool inRoomSurface,
  required VoidCallback onItemsTabRefresh,
  RoomCubit? roomCubit,

  /// Author only: switch to the showcase preview ("How others see it").
  VoidCallback? onPreviewAsOthers,

  /// Expanded split (#168): a single header ⋮ serves both the request pane
  /// and the discussion pane, so it carries both action sets.
  bool combineSplitPanes = false,
}) {
  Widget menu({VoidCallback? onAddPlan}) => _beaconViewAppBarOverflowMenu(
    context: context,
    state: state,
    cubit: cubit,
    screenCubit: screenCubit,
    l10n: l10n,
    onAuthorManageStatus: onAuthorManageStatus,
    onActivityLog: onActivityLog,
    inRoomSurface: inRoomSurface,
    onItemsTabRefresh: onItemsTabRefresh,
    roomCubit: roomCubit,
    onPreviewAsOthers: onPreviewAsOthers,
    combineSplitPanes: combineSplitPanes,
    onAddPlan: onAddPlan,
  );

  // #546: a Request without a plan step has no Plan tab; an editor of the
  // plan (author / steward) starts one here, in the plan editor.
  final planCubit = context.read<PlanCubit?>();
  final pages = BeaconPlanPageScope.maybeOf(context);
  final showsManagement = !inRoomSurface || combineSplitPanes;
  if (planCubit == null || pages == null || !showsManagement) return menu();
  bool canAddPlan(PlanState s) {
    final plan = s.plan;
    return plan != null && plan.editable && !beaconPlanHasSteps(plan);
  }

  return BlocBuilder<PlanCubit, PlanState>(
    bloc: planCubit,
    buildWhen: (p, c) => canAddPlan(p) != canAddPlan(c),
    builder: (context, planState) => menu(
      onAddPlan: canAddPlan(planState)
          ? () => pages.open(BeaconPlanPage.edit)
          : null,
    ),
  );
}

Widget _beaconViewAppBarOverflowMenu({
  required BuildContext context,
  required BeaconViewState state,
  required BeaconViewCubit cubit,
  required ScreenCubit screenCubit,
  required L10n l10n,
  required Future<void> Function() onAuthorManageStatus,
  required VoidCallback onActivityLog,
  required bool inRoomSurface,
  required VoidCallback onItemsTabRefresh,
  required RoomCubit? roomCubit,
  required VoidCallback? onPreviewAsOthers,
  required bool combineSplitPanes,
  required VoidCallback? onAddPlan,
}) {
  final b = state.beacon;
  final beaconId = b.id;
  // The Request's plan (#220), loaded only for a viewer inside it; offers
  // «Скопировать план» on «Создать на основе».
  final planCubit = context.read<PlanCubit?>();
  final hideOfferHelpWithdraw = hideOfferHelpWithdrawFromOverflow(state);
  final showBeaconManagementOverflow = !inRoomSurface || combineSplitPanes;
  final showRoomActions = inRoomSurface || combineSplitPanes;
  final onCreatePromise = beaconViewRoomCreatePromiseAction(
    context: context,
    state: state,
    beaconViewCubit: cubit,
    beaconId: beaconId,
    onSaved: onItemsTabRefresh,
    inRoomSurface: showRoomActions,
  );
  final onUpdatePlan = beaconViewRoomUpdatePlanAction(
    context: context,
    roomCubit: roomCubit,
    inRoomSurface: showRoomActions,
  );
  // Overflow is only mounted when request content is loaded (see call sites).
  final onForward = beaconViewForwardOverflowAction(
    context: context,
    state: state,
    cubit: cubit,
    l10n: l10n,
    showBeaconManagementOverflow: showBeaconManagementOverflow,
    showBeaconContent: true,
    showInitialLoading: false,
  );

  if (state.isBeaconMine) {
    return BeaconOverflowMenu(
      beacon: b,
      onRequestStatus:
          showBeaconManagementOverflow &&
              beaconViewShowsRequestStatusOverflow(state)
          ? () async {
              if (!context.mounted) return;
              await cubit.refreshClosureState();
              if (!context.mounted) return;
              await onAuthorManageStatus();
            }
          : null,
      onActivityLog: onActivityLog,
      onPreviewAsOthers: showBeaconManagementOverflow
          ? onPreviewAsOthers
          : null,
      onEdit: showBeaconManagementOverflow && beaconAllowsEdit(b)
          ? () => unawaited(
              context.router.push(BeaconCreateRoute(editId: beaconId)),
            )
          : null,
      onCreateFrom:
          showBeaconManagementOverflow && beaconAllowsLineageOverflow(b)
          ? () async {
              await runBeaconCreateFromAction(
                context,
                sourceBeaconId: beaconId,
                sourcePlan: planCubit?.state.plan,
              );
            }
          : null,
      onCreatePromise: onCreatePromise,
      onUpdatePlan: onUpdatePlan,
      onAddPlan: onAddPlan,
      onForward: onForward,
      onDelete: showBeaconManagementOverflow
          ? () async {
              if (!context.mounted) return;
              if (await BeaconDeleteDialog.show(
                    context,
                    status: b.status,
                    hasEverHadCommitter: beaconDeleteBlockedByCommitters(
                      b,
                      serverCanDelete: state.displayStatus?.canDelete,
                    ),
                    onArchive: () => archiveBeaconFromDetail(beaconId),
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
    onRequestStatus:
        showBeaconManagementOverflow &&
            state.isAuthorOrSteward &&
            beaconViewShowsRequestStatusOverflow(state)
        ? () async {
            if (!context.mounted) return;
            await cubit.refreshClosureState();
            if (!context.mounted) return;
            await onAuthorManageStatus();
          }
        : null,
    onActivityLog: onActivityLog,
    onCreatePromise: onCreatePromise,
    onUpdatePlan: onUpdatePlan,
    onAddPlan: onAddPlan,
    onForward: onForward,
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
    onCreateFrom: showBeaconManagementOverflow && beaconAllowsLineageOverflow(b)
        ? () async {
            await runBeaconCreateFromAction(
              context,
              sourceBeaconId: b.id,
              sourcePlan: planCubit?.state.plan,
            );
          }
        : null,
    onWatch:
        !state.isHelpOffered && state.inboxStatus == InboxItemStatus.needsMe
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
