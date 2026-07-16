import 'dart:async';

import 'package:flutter_test/flutter_test.dart';
import 'package:logging/logging.dart';

import 'package:tentura/app/router/home_tab_branches.dart';
import 'package:tentura/domain/entity/realtime/realtime_entity_change.dart';
import 'package:tentura/env.dart';
import 'package:tentura/features/auth/ui/bloc/auth_cubit.dart';
import 'package:tentura/features/home/ui/bloc/new_stuff_cubit.dart';
import 'package:tentura/features/notification_center/data/repository/notification_center_repository.dart';
import 'package:tentura/features/notification_center/domain/entity/notification_center_item.dart';
import 'package:tentura/features/notification_center/domain/use_case/notification_center_case.dart';
import 'package:tentura/features/settings/domain/port/settings_repository_port.dart';

import '../../support/test_realtime_sync.dart';

final class _FakeAuthCubit implements AuthCubit {
  _FakeAuthCubit(String accountId)
    : _state = AuthState(
        updatedAt: DateTime.utc(2026),
        currentAccountId: accountId,
      );

  AuthState _state;
  final _states = StreamController<AuthState>.broadcast();

  @override
  AuthState get state => _state;

  @override
  Stream<AuthState> get stream => _states.stream;

  void switchAccount(String accountId) {
    _state = _state.copyWith(
      currentAccountId: accountId,
      updatedAt: DateTime.timestamp(),
    );
    _states.add(_state);
  }

  Future<void> disposeFake() => _states.close();

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

final class _FakeSettingsRepository implements SettingsRepositoryPort {
  @override
  Future<int?> getNewStuffInboxLastSeenMs(String accountId) async => 10;

  @override
  Future<int?> getNewStuffMyWorkLastSeenMs(String accountId) async => 20;

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

final class _FakeNotificationRepository
    implements NotificationCenterRepository {
  NotificationFeedPage page = (items: const [], unreadCount: 0);
  int fetchCalls = 0;
  final pending = <Completer<NotificationFeedPage>>[];
  final _changes = StreamController<void>.broadcast();

  @override
  Stream<void> get changes => _changes.stream;

  @override
  Future<NotificationFeedPage> fetch({
    int limit = 50,
    DateTime? before,
  }) async {
    fetchCalls++;
    if (pending.isNotEmpty) return pending.removeAt(0).future;
    return page;
  }

  @override
  Future<int> markAllRead() async => 0;

  @override
  Future<int> markRead(List<String> ids) async => ids.length;

  @override
  Future<void> dispose() => _changes.close();
}

Future<void> waitFor(bool Function() condition) async {
  final deadline = DateTime.now().add(const Duration(seconds: 2));
  while (DateTime.now().isBefore(deadline)) {
    if (condition()) return;
    await Future<void>.delayed(const Duration(milliseconds: 10));
  }
  fail('Timed out waiting for global notification count convergence.');
}

void main() {
  test('null last-seen with positive Inbox activity qualifies', () {
    const maxInboxActivityMs = 100;
    const inboxLastSeenMs = null as int?;
    const activeHomeTab = HomeTab.work;
    const accountId = 'U1';

    final qualifies =
        accountId.isNotEmpty &&
        activeHomeTab != HomeTab.inbox &&
        maxInboxActivityMs > 0 &&
        (inboxLastSeenMs == null || maxInboxActivityMs > inboxLastSeenMs);

    expect(qualifies, isTrue);
  });

  test(
    'global unread owner follows notification arrival and catch-up',
    () async {
      final realtime = buildTestRealtimeSync();
      final repository = _FakeNotificationRepository()
        ..page = (items: const [], unreadCount: 1);
      final auth = _FakeAuthCubit('U-me');
      final notificationCase = NotificationCenterCase.forTesting(
        repository: repository,
        realtime: realtime.case_,
        env: const Env(),
        logger: Logger('test'),
      );
      final cubit = NewStuffCubit(
        _FakeSettingsRepository(),
        auth,
        notificationCase,
      );
      await waitFor(() => cubit.state.notificationUnreadCount == 1);
      repository.page = (items: const [], unreadCount: 2);

      realtime.port.emitChange(
        const RealtimeEntityChange(
          kind: RealtimeEntityKind.notification,
          aggregateId: 'U-me',
          operation: RealtimeOperation.insert,
          source: RealtimeChangeSource.serverInvalidation,
        ),
      );
      await waitFor(() => cubit.state.notificationUnreadCount == 2);
      repository.page = (items: const [], unreadCount: 0);
      realtime.port.emitCatchUp();
      await waitFor(() => cubit.state.notificationUnreadCount == 0);

      await cubit.close();
      await auth.disposeFake();
      await repository.dispose();
      await realtime.port.dispose();
    },
  );

  test('old-account unread response cannot overwrite new account', () async {
    final repository = _FakeNotificationRepository();
    final stale = Completer<NotificationFeedPage>();
    final fresh = Completer<NotificationFeedPage>();
    repository.pending.addAll([stale, fresh]);
    final auth = _FakeAuthCubit('U-old');
    final notificationCase = NotificationCenterCase.forTesting(
      repository: repository,
      env: const Env(),
      logger: Logger('test'),
    );
    final cubit = NewStuffCubit(
      _FakeSettingsRepository(),
      auth,
      notificationCase,
    );
    await waitFor(() => repository.fetchCalls == 1);

    auth.switchAccount('U-new');
    await waitFor(() => repository.fetchCalls == 2);
    fresh.complete((items: const <NotificationCenterItem>[], unreadCount: 3));
    await waitFor(() => cubit.state.notificationUnreadCount == 3);
    stale.complete((items: const <NotificationCenterItem>[], unreadCount: 9));
    await Future<void>.delayed(const Duration(milliseconds: 50));

    expect(cubit.state.notificationUnreadCount, 3);
    await cubit.close();
    await auth.disposeFake();
    await repository.dispose();
  });
}
