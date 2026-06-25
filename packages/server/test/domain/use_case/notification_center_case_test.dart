import 'package:test/test.dart';

import 'package:tentura_server/domain/coordination/filter_beacon_notifications.dart';
import 'package:tentura_server/domain/entity/notification_category.dart';
import 'package:tentura_server/domain/entity/notification_kind.dart';
import 'package:tentura_server/domain/entity/notification_outbox_item_entity.dart';
import 'package:tentura_server/domain/entity/notification_priority.dart';
import 'package:tentura_server/domain/port/beacon_access_guard.dart';
import 'package:tentura_server/domain/port/notification_outbox_repository_port.dart';
import 'package:tentura_server/domain/use_case/notification_center_case.dart';

import '../../support/fake_beacon_access_guard.dart';

class _FakeOutbox implements NotificationOutboxRepositoryPort {
  _FakeOutbox(this._rows);

  final List<NotificationOutboxItemEntity> _rows;

  String? lastAccountId;
  int? lastLimit;
  DateTime? lastBefore;

  String? unreadCountAccountId;
  String? markReadAccountId;
  List<String>? markReadIds;
  String? markAllReadAccountId;

  @override
  Future<List<NotificationOutboxItemEntity>> feedForAccount({
    required String accountId,
    int limit = 50,
    DateTime? before,
  }) async {
    lastAccountId = accountId;
    lastLimit = limit;
    lastBefore = before;
    return _rows;
  }

  @override
  Future<int> unreadActionableCount(String accountId) async {
    unreadCountAccountId = accountId;
    return 3;
  }

  @override
  Future<int> markRead({
    required String accountId,
    required List<String> ids,
  }) async {
    markReadAccountId = accountId;
    markReadIds = ids;
    return ids.length;
  }

  @override
  Future<int> markAllRead(String accountId) async {
    markAllReadAccountId = accountId;
    return 7;
  }

  @override
  dynamic noSuchMethod(Invocation i) => throw UnimplementedError('$i');
}

class _PerBeaconGuard implements BeaconAccessGuard {
  _PerBeaconGuard({
    this.contentAllowed = const {},
    this.tombstoneAllowed = const {},
  });

  final Map<String, bool> contentAllowed;
  final Map<String, bool> tombstoneAllowed;

  @override
  Future<bool> canReadContent({
    required String beaconId,
    required String viewerId,
  }) async =>
      contentAllowed[beaconId] ?? false;

  @override
  Future<bool> canReadTombstone({
    required String beaconId,
    required String viewerId,
  }) async =>
      tombstoneAllowed[beaconId] ?? false;

  @override
  Future<bool> canReadInvolvement({
    required String beaconId,
    required String viewerId,
  }) async =>
      false;
}

void main() {
  const accountId = 'u1';
  final createdAt = DateTime.utc(2026, 6, 24, 12);

  NotificationOutboxItemEntity item({
    required String id,
    String? beaconId,
    String title = 'Title',
    String body = 'Body',
  }) =>
      NotificationOutboxItemEntity(
        id: id,
        accountId: accountId,
        category: NotificationCategory.asksOfMe,
        kind: NotificationKind.needsMe,
        priority: NotificationPriority.high,
        title: title,
        body: body,
        actionUrl: '/#/beacon/$beaconId',
        createdAt: createdAt,
        collapsedCount: 1,
        beaconId: beaconId,
      );

  group('NotificationCenterCase.feed', () {
    test('forwards accountId, limit, and before to the outbox', () async {
      final outbox = _FakeOutbox([item(id: 'n1')]);
      final before = DateTime.utc(2026, 6, 24, 11);
      final case_ = NotificationCenterCase(outbox, FakeBeaconAccessGuard());

      await case_.feed(accountId: accountId, limit: 25, before: before);

      expect(outbox.lastAccountId, accountId);
      expect(outbox.lastLimit, 25);
      expect(outbox.lastBefore, before);
    });

    test('clamps limit to 1..100', () async {
      final outbox = _FakeOutbox([]);
      final case_ = NotificationCenterCase(outbox, FakeBeaconAccessGuard());

      await case_.feed(accountId: accountId, limit: 0);
      expect(outbox.lastLimit, 1);

      await case_.feed(accountId: accountId, limit: -5);
      expect(outbox.lastLimit, 1);

      await case_.feed(accountId: accountId, limit: 200);
      expect(outbox.lastLimit, 100);
    });

    test('passes through rows without a beacon id', () async {
      final rows = [item(id: 'n1'), item(id: 'n2')];
      final case_ = NotificationCenterCase(
        _FakeOutbox(rows),
        FakeBeaconAccessGuard(contentAllowed: false, tombstoneAllowed: false),
      );

      final feed = await case_.feed(accountId: accountId);

      expect(feed, rows);
    });

    test('keeps beacon-linked rows when content is readable', () async {
      final rows = [item(id: 'n1', beaconId: 'b1', title: 'Help needed')];
      final case_ = NotificationCenterCase(
        _FakeOutbox(rows),
        FakeBeaconAccessGuard(contentAllowed: true),
      );

      final feed = await case_.feed(accountId: accountId);

      expect(feed, hasLength(1));
      expect(feed.first.title, 'Help needed');
    });

    test('tombstones rows when content is hidden but tombstone is visible', () async {
      final rows = [item(id: 'n1', beaconId: 'b1', title: 'Help needed')];
      final case_ = NotificationCenterCase(
        _FakeOutbox(rows),
        FakeBeaconAccessGuard(contentAllowed: false, tombstoneAllowed: true),
      );

      final feed = await case_.feed(accountId: accountId);

      expect(feed, hasLength(1));
      expect(feed.first.title, kBeaconUnavailableNotificationTitle);
      expect(feed.first.body, kBeaconUnavailableNotificationBody);
    });

    test('drops rows when neither content nor tombstone is visible', () async {
      final rows = [
        item(id: 'n1', beaconId: 'b1'),
        item(id: 'n2'),
      ];
      final case_ = NotificationCenterCase(
        _FakeOutbox(rows),
        _PerBeaconGuard(
          contentAllowed: const {'b1': false},
          tombstoneAllowed: const {'b1': false},
        ),
      );

      final feed = await case_.feed(accountId: accountId);

      expect(feed, [rows[1]]);
    });
  });

  group('NotificationCenterCase read helpers', () {
    test('unreadActionableCount delegates to the outbox', () async {
      final outbox = _FakeOutbox([]);
      final case_ = NotificationCenterCase(outbox, FakeBeaconAccessGuard());

      final count = await case_.unreadActionableCount(accountId);

      expect(count, 3);
      expect(outbox.unreadCountAccountId, accountId);
    });

    test('markRead delegates accountId and ids', () async {
      final outbox = _FakeOutbox([]);
      final case_ = NotificationCenterCase(outbox, FakeBeaconAccessGuard());

      final updated = await case_.markRead(
        accountId: accountId,
        ids: const ['a', 'b'],
      );

      expect(updated, 2);
      expect(outbox.markReadAccountId, accountId);
      expect(outbox.markReadIds, ['a', 'b']);
    });

    test('markAllRead delegates to the outbox', () async {
      final outbox = _FakeOutbox([]);
      final case_ = NotificationCenterCase(outbox, FakeBeaconAccessGuard());

      final updated = await case_.markAllRead(accountId);

      expect(updated, 7);
      expect(outbox.markAllReadAccountId, accountId);
    });
  });
}
