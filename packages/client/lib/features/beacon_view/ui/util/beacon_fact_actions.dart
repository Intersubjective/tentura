import 'package:flutter/material.dart';

import 'package:tentura/domain/entity/beacon_fact_card.dart';
import 'package:tentura/features/beacon_room/ui/bloc/room_cubit.dart';
import 'package:tentura/features/beacon_room/ui/widget/fact_actions_sheet.dart';

/// Opens manage/edit/remove actions for a pinned fact card.
Future<void> showBeaconFactActions(
  BuildContext context, {
  required String beaconId,
  required BeaconFactCard fact,
}) async {
  final cubit = RoomCubit(beaconId: beaconId);
  try {
    await showFactActionsSheet(
      context,
      cubit: cubit,
      fact: fact,
    );
  } finally {
    await cubit.close();
  }
}
