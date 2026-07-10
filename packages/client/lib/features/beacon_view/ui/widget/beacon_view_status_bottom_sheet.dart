import 'dart:async';
import 'package:tentura_root/domain/entity/beacon_status.dart';

import 'package:flutter/material.dart';

import 'package:tentura/consts.dart';
import 'package:tentura/design_system/tentura_design_system.dart';
import 'package:tentura/domain/entity/beacon.dart';
import 'package:tentura/domain/entity/coordination_item.dart';
import 'package:tentura/features/beacon/ui/sheet/beacon_close_confirm_sheet.dart';
import 'package:tentura/features/beacon_create/ui/dialog/beacon_publish_dialog.dart';
import 'package:tentura/features/beacon_view/domain/beacon_status_menu.dart';
import 'package:tentura/features/beacon_view/domain/beacon_status_menu_presenter.dart';
import 'package:tentura/features/beacon_view/ui/bloc/beacon_view_cubit.dart';
import 'package:tentura/features/beacon_view/ui/util/beacon_closure_readiness.dart';
import 'package:tentura/ui/l10n/l10n.dart';

Future<void> showBeaconViewUpdateStatusSheet(
  BuildContext context,
  BeaconViewState state,
  BeaconViewCubit beaconViewCubit, {
  VoidCallback? onOpenPeopleTab,
  void Function([CoordinationItem? focusItem])? onEnterRoomSurface,
}) async {
  final lifecycle = state.beacon.status;
  if (lifecycle == BeaconStatus.deleted) return;

  final l10n = L10n.of(context)!;
  final review = state.reviewWindowInfo;
  final menuInput = BeaconStatusMenuInput(
    beacon: state.beacon,
    closureReadiness: state.closureReadiness,
    hasCommitters: beaconStateHasCommitters(state),
    canManageLifecycle: state.isBeaconMine,
    canSetCoordination: state.isAuthorOrSteward,
    allowForceCloseWhenBlocked: kBeaconAllowForceCloseWhenBlocked,
    reviewWindow: review == null
        ? null
        : ReviewWindowMenuSnapshot(
            reviewedCount: review.reviewedCount,
            totalCount: review.totalCount,
            windowComplete: review.windowComplete,
            extensionsUsed: review.extensionsUsed,
            canCloseNow: review.canCloseNow,
          ),
  );
  final rows = buildBeaconStatusMenuRows(menuInput);

  await showTenturaAdaptiveSheet<void>(
    context: context,
    showDragHandle: true,
    isScrollControlled: true,
    builder: (ctx) {
      final tt = ctx.tt;
      final scheme = Theme.of(ctx).colorScheme;
      return SafeArea(
        child: BlocBuilder<BeaconViewCubit, BeaconViewState>(
          bloc: beaconViewCubit,
          builder: (context, liveState) {
            final isLoading = liveState.isLoading;
            return Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Padding(
                  padding: EdgeInsets.fromLTRB(
                    tt.screenHPadding,
                    tt.tightGap * 2,
                    tt.screenHPadding,
                    tt.tightGap,
                  ),
                  child: Text(
                    l10n.beaconStatusSheetTitle,
                    style: Theme.of(ctx).textTheme.titleSmall,
                  ),
                ),
                for (final row in rows)
                  BeaconStatusMenuRowTile(
                    row: row,
                    beacon: liveState.beacon,
                    isLoading: isLoading,
                    onTap: row.isEnabled && !isLoading
                        ? () => unawaited(
                            _dispatchStatusMenuAction(
                              ctx,
                              action: row.action,
                              state: liveState,
                              cubit: beaconViewCubit,
                              l10n: l10n,
                              onOpenPeopleTab: onOpenPeopleTab,
                              onEnterRoomSurface: onEnterRoomSurface,
                            ),
                          )
                        : null,
                    onSecondaryTap:
                        row.isSecondaryEnabled &&
                            row.secondaryAction !=
                                BeaconStatusMenuAction.none &&
                            !isLoading
                        ? () => unawaited(
                            _dispatchStatusMenuAction(
                              ctx,
                              action: row.secondaryAction,
                              state: liveState,
                              cubit: beaconViewCubit,
                              l10n: l10n,
                              onOpenPeopleTab: onOpenPeopleTab,
                              onEnterRoomSurface: onEnterRoomSurface,
                            ),
                          )
                        : null,
                  ),
                if (isLoading)
                  Padding(
                    padding: EdgeInsets.all(tt.rowGap),
                    child: LinearProgressIndicator(
                      color: scheme.primary,
                      backgroundColor: scheme.surfaceContainerHighest,
                    ),
                  ),
                SizedBox(height: tt.rowGap),
              ],
            );
          },
        ),
      );
    },
  );
}

class BeaconStatusMenuRowTile extends StatelessWidget {
  const BeaconStatusMenuRowTile({
    required this.row,
    required this.beacon,
    required this.isLoading,
    required this.onTap,
    this.onSecondaryTap,
  });

  final BeaconStatusMenuRow row;
  final Beacon beacon;
  final bool isLoading;
  final VoidCallback? onTap;
  final VoidCallback? onSecondaryTap;

  @override
  Widget build(BuildContext context) {
    final l10n = L10n.of(context)!;
    final tt = context.tt;
    final scheme = Theme.of(context).colorScheme;
    final title = row.id == BeaconStatusMenuRowId.open
        ? beaconStatusMenuOpenRowLabel(l10n, beacon)
        : beaconStatusMenuRowLabel(l10n, row.id);
    final hint = beaconStatusMenuDisabledReasonLabel(l10n, row.disabledReason);
    final subtitle = hint.isNotEmpty ? hint : null;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        ListTile(
          enabled: row.isEnabled && !isLoading,
          leading: row.isSelected
              ? Icon(Icons.check, size: tt.iconSize, color: scheme.primary)
              : SizedBox(width: tt.iconSize),
          title: Text(
            title,
            style: row.isSelected
                ? TenturaText.body(scheme.primary).copyWith(
                    fontWeight: FontWeight.w600,
                  )
                : null,
          ),
          subtitle: subtitle != null
              ? Text(
                  subtitle,
                  style: TenturaText.status(scheme.onSurfaceVariant),
                )
              : null,
          onTap: onTap == null
              ? null
              : () {
                  Navigator.of(context).pop();
                  onTap!();
                },
        ),
        if (onSecondaryTap != null)
          Align(
            alignment: Alignment.centerLeft,
            child: Padding(
              padding: EdgeInsets.only(
                left: tt.screenHPadding + tt.iconSize + tt.iconTextGap,
                bottom: tt.tightGap,
              ),
              child: TextButton(
                onPressed: () {
                  Navigator.of(context).pop();
                  onSecondaryTap!();
                },
                child: Text(l10n.beaconReviewExtendAction),
              ),
            ),
          ),
      ],
    );
  }
}

Future<void> _dispatchStatusMenuAction(
  BuildContext context, {
  required BeaconStatusMenuAction action,
  required BeaconViewState state,
  required BeaconViewCubit cubit,
  required L10n l10n,
  VoidCallback? onOpenPeopleTab,
  void Function([CoordinationItem? focusItem])? onEnterRoomSurface,
}) async {
  switch (action) {
    case BeaconStatusMenuAction.none:
      return;
    case BeaconStatusMenuAction.publish:
      if (!context.mounted) return;
      final ok = await BeaconPublishDialog.show(context);
      if (ok == true && context.mounted) {
        await cubit.publishBeacon();
      }
    case BeaconStatusMenuAction.setCoordinationNeutral:
      await cubit.setBeaconStatus(
        BeaconStatus.open,
      );
    case BeaconStatusMenuAction.setCoordinationMoreHelp:
      if (state.beacon.status == BeaconStatus.reviewOpen) {
        if (!context.mounted) return;
        final ok = await showAdaptiveDialog<bool>(
          context: context,
          builder: (ctx) => AlertDialog.adaptive(
            title: Text(l10n.beaconNeedsMoreHelpRevertTitle),
            content: Text(l10n.beaconNeedsMoreHelpRevertBody),
            actions: [
              TextButton(
                onPressed: () => Navigator.of(ctx).pop(true),
                child: Text(l10n.beaconNeedsMoreHelpRevertConfirm),
              ),
              TextButton(
                onPressed: () => Navigator.of(ctx).pop(false),
                child: Text(l10n.buttonCancel),
              ),
            ],
          ),
        );
        if (ok != true) return;
      }
      await cubit.setBeaconStatus(
        BeaconStatus.needsMoreHelp,
      );
    case BeaconStatusMenuAction.setCoordinationEnoughHelp:
      await cubit.setBeaconStatus(
        BeaconStatus.enoughHelp,
      );
    case BeaconStatusMenuAction.startWrappingUp:
      if (!context.mounted) return;
      await _runCloseFlow(
        context,
        cubit: cubit,
        expectedRequiresReviewWindow: true,
        onOpenPeopleTab: onOpenPeopleTab,
        onEnterRoomSurface: onEnterRoomSurface,
      );
    case BeaconStatusMenuAction.closeDirect:
      if (!context.mounted) return;
      await _runCloseFlow(
        context,
        cubit: cubit,
        expectedRequiresReviewWindow: false,
        onOpenPeopleTab: onOpenPeopleTab,
        onEnterRoomSurface: onEnterRoomSurface,
      );
    case BeaconStatusMenuAction.closeNow:
      await cubit.closeBeaconNow();
    case BeaconStatusMenuAction.extendReview:
      await cubit.extendReview();
    case BeaconStatusMenuAction.reopen:
      if (!context.mounted) return;
      final ok = await showAdaptiveDialog<bool>(
        context: context,
        builder: (ctx) => AlertDialog.adaptive(
          title: Text(l10n.beaconReviewReopenTitle),
          content: Text(l10n.beaconReviewReopenBody),
          actions: [
            TextButton(
              onPressed: () => Navigator.of(ctx).pop(true),
              child: Text(l10n.beaconReviewReopenConfirm),
            ),
            TextButton(
              onPressed: () => Navigator.of(ctx).pop(false),
              child: Text(l10n.buttonCancel),
            ),
          ],
        ),
      );
      if (ok == true) {
        await cubit.reopenBeacon();
      }
    case BeaconStatusMenuAction.cancel:
      if (!context.mounted) return;
      final ok = await showAdaptiveDialog<bool>(
        context: context,
        builder: (ctx) => AlertDialog.adaptive(
          title: Text(l10n.beaconStatusCancelTitle),
          content: Text(l10n.beaconStatusCancelBody),
          actions: [
            TextButton(
              onPressed: () => Navigator.of(ctx).pop(false),
              child: Text(l10n.buttonCancel),
            ),
            TextButton(
              onPressed: () => Navigator.of(ctx).pop(true),
              style: TextButton.styleFrom(
                foregroundColor: Theme.of(ctx).colorScheme.error,
              ),
              child: Text(l10n.beaconStatusCancelConfirm),
            ),
          ],
        ),
      );
      if (ok == true) {
        await cubit.cancelBeacon();
      }
  }
}

Future<void> _runCloseFlow(
  BuildContext context, {
  required BeaconViewCubit cubit,
  required bool expectedRequiresReviewWindow,
  VoidCallback? onOpenPeopleTab,
  void Function([CoordinationItem? focusItem])? onEnterRoomSurface,
}) async {
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
        onOpenPeople: onOpenPeopleTab ?? () {},
        onResolveRoom: cubit.state.canNavigateBeaconRoom
            ? () => onEnterRoomSurface?.call()
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
    onOpenPeople: onOpenPeopleTab ?? () {},
    onResolveRoom: cubit.state.canNavigateBeaconRoom
        ? () => onEnterRoomSurface?.call()
        : null,
  );
}
