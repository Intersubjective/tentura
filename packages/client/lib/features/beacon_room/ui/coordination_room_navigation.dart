import 'package:flutter/material.dart';

import 'package:tentura/app/router/root_router.dart';
import 'package:tentura/domain/entity/coordination_item.dart';
import 'package:tentura/features/beacon_room/ui/bloc/room_cubit.dart';

/// Plan coordination items use the main beacon room, not per-item threads.
bool planItemSuppressesItemDiscussion(CoordinationItem item) =>
    item.kind == CoordinationItemKind.plan;

/// Opens an item thread from the beacon room, or scrolls to a plan anchor.
Future<void> openCoordinationItemFromRoom(
  BuildContext context, {
  required CoordinationItem item,
  RoomCubit? roomCubit,
}) async {
  if (planItemSuppressesItemDiscussion(item)) {
    roomCubit?.prepareThreadScroll(
      messageId: item.threadAnchorMessageId,
      coordinationItemId: item.id,
    );
    return;
  }

  final updated = await context.router.push<CoordinationItem?>(
    ItemDiscussionRoute(
      beaconId: item.beaconId,
      itemId: item.id,
      item: item,
    ),
  );

  if (!context.mounted) return;
  final cubit = roomCubit;
  if (cubit == null || cubit.isClosed) return;

  if (updated != null) {
    cubit.applyCoordinationItemSnapshot(updated);
  }
  await cubit.reloadMessages(silent: true);
}
