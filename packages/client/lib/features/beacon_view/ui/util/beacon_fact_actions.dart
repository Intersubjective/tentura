import 'package:flutter/material.dart';

import 'package:tentura/domain/entity/beacon_fact_card.dart';
import 'package:tentura/features/beacon_threads/ui/widget/fact_actions_sheet.dart';
import 'package:tentura/features/beacon_view/ui/bloc/beacon_view_cubit.dart';

/// Opens manage/edit/remove actions using the live [BeaconViewCubit].
///
/// [pageContext] must belong to the page that owns the cubit (not the facts
/// sheet builder), so confirm/edit still work if that sheet is dismissed.
Future<void> showBeaconFactActions(
  BuildContext pageContext, {
  required BeaconViewCubit cubit,
  required BeaconFactCard fact,
}) {
  return showFactActionsHostSheet(
    pageContext,
    fact: fact,
    onCorrect: ({required factCardId, required newText}) =>
        cubit.correctFact(factCardId: factCardId, newText: newText),
    onRemove: ({required factCardId}) => cubit.removeFact(factCardId: factCardId),
    onSetVisibility: ({required factCardId, required visibility}) =>
        cubit.setFactVisibility(
          factCardId: factCardId,
          visibility: visibility,
        ),
  );
}
