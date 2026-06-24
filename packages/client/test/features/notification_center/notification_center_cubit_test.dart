import 'package:flutter_test/flutter_test.dart';

import 'package:tentura/features/notification_center/data/repository/notification_center_repository.dart';
import 'package:tentura/features/notification_center/domain/entity/notification_center_item.dart';
import 'package:tentura/features/notification_center/ui/bloc/notification_center_cubit.dart';

class _FakeRepo implements NotificationCenterRepository {
  _FakeRepo(this._page);
  NotificationFeedPage _page;
  final markReadCalls = <List<String>>[];
  var markAllReadCalls = 0;
  bool failMarkRead = false;

  @override
  Future<NotificationFeedPage> fetch({int limit = 50, DateTime? before}) async =>
      _page;

  @override
  Future<int> markRead(List<String> ids) async {
    if (failMarkRead) {
      throw Exception('boom');
    }
    markReadCalls.add(ids);
    return ids.length;
  }

  @override
  Future<int> markAllRead() async {
    markAllReadCalls++;
    return 0;
  }
}

NotificationCenterItem item(
  String id, {
  NotificationCenterCategory category = NotificationCenterCategory.asksOfMe,
  DateTime? readAt,
}) =>
    NotificationCenterItem(
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

void main() {
  test('fetch loads items + unread count', () async {
    final cubit = NotificationCenterCubit(
      repository: _FakeRepo((items: [item('a'), item('b')], unreadCount: 2)),
    );
    await cubit.fetch();
    expect(cubit.state.items.length, 2);
    expect(cubit.state.unreadCount, 2);
    expect(cubit.state.status, isA<StateIsSuccess>());
    await cubit.close();
  });

  test('markRead optimistically marks one item read and drops unread', () async {
    final cubit = NotificationCenterCubit(
      repository: _FakeRepo((items: [item('a'), item('b')], unreadCount: 2)),
    );
    await cubit.fetch();

    await cubit.markRead('a');
    final a = cubit.state.items.firstWhere((e) => e.id == 'a');
    expect(a.isRead, isTrue);
    // Only the remaining unread actionable item counts.
    expect(cubit.state.unreadCount, 1);
    await cubit.close();
  });

  test('markAllRead marks everything read locally', () async {
    final repo = _FakeRepo((items: [item('a'), item('b')], unreadCount: 2));
    final cubit = NotificationCenterCubit(repository: repo);
    await cubit.fetch();

    await cubit.markAllRead();
    expect(cubit.state.items.every((e) => e.isRead), isTrue);
    expect(cubit.state.unreadCount, 0);
    expect(repo.markAllReadCalls, 1);
    await cubit.close();
  });

  test('markRead refetches ground truth on failure', () async {
    final repo = _FakeRepo((items: [item('a')], unreadCount: 1))
      ..failMarkRead = true;
    final cubit = NotificationCenterCubit(repository: repo);
    await cubit.fetch();

    await cubit.markRead('a');
    // Reverted to server state (still unread).
    expect(cubit.state.items.single.isRead, isFalse);
    await cubit.close();
  });
}
