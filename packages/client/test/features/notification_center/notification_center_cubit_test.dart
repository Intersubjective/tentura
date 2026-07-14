import 'dart:async';

import 'package:flutter_test/flutter_test.dart';
import 'package:logging/logging.dart';

import 'package:tentura/domain/entity/realtime/realtime_entity_change.dart';
import 'package:tentura/domain/use_case/realtime_sync_case.dart';
import 'package:tentura/env.dart';
import 'package:tentura/features/notification_center/data/repository/notification_center_repository.dart';
import 'package:tentura/features/notification_center/domain/entity/notification_center_item.dart';
import 'package:tentura/features/notification_center/domain/use_case/notification_center_case.dart';
import 'package:tentura/features/notification_center/ui/bloc/notification_center_cubit.dart';

import '../../support/test_realtime_sync.dart';

final class _FakeRepo implements NotificationCenterRepository {
  _FakeRepo(this.page);

  NotificationFeedPage page;
  Object? fetchError;
  bool failMarkRead = false;
  int fetchCalls = 0;
  final markReadCalls = <List<String>>[];
  int markAllReadCalls = 0;
  final pending = <Completer<NotificationFeedPage>>[];
  final _changes = StreamController<void>.broadcast();

  @override
  Stream<void> get changes => _changes.stream;

  void notifyChanged() => _changes.add(null);

  @override
  Future<NotificationFeedPage> fetch({
    int limit = 50,
    DateTime? before,
  }) async {
    fetchCalls++;
    if (pending.isNotEmpty) return pending.removeAt(0).future;
    final error = fetchError;
    if (error is Exception) throw error;
    if (error is Error) throw error;
    return page;
  }

  @override
  Future<int> markRead(List<String> ids) async {
    if (failMarkRead) throw Exception('boom');
    markReadCalls.add(ids);
    _changes.add(null);
    return ids.length;
  }

  @override
  Future<int> markAllRead() async {
    markAllReadCalls++;
    _changes.add(null);
    return 0;
  }

  @override
  Future<void> dispose() => _changes.close();
}

NotificationCenterItem item(
  String id, {
  NotificationCenterCategory category = NotificationCenterCategory.asksOfMe,
  DateTime? readAt,
}) => NotificationCenterItem(
  id: id,
  category: category,
  kind: 'needsMe',
  title: 'T-$id',
  body: 'B-$id',
  actionUrl: '/#/x',
  createdAt: DateTime(2026, 6, 24),
  collapsedCount: 1,
  readAt: readAt,
);

NotificationCenterCase _notificationCase(
  _FakeRepo repository, {
  RealtimeSyncCase? realtime,
}) => NotificationCenterCase.forTesting(
  repository: repository,
  realtime: realtime,
  env: const Env(),
  logger: Logger('test'),
);

NotificationCenterCubit _cubitFor(
  _FakeRepo repository, {
  RealtimeSyncCase? realtime,
}) => NotificationCenterCubit(
  notificationCenterCase: _notificationCase(repository, realtime: realtime),
  logger: Logger('test'),
);

Future<void> _waitFor(bool Function() condition) async {
  final deadline = DateTime.now().add(const Duration(seconds: 2));
  while (DateTime.now().isBefore(deadline)) {
    if (condition()) return;
    await Future<void>.delayed(const Duration(milliseconds: 10));
  }
  fail('Timed out waiting for notification convergence.');
}

void main() {
  test('fetch loads items + unread count', () async {
    final repo = _FakeRepo((items: [item('a'), item('b')], unreadCount: 2));
    final cubit = _cubitFor(repo);

    await cubit.fetch();

    expect(cubit.state.items.length, 2);
    expect(cubit.state.unreadCount, 2);
    expect(cubit.state.status, isA<StateIsSuccess>());
    await cubit.close();
    await repo.dispose();
  });

  test(
    'markRead optimistically marks one item read and drops unread',
    () async {
      final repo = _FakeRepo((items: [item('a'), item('b')], unreadCount: 2));
      final cubit = _cubitFor(repo);
      await cubit.fetch();

      await cubit.markRead('a');

      final a = cubit.state.items.firstWhere((e) => e.id == 'a');
      expect(a.isRead, isTrue);
      expect(cubit.state.unreadCount, 1);
      await cubit.close();
      await repo.dispose();
    },
  );

  test('markAllRead marks everything read locally', () async {
    final repo = _FakeRepo((items: [item('a'), item('b')], unreadCount: 2));
    final cubit = _cubitFor(repo);
    await cubit.fetch();

    await cubit.markAllRead();

    expect(cubit.state.items.every((e) => e.isRead), isTrue);
    expect(cubit.state.unreadCount, 0);
    expect(repo.markAllReadCalls, 1);
    await cubit.close();
    await repo.dispose();
  });

  test('markRead refetches ground truth on failure', () async {
    final repo = _FakeRepo((items: [item('a')], unreadCount: 1))
      ..failMarkRead = true;
    final cubit = _cubitFor(repo);
    await cubit.fetch();

    await cubit.markRead('a');

    expect(cubit.state.items.single.isRead, isFalse);
    await cubit.close();
    await repo.dispose();
  });

  test('notification invalidation refreshes an open center', () async {
    final realtime = buildTestRealtimeSync();
    final repo = _FakeRepo((items: [item('a')], unreadCount: 1));
    final cubit = _cubitFor(repo, realtime: realtime.case_);
    await cubit.fetch();
    repo.page = (items: [item('a'), item('b')], unreadCount: 2);

    realtime.port.emitChange(
      const RealtimeEntityChange(
        kind: RealtimeEntityKind.notification,
        aggregateId: 'U-me',
        operation: RealtimeOperation.insert,
        source: RealtimeChangeSource.serverInvalidation,
      ),
    );
    await _waitFor(() => cubit.state.items.length == 2);

    expect(cubit.state.unreadCount, 2);
    await cubit.close();
    await repo.dispose();
    await realtime.case_.dispose();
    await realtime.port.dispose();
  });

  test('catch-up refreshes read truth without UI effects', () async {
    final realtime = buildTestRealtimeSync();
    final repo = _FakeRepo((items: [item('a')], unreadCount: 1));
    final cubit = _cubitFor(repo, realtime: realtime.case_);
    await cubit.fetch();
    repo.page = (
      items: [item('a', readAt: DateTime.utc(2026, 6, 25))],
      unreadCount: 0,
    );

    realtime.port.emitCatchUp();
    await _waitFor(() => cubit.state.unreadCount == 0);

    expect(cubit.state.items.single.isRead, isTrue);
    await cubit.close();
    await repo.dispose();
    await realtime.case_.dispose();
    await realtime.port.dispose();
  });

  test('newer notification refresh wins over stale completion', () async {
    final realtime = buildTestRealtimeSync();
    final repo = _FakeRepo((items: [item('initial')], unreadCount: 1));
    final cubit = _cubitFor(repo, realtime: realtime.case_);
    await cubit.fetch();
    final stale = Completer<NotificationFeedPage>();
    final fresh = Completer<NotificationFeedPage>();
    repo.pending.addAll([stale, fresh]);

    realtime.port.emitCatchUp();
    await _waitFor(() => repo.fetchCalls == 2);
    realtime.port.emitCatchUp();
    await _waitFor(() => repo.fetchCalls == 3);
    fresh.complete((items: [item('fresh')], unreadCount: 1));
    await _waitFor(() => cubit.state.items.single.id == 'fresh');
    stale.complete((items: [item('stale')], unreadCount: 1));
    await Future<void>.delayed(const Duration(milliseconds: 50));

    expect(cubit.state.items.single.id, 'fresh');
    await cubit.close();
    await repo.dispose();
    await realtime.case_.dispose();
    await realtime.port.dispose();
  });

  test('background failure keeps the usable feed', () async {
    final repo = _FakeRepo((items: [item('stable')], unreadCount: 1));
    final cubit = _cubitFor(repo);
    await cubit.fetch();
    repo
      ..fetchError = StateError('offline')
      ..notifyChanged();
    await _waitFor(() => repo.fetchCalls == 2);
    await Future<void>.delayed(const Duration(milliseconds: 50));

    expect(cubit.state.items.single.id, 'stable');
    expect(cubit.state.unreadCount, 1);
    await cubit.close();
    await repo.dispose();
  });
}
