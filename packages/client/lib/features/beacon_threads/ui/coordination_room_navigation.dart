import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';

import 'package:tentura/app/router/root_router.dart';
import 'package:tentura/design_system/tentura_design_system.dart';
import 'package:tentura/domain/entity/coordination_item.dart';
import 'package:tentura/features/beacon_threads/domain/entity/request_thread.dart';
import 'package:tentura/features/beacon_threads/ui/bloc/room_cubit.dart';
import 'package:tentura/features/beacon_threads/ui/bloc/thread_host_cubit.dart';
import 'package:tentura/features/beacon_threads/ui/bloc/threads_cubit.dart';

/// Plan coordination items use the main beacon room, not per-item threads.
bool planItemSuppressesItemDiscussion(CoordinationItem item) =>
    item.kind == CoordinationItemKind.plan;

/// Opens or focuses an item thread from within a room message surface.
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

  final expanded = context.windowClass == WindowClass.expanded;
  if (expanded) {
    try {
      final host = context.read<ThreadHostCubit>();
      final threads = context.read<ThreadsCubit>().state.threads;
      RequestThread? thread;
      for (final t in threads) {
        if (t.threadId == item.id) {
          thread = t;
          break;
        }
      }
      if (thread != null) {
        await host.select(thread);
        final cubit = host.roomCubit;
        if (cubit != null && !cubit.isClosed) {
          await cubit.reloadMessages(silent: true);
        }
        return;
      }
    } on Object {
      // No thread host scope — fall through to routed detail.
    }
  }

  final route = ThreadDetailRoute(threadId: item.id);
  final router = context.router;
  if (router.currentChild?.name == ThreadDetailRoute.name) {
    await router.replace(route);
  } else {
    await router.push(route);
  }

  if (!context.mounted) return;
  final cubit = roomCubit ?? context.read<ThreadHostCubit>().roomCubit;
  if (cubit == null || cubit.isClosed) return;
  await cubit.reloadMessages(silent: true);
}
