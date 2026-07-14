import 'dart:async';

import 'package:logging/logging.dart';
import 'package:get_it/get_it.dart';

import '../../domain/entity/notification_center_item.dart';
import '../../domain/use_case/notification_center_case.dart';
import 'notification_center_state.dart';

export 'package:flutter_bloc/flutter_bloc.dart';

export 'notification_center_state.dart';

class NotificationCenterCubit extends Cubit<NotificationCenterState> {
  NotificationCenterCubit({
    NotificationCenterCase? notificationCenterCase,
    Logger? logger,
  }) : _case = notificationCenterCase ?? GetIt.I<NotificationCenterCase>(),
       _logger = logger ?? GetIt.I<Logger>(),
       super(const NotificationCenterState()) {
    _changesSub = _case.changes.listen(
      (_) => _scheduleSilentFetch(),
      cancelOnError: false,
    );
    _accountSub = _case.accountChanges.listen(
      _onAccountChanged,
      cancelOnError: false,
    );
  }

  static const _refreshDebounce = Duration(milliseconds: 100);

  final NotificationCenterCase _case;
  final Logger _logger;

  late final StreamSubscription<void> _changesSub;
  late final StreamSubscription<String> _accountSub;

  Timer? _refreshTimer;
  int _fetchSequence = 0;
  String? _accountId;

  @override
  Future<void> close() async {
    _refreshTimer?.cancel();
    _fetchSequence++;
    await _changesSub.cancel();
    await _accountSub.cancel();
    return super.close();
  }

  Future<void> fetch({bool showLoading = true}) async {
    final sequence = ++_fetchSequence;
    if (showLoading) {
      emit(state.copyWith(status: const StateIsLoading()));
    }
    try {
      final page = await _case.fetch();
      if (isClosed || sequence != _fetchSequence) return;
      emit(
        state.copyWith(
          items: page.items,
          unreadCount: page.unreadCount,
          status: const StateIsSuccess(),
        ),
      );
    } catch (e) {
      if (isClosed || sequence != _fetchSequence) return;
      _logger.warning('NotificationCenter fetch failed', e);
      emit(state.copyWith(status: const StateIsSuccess()));
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
      await _case.markRead([id]);
    } catch (_) {
      // Best-effort: refetch to restore ground truth on failure.
      await fetch(showLoading: false);
    }
  }

  Future<void> markAllRead() async {
    if (state.unreadCount == 0 && state.items.every((e) => e.isRead)) {
      return;
    }
    final ids = state.items.where((e) => !e.isRead).map((e) => e.id).toSet();
    _applyRead(ids);
    try {
      await _case.markAllRead();
    } catch (_) {
      await fetch(showLoading: false);
    }
  }

  void _scheduleSilentFetch() {
    if (isClosed) return;
    _refreshTimer?.cancel();
    _refreshTimer = Timer(_refreshDebounce, () {
      _refreshTimer = null;
      if (!isClosed) unawaited(fetch(showLoading: false));
    });
  }

  void _onAccountChanged(String accountId) {
    final previous = _accountId;
    _accountId = accountId;
    if (previous == null || previous == accountId) return;
    _refreshTimer?.cancel();
    _fetchSequence++;
    emit(const NotificationCenterState(status: StateIsSuccess()));
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
    final unread = next
        .where((e) => !e.isRead && e.category.isActionable)
        .length;
    emit(state.copyWith(items: next, unreadCount: unread));
  }
}
