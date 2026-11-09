import 'dart:async';

import 'package:auto_route/auto_route.dart';
import 'package:flutter/widgets.dart';
import 'package:get_it/get_it.dart';

import 'package:tentura/design_system/components/tentura_confirm_dialog.dart';
import 'package:tentura/design_system/components/tentura_sheet_dismiss_guard.dart';
import 'package:tentura/features/beacon_threads/data/service/beacon_room_composer_draft_store.dart';
import 'package:tentura/features/beacon_threads/ui/bloc/thread_host_cubit.dart';
import 'package:tentura/ui/l10n/l10n.dart';
import 'package:tentura/ui/navigation/app_navigator.dart';
import 'package:tentura/ui/navigation/home_tab.dart';

/// In-app back/close when the room composer may hold an unsent reply (#1105).
///
/// Uses the same discard copy as [TenturaSheetDismissGuard] and clears the
/// session draft store plus unsaved-leave bookkeeping on the mounted room
/// cubit when the user confirms.
Future<bool> confirmDiscardBeaconRoomComposerIfNeeded(
  BuildContext context,
  String beaconId,
) async {
  final draft = readBeaconRoomComposerDraft(beaconId)?.trim();
  if (draft == null || draft.isEmpty) return true;
  final l10n = L10n.of(context)!;
  final copy = TenturaSheetDiscardCopy.composer(l10n);
  final confirmed = await TenturaConfirmDialog.show(
    context: context,
    title: copy.title,
    content: copy.body,
    confirmLabel: copy.confirmLabel,
    cancelLabel: copy.cancelLabel,
    emphasizeCancel: true,
  );
  return confirmed ?? false;
}

void abandonBeaconRoomComposerDraft(BuildContext context, String beaconId) {
  clearBeaconRoomComposerDraft(beaconId);
  if (!context.mounted) return;
  try {
    context.read<ThreadHostCubit>().roomCubit?.composerTextChanged('');
  } on Object {
    // No room mounted (e.g. loading shell).
  }
}

/// Leaves a Post detail, targeting the Posts (Conversations) home tab even when
/// a cold `/beacon/view/<postId>` reload left Requests underneath.
Future<void> leavePostDetailScreen(
  BuildContext context, {
  required String beaconId,
}) async {
  if (!await confirmDiscardBeaconRoomComposerIfNeeded(context, beaconId)) {
    return;
  }
  if (!context.mounted) return;
  abandonBeaconRoomComposerDraft(context, beaconId);

  final navigator = GetIt.I<AppNavigator>();
  final root = context.router.root;
  const ownerTab = HomeTab.conversations;
  final ownerIndex = HomeTabSpec.forTab(ownerTab).index;

  if (root.canPop()) {
    await root.maybePop();
  } else {
    await navigator.resetToHome(tab: ownerTab);
    return;
  }
  if (!context.mounted) return;
  if (navigator.activeHomeTabIndex != ownerIndex) {
    await navigator.openHomeTab(ownerTab);
  }
}

/// Leaves a Request detail opened on the root browse stack.
Future<void> leaveRequestDetailScreen(
  BuildContext context, {
  required String beaconId,
}) async {
  if (!await confirmDiscardBeaconRoomComposerIfNeeded(context, beaconId)) {
    return;
  }
  if (!context.mounted) return;
  abandonBeaconRoomComposerDraft(context, beaconId);

  final navigator = GetIt.I<AppNavigator>();
  final root = context.router.root;
  const ownerTab = HomeTab.work;
  final ownerIndex = HomeTabSpec.forTab(ownerTab).index;

  if (root.canPop()) {
    await root.maybePop();
  } else {
    await navigator.resetToHome(tab: ownerTab);
    return;
  }
  if (!context.mounted) return;
  if (navigator.activeHomeTabIndex != ownerIndex) {
    await navigator.openHomeTab(ownerTab);
  }
}
