import 'package:logging/logging.dart';
import 'package:test/test.dart';

import 'package:tentura_server/data/service/beacon_notification_service.dart';
import 'package:tentura_server/domain/entity/fcm_token_entity.dart';
import 'package:tentura_server/domain/entity/beacon_notification_context.dart';
import 'package:tentura_server/domain/entity/beacon_notification_intent.dart';
import 'package:tentura_server/domain/entity/notification_category.dart';
import 'package:tentura_server/domain/entity/notification_kind.dart';
import 'package:tentura_server/domain/entity/notification_preferences_entity.dart';
import 'package:tentura_server/domain/entity/notification_priority.dart';
import 'package:tentura_server/domain/entity/user_entity.dart';
import 'package:tentura_server/domain/port/beacon_room_notification_context_port.dart';
import 'package:tentura_server/domain/port/email_notification_port.dart';
import 'package:tentura_server/domain/port/fcm_batch_queue_port.dart';
import 'package:tentura_server/domain/port/fcm_remote_repository_port.dart';
import 'package:tentura_server/domain/port/fcm_token_repository_port.dart';
import 'package:tentura_server/domain/port/notification_outbox_repository_port.dart';
import 'package:tentura_server/domain/port/notification_preference_repository_port.dart';
import 'package:tentura_server/domain/port/user_repository_port.dart';

typedef _OutboxEnqueue = ({
  String accountId,
  NotificationCategory category,
  String dedupKey,
  String? beaconId,
  String? coordinationItemId,
});

typedef _EmailConsider = ({
  String recipientUserId,
  NotificationKind kind,
  String beaconId,
  String dedupKey,
});

class _FakeFcmBatch implements FcmBatchQueuePort {
  @override
  void dispose() {}

  @override
  dynamic noSuchMethod(Invocation invocation) =>
      throw UnimplementedError(invocation.memberName.toString());
}

class _FakeFcmTokens implements FcmTokenRepositoryPort {
  @override
  Future<Iterable<FcmTokenEntity>> getTokensByUserId(String userId) async =>
      const [];

  @override
  dynamic noSuchMethod(Invocation invocation) =>
      throw UnimplementedError(invocation.memberName.toString());
}

class _FakeFcmRemote implements FcmRemoteRepositoryPort {
  @override
  Future<List<Exception>> sendChatNotification({
    required Iterable<String> fcmTokens,
    required dynamic message,
  }) async =>
      const [];

  @override
  dynamic noSuchMethod(Invocation invocation) =>
      throw UnimplementedError(invocation.memberName.toString());
}

class _FakeUsers implements UserRepositoryPort {
  @override
  Future<UserEntity> getById(String id) async =>
      UserEntity(id: id, displayName: 'Actor Name');

  @override
  dynamic noSuchMethod(Invocation invocation) =>
      throw UnimplementedError(invocation.memberName.toString());
}

class _FakeContext implements BeaconRoomNotificationContextPort {
  _FakeContext(this._ctx);
  final BeaconNotificationContext _ctx;

  @override
  Future<BeaconNotificationContext> loadContextForBeacon(String beaconId) async =>
      _ctx;

  @override
  dynamic noSuchMethod(Invocation invocation) =>
      throw UnimplementedError(invocation.memberName.toString());
}

class _FakePrefs implements NotificationPreferenceRepositoryPort {
  @override
  Future<NotificationPreferencesEntity> getForAccount(String accountId) async =>
      NotificationPreferencesEntity.defaults(accountId);

  @override
  Future<Set<String>> getMutedBeaconIds(String accountId, DateTime now) async =>
      const {};

  @override
  dynamic noSuchMethod(Invocation invocation) =>
      throw UnimplementedError(invocation.memberName.toString());
}

class _CapturingOutbox implements NotificationOutboxRepositoryPort {
  final enqueues = <_OutboxEnqueue>[];

  @override
  Future<void> enqueue({
    required String accountId,
    required NotificationCategory category,
    required NotificationKind kind,
    required NotificationPriority priority,
    required String title,
    required String body,
    required String actionUrl,
    required String dedupKey,
    String? beaconId,
    String? coordinationItemId,
    String? actorUserId,
  }) async {
    enqueues.add((
      accountId: accountId,
      category: category,
      dedupKey: dedupKey,
      beaconId: beaconId,
      coordinationItemId: coordinationItemId,
    ));
  }

  @override
  dynamic noSuchMethod(Invocation invocation) =>
      throw UnimplementedError(invocation.memberName.toString());
}

/// Simulates unread collapse: repeated enqueue with the same dedup key bumps
/// a counter instead of inserting a second active row.
class _CollapsingOutbox implements NotificationOutboxRepositoryPort {
  final activeKeys = <String>{};
  final collapseCounts = <String, int>{};

  @override
  Future<void> enqueue({
    required String accountId,
    required NotificationCategory category,
    required NotificationKind kind,
    required NotificationPriority priority,
    required String title,
    required String body,
    required String actionUrl,
    required String dedupKey,
    String? beaconId,
    String? coordinationItemId,
    String? actorUserId,
  }) async {
    if (activeKeys.contains(dedupKey)) {
      collapseCounts[dedupKey] = (collapseCounts[dedupKey] ?? 1) + 1;
    } else {
      activeKeys.add(dedupKey);
    }
  }

  @override
  dynamic noSuchMethod(Invocation invocation) =>
      throw UnimplementedError(invocation.memberName.toString());
}

class _CapturingEmail implements EmailNotificationPort {
  final considers = <_EmailConsider>[];

  @override
  Future<void> considerImmediate({
    required String recipientUserId,
    required NotificationKind kind,
    required String beaconId,
    required String dedupKey,
    required String title,
    required String body,
    required String actionUrl,
    required bool pushDelivered,
  }) async {
    considers.add((
      recipientUserId: recipientUserId,
      kind: kind,
      beaconId: beaconId,
      dedupKey: dedupKey,
    ));
  }

  @override
  dynamic noSuchMethod(Invocation invocation) =>
      throw UnimplementedError(invocation.memberName.toString());
}

void main() {
  BeaconNotificationService build({
    required NotificationOutboxRepositoryPort outbox,
    _CapturingEmail? email,
    BeaconNotificationContext ctx = const BeaconNotificationContext(
      beaconAuthorId: 'author',
    ),
  }) =>
      BeaconNotificationService(
        _FakeFcmBatch(),
        _FakeFcmTokens(),
        _FakeFcmRemote(),
        _FakeUsers(),
        _FakeContext(ctx),
        _FakePrefs(),
        outbox,
        email ?? _CapturingEmail(),
        Logger('test'),
      );

  BeaconNotificationIntent intent({
    required NotificationKind kind,
    String beaconId = 'beacon-1',
    String actorUserId = 'actor',
    String? targetPersonId,
    String? coordinationItemId,
    List<String> admittedUserIds = const [],
  }) =>
      BeaconNotificationIntent(
        kind: kind,
        priority: NotificationPriority.normal,
        beaconId: beaconId,
        actorUserId: actorUserId,
        targetPersonId: targetPersonId,
        coordinationItemId: coordinationItemId,
        admittedUserIds: admittedUserIds,
      );

  group('dedup key', () {
    test('asksOfMe encodes userId, category, beaconId, empty item segment', () async {
      final outbox = _CapturingOutbox();
      final service = build(outbox: outbox);

      await service.dispatch(
        intent(
          kind: NotificationKind.needsMe,
          targetPersonId: 'recipient-1',
        ),
      );

      expect(outbox.enqueues, hasLength(1));
      expect(
        outbox.enqueues.single.dedupKey,
        'recipient-1|asksOfMe|beacon-1|',
      );
      expect(outbox.enqueues.single.category, NotificationCategory.asksOfMe);
    });

    test('coordinationChanged includes coordinationItemId in dedup key', () async {
      final outbox = _CapturingOutbox();
      final service = build(
        outbox: outbox,
        ctx: const BeaconNotificationContext(beaconAuthorId: 'author'),
      );

      await service.dispatch(
        intent(
          kind: NotificationKind.coordinationChanged,
          coordinationItemId: 'item-42',
        ),
      );

      expect(outbox.enqueues, hasLength(1));
      expect(
        outbox.enqueues.single.dedupKey,
        'author|coordination|beacon-1|item-42',
      );
      expect(outbox.enqueues.single.coordinationItemId, 'item-42');
    });

    test('empty beaconId yields empty beacon segment in dedup key', () async {
      final outbox = _CapturingOutbox();
      final service = build(outbox: outbox);

      await service.dispatch(
        intent(
          kind: NotificationKind.needsMe,
          beaconId: '',
          targetPersonId: 'recipient-1',
        ),
      );

      expect(outbox.enqueues.single.dedupKey, 'recipient-1|asksOfMe||');
      expect(outbox.enqueues.single.beaconId, isNull);
    });

    test('distinct recipients get distinct dedup keys for the same intent', () async {
      final outbox = _CapturingOutbox();
      final service = build(
        outbox: outbox,
        ctx: const BeaconNotificationContext(
          beaconAuthorId: 'author',
          stewardUserIds: {'steward'},
        ),
      );

      await service.dispatch(
        intent(
          kind: NotificationKind.promiseMade,
          targetPersonId: 'affected',
        ),
      );

      expect(outbox.enqueues, hasLength(3));
      final keys = outbox.enqueues.map((e) => e.dedupKey).toSet();
      expect(keys, {
        'author|coordination|beacon-1|',
        'steward|coordination|beacon-1|',
        'affected|coordination|beacon-1|',
      });
    });

    test('different categories for same user and beacon do not collide', () async {
      final outbox = _CapturingOutbox();
      final service = build(outbox: outbox);

      await service.dispatch(
        intent(
          kind: NotificationKind.needsMe,
          targetPersonId: 'recipient-1',
        ),
      );
      await service.dispatch(
        intent(
          kind: NotificationKind.coordinationChanged,
          targetPersonId: 'recipient-1',
        ),
      );

      final keys = outbox.enqueues.map((e) => e.dedupKey).toList();
      expect(keys[0], 'recipient-1|asksOfMe|beacon-1|');
      expect(keys[1], 'author|coordination|beacon-1|');
      expect(keys.toSet(), hasLength(2));
    });

    test('different coordination items for same recipient do not collide', () async {
      final outbox = _CapturingOutbox();
      final service = build(
        outbox: outbox,
        ctx: const BeaconNotificationContext(beaconAuthorId: 'author'),
      );

      await service.dispatch(
        intent(
          kind: NotificationKind.coordinationChanged,
          coordinationItemId: 'item-a',
        ),
      );
      await service.dispatch(
        intent(
          kind: NotificationKind.coordinationChanged,
          coordinationItemId: 'item-b',
        ),
      );

      expect(
        outbox.enqueues.map((e) => e.dedupKey).toSet(),
        {
          'author|coordination|beacon-1|item-a',
          'author|coordination|beacon-1|item-b',
        },
      );
    });

    test('outbox and email receive the same dedup key', () async {
      final outbox = _CapturingOutbox();
      final email = _CapturingEmail();
      final service = build(outbox: outbox, email: email);

      await service.dispatch(
        intent(
          kind: NotificationKind.needsMe,
          targetPersonId: 'recipient-1',
        ),
      );

      expect(outbox.enqueues.single.dedupKey, 'recipient-1|asksOfMe|beacon-1|');
      expect(email.considers.single.dedupKey, outbox.enqueues.single.dedupKey);
    });

    test('reviewReady uses unblocksMe category in dedup key', () async {
      final outbox = _CapturingOutbox();
      final service = build(outbox: outbox);

      await service.dispatch(
        intent(
          kind: NotificationKind.reviewReady,
          admittedUserIds: ['reviewer-1'],
        ),
      );

      expect(outbox.enqueues.single.dedupKey, 'reviewer-1|unblocksMe|beacon-1|');
      expect(outbox.enqueues.single.category, NotificationCategory.unblocksMe);
    });
  });

  group('unread collapse contract', () {
    test('repeated dispatch passes identical dedup key for collapse', () async {
      final outbox = _CollapsingOutbox();
      final service = build(outbox: outbox);
      final sameIntent = intent(
        kind: NotificationKind.needsMe,
        targetPersonId: 'recipient-1',
      );

      await service.dispatch(sameIntent);
      await service.dispatch(sameIntent);

      expect(outbox.activeKeys, {'recipient-1|asksOfMe|beacon-1|'});
      expect(outbox.collapseCounts['recipient-1|asksOfMe|beacon-1|'], 2);
    });

    test('changed coordination item produces a new dedup key (no collapse)', () async {
      final outbox = _CollapsingOutbox();
      final service = build(
        outbox: outbox,
        ctx: const BeaconNotificationContext(beaconAuthorId: 'author'),
      );

      await service.dispatch(
        intent(
          kind: NotificationKind.coordinationChanged,
          coordinationItemId: 'item-a',
        ),
      );
      await service.dispatch(
        intent(
          kind: NotificationKind.coordinationChanged,
          coordinationItemId: 'item-b',
        ),
      );

      expect(outbox.activeKeys, hasLength(2));
      expect(outbox.collapseCounts, isEmpty);
    });
  });
}
