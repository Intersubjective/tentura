import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';

import 'package:tentura/domain/entity/coordination_item.dart';
import 'package:tentura/features/beacon_threads/ui/bloc/room_cubit.dart';
import 'package:tentura/features/beacon_threads/ui/bloc/thread_host_cubit.dart';
import 'package:tentura/features/beacon_threads/ui/bloc/thread_host_state.dart';
import 'package:tentura/features/beacon_view/ui/util/beacon_room_navigation_scope.dart';

/// Plan coordination items use the main beacon room, not per-item threads.
bool planItemSuppressesItemDiscussion(CoordinationItem item) =>
    item.kind == CoordinationItemKind.plan;

/// Opens or focuses an item thread from within a room message surface.
Future<void> openCoordinationItemFromRoom(
  BuildContext context, {
  required CoordinationItem item,
  RoomCubit? roomCubit,
}) async {
  final messageId = item.threadAnchorMessageId;
  final coordinationItemId = item.id;

  if (planItemSuppressesItemDiscussion(item)) {
    final cubit = roomCubit ?? _activeRoomCubit(context);
    cubit?.prepareThreadScroll(
      messageId: messageId,
      coordinationItemId: coordinationItemId,
    );
    return;
  }

  final scope = BeaconRoomNavigationScope.maybeOf(context);
  if (scope != null) {
    if (scope.isRoomPresented) {
      await scope.roomLease.awaitReady();
      if (!context.mounted) return;
      _activeRoomCubit(context)?.prepareThreadScroll(
        messageId: messageId,
        coordinationItemId: coordinationItemId,
      );
    } else {
      await scope.openGeneralAnchor(
        messageId: messageId,
        coordinationItemId: coordinationItemId,
      );
    }
    await _reloadRoomMessages(context, roomCubit: roomCubit);
    return;
  }

  await _openAnchorWithoutNavigationScope(
    context,
    messageId: messageId,
    coordinationItemId: coordinationItemId,
    roomCubit: roomCubit,
  );
}

RoomCubit? _activeRoomCubit(BuildContext context) {
  try {
    final cubit = context.read<ThreadHostCubit>().roomCubit;
    if (cubit != null && !cubit.isClosed) return cubit;
  } on Object {
    // No thread host above this context.
  }
  return null;
}

bool _isRoomActiveWithoutScope(ThreadHostState state, RoomCubit? roomCubit) =>
    roomCubit != null &&
    !roomCubit.isClosed &&
    !state.switching &&
    state.openThreadId != null;

Future<void> _reloadRoomMessages(
  BuildContext context, {
  RoomCubit? roomCubit,
}) async {
  if (!context.mounted) return;
  final cubit = roomCubit ?? _activeRoomCubit(context);
  if (cubit == null || cubit.isClosed) return;
  await cubit.reloadMessages(silent: true);
}

/// Legacy pushed thread detail (U10) — no [BeaconRoomNavigationScope].
Future<void> _openAnchorWithoutNavigationScope(
  BuildContext context, {
  String? messageId,
  String? coordinationItemId,
  RoomCubit? roomCubit,
}) async {
  ThreadHostCubit? host;
  try {
    host = context.read<ThreadHostCubit>();
  } on Object {
    return;
  }
  if (host.isClosed) return;

  final activeCubit = roomCubit ?? host.roomCubit;
  if (_isRoomActiveWithoutScope(host.state, activeCubit)) {
    activeCubit!.prepareThreadScroll(
      messageId: messageId,
      coordinationItemId: coordinationItemId,
    );
    await _reloadRoomMessages(context, roomCubit: roomCubit);
  }
}
