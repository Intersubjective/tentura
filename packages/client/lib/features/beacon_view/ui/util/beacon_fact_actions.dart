import 'dart:async';

import 'package:flutter/material.dart';

import 'package:tentura/domain/entity/beacon_fact_card.dart';
import 'package:tentura/features/beacon_threads/ui/widget/fact_actions_sheet.dart';
import 'package:tentura/features/beacon_threads/ui/widget/fact_history_sheet.dart';
import 'package:tentura/features/beacon_view/ui/bloc/beacon_view_cubit.dart';
import 'package:tentura/features/beacon_view/ui/util/beacon_room_navigation_scope.dart';

/// Opens manage/edit/remove actions using the live [BeaconViewCubit].
///
/// [pageContext] must belong to the page that owns the cubit (not the facts
/// sheet builder), so confirm/edit still work if that sheet is dismissed.
Future<void> showBeaconFactActions(
  BuildContext pageContext, {
  required BeaconViewCubit cubit,
  required BeaconFactCard fact,
}) {
  final navigation = BeaconRoomNavigationScope.maybeOf(pageContext);
  return showFactActionsHostSheet(
    pageContext,
    fact: fact,
    canMutate: cubit.state.beacon.status.allowsDiscussionWrites,
    onCorrect: ({required factCardId, required newText, String? attachmentsJson}) =>
        cubit.correctFact(
          factCardId: factCardId,
          newText: newText,
          attachmentsJson: attachmentsJson,
        ),
    onRemove: ({required factCardId}) => cubit.removeFact(factCardId: factCardId),
    onSetVisibility: ({required factCardId, required visibility}) =>
        cubit.setFactVisibility(
          factCardId: factCardId,
          visibility: visibility,
        ),
    // Opens General at the fact's message (#373). The Facts sheet is closed
    // first so the chat is in view.
    onJumpToSource: navigation == null
        ? null
        : (messageId) {
            Navigator.of(pageContext).popUntil((route) => route is! PopupRoute);
            unawaited(navigation.openGeneralAnchor(messageId: messageId));
          },
    onEditHistory: (f) => unawaited(
      showFactHistorySheet(
        pageContext,
        beaconId: cubit.state.beacon.id,
        factCardId: f.id,
        baseRevisionSeq: f.revisionSeq,
        canMutate: cubit.state.beacon.status.allowsDiscussionWrites,
      ),
    ),
  );
}
