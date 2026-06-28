import 'package:logging/logging.dart';
import 'package:get_it/get_it.dart';

import '../../data/repository/notification_center_repository.dart';
import '../../domain/entity/notification_center_item.dart';
import 'notification_center_state.dart';

export 'package:flutter_bloc/flutter_bloc.dart';

export 'notification_center_state.dart';

class NotificationCenterCubit extends Cubit<NotificationCenterState> {
  NotificationCenterCubit({NotificationCenterRepository? repository})
      : _repository = repository ?? GetIt.I<NotificationCenterRepository>(),
        super(const NotificationCenterState());

  final NotificationCenterRepository _repository;

  Future<void> fetch() async {
    emit(state.copyWith(status: const StateIsLoading()));
    try {
      final page = await _repository.fetch();
      emit(
        state.copyWith(
          items: page.items,
          unreadCount: page.unreadCount,
          status: const StateIsSuccess(),
        ),
      );
    } catch (e) {
      GetIt.I<Logger>().warning('NotificationCenter fetch failed', e);
      if (!isClosed) {
        emit(state.copyWith(status: const StateIsSuccess()));
      }
    }
  }

  /// Optimistically marks one item read, then persists.
  Future<void> markRead(String id) async {
    final item = state.items.where((e) => e.id == id).firstOrNull;
    if (item == null || item.isRead) {
      return;
    }
    _applyRead({id});
    try {
      await _repository.markRead([id]);
    } catch (_) {
      // Best-effort: refetch to restore ground truth on failure.
      await fetch();
    }
  }

  Future<void> markAllRead() async {
    if (state.unreadCount == 0 && state.items.every((e) => e.isRead)) {
      return;
    }
    final ids = state.items.where((e) => !e.isRead).map((e) => e.id).toSet();
    _applyRead(ids);
    try {
      await _repository.markAllRead();
    } catch (_) {
      await fetch();
    }
  }

  void _applyRead(Set<String> ids) {
    final now = DateTime.now();
    final next = [
      for (final e in state.items)
        if (ids.contains(e.id) && !e.isRead)
          NotificationCenterItem(
            id: e.id,
            category: e.category,
            kind: e.kind,
            title: e.title,
            body: e.body,
            actionUrl: e.actionUrl,
            createdAt: e.createdAt,
            collapsedCount: e.collapsedCount,
            readAt: now,
            beaconId: e.beaconId,
            coordinationItemId: e.coordinationItemId,
            actorUserId: e.actorUserId,
          )
        else
          e,
    ];
    final unread = next.where((e) => !e.isRead && e.category.isActionable).length;
    emit(state.copyWith(items: next, unreadCount: unread));
  }
}
