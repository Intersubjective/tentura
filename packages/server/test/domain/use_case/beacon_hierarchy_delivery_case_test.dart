import 'package:injectable/injectable.dart' show Environment;
import 'package:logging/logging.dart';
import 'package:test/test.dart';
import 'package:tentura_root/domain/entity/beacon_hierarchy_delivery_direction.dart';
import 'package:tentura_root/domain/entity/beacon_hierarchy_event.dart';
import 'package:tentura_root/domain/entity/beacon_status.dart';

import 'package:tentura_server/consts/beacon_hierarchy_delivery_consts.dart';
import 'package:tentura_server/domain/attention/attention_models.dart';
import 'package:tentura_server/domain/entity/beacon_notification_context.dart';
import 'package:tentura_server/domain/port/beacon_hierarchy_outbox_port.dart';
import 'package:tentura_server/domain/use_case/beacon_hierarchy_delivery_case.dart';
import 'package:tentura_server/env.dart';

import '../../support/fake_user_block_repository.dart';
import '../../support/test_attention_harness.dart';

final class _InMemoryDeliveryOutbox implements BeaconHierarchyOutboxPort {
  final events = <String, BeaconHierarchyEvent>{};
  final destinationStatus = <String, BeaconStatus?>{};
  final rows = <String, _DeliveryRow>{};
  var failOnNoticeInsert = false;
  var failOnMarkDelivered = false;
  int scheduleRetryCalls = 0;
  String? lastSafeErrorCode;
  String? lastRetryLeaseOwner;
  int operatorParkCalls = 0;

  String rowKey(String eventId, String targetBeaconId) =>
      '$eventId::$targetBeaconId';

  void seedDelivery({
    required BeaconHierarchyEvent event,
    required String targetBeaconId,
    BeaconHierarchyDeliveryDirection direction =
        BeaconHierarchyDeliveryDirection.ancestor,
    BeaconStatus? destination,
  }) {
    events[event.eventId] = event;
    if (destination != null) {
      destinationStatus[targetBeaconId] = destination;
    }
    rows[rowKey(event.eventId, targetBeaconId)] = _DeliveryRow(
      eventId: event.eventId,
      targetBeaconId: targetBeaconId,
      direction: direction,
      state: 'leased',
      leaseOwner: 'worker-a',
      attemptCount: 1,
    );
  }

  @override
  Future<List<BeaconHierarchyDeliveryTarget>> claimDueDeliveries({
    required String leaseOwner,
    required DateTime now,
    required int limit,
  }) async {
    final claimed = <BeaconHierarchyDeliveryTarget>[];
    for (final row in rows.values) {
      if (claimed.length >= limit) break;
      if (row.state != 'pending' && row.state != 'leased') continue;
      row.state = 'leased';
      row.leaseOwner = leaseOwner;
      row.attemptCount++;
      claimed.add(
        BeaconHierarchyDeliveryTarget(
          eventId: row.eventId,
          targetBeaconId: row.targetBeaconId,
          direction: row.direction,
        ),
      );
    }
    return claimed;
  }

  @override
  Future<BeaconHierarchyEvent?> loadEvent(String eventId) async =>
      events[eventId];

  @override
  Future<BeaconStatus?> loadDestinationBeaconStatus(
    String targetBeaconId,
  ) async =>
      destinationStatus[targetBeaconId];

  @override
  Future<String> insertHierarchyLifecycleNotice({
    required String eventId,
    required String targetBeaconId,
    required BeaconHierarchyDeliveryDirection direction,
    required BeaconStatus toStatus,
    required DateTime occurredAt,
    required String noticeBody,
    required bool sourceDeleted,
  }) async {
    if (failOnNoticeInsert) {
      throw StateError('NoticeInsertFailure injected');
    }
    return 'R-notice-$eventId-$targetBeaconId';
  }

  @override
  Future<void> markDeliveryDelivered({
    required String eventId,
    required String targetBeaconId,
    required String leaseOwner,
    String? noticeMessageId,
  }) async {
    if (failOnMarkDelivered) {
      throw StateError('AttentionDispatchFailure injected');
    }
    final row = rows[rowKey(eventId, targetBeaconId)];
    if (row == null || row.leaseOwner != leaseOwner) return;
    row.state = 'delivered';
    row.leaseOwner = null;
    row.noticeMessageId = noticeMessageId;
  }

  @override
  Future<void> markDeliverySuppressed({
    required String eventId,
    required String targetBeaconId,
    required String leaseOwner,
  }) async {
    final row = rows[rowKey(eventId, targetBeaconId)];
    if (row == null || row.leaseOwner != leaseOwner) return;
    row.state = 'suppressed';
    row.leaseOwner = null;
  }

  @override
  Future<void> scheduleDeliveryRetry({
    required String eventId,
    required String targetBeaconId,
    required String leaseOwner,
    required DateTime now,
    required int attemptCount,
    required String safeErrorCode,
  }) async {
    scheduleRetryCalls++;
    lastSafeErrorCode = safeErrorCode;
    lastRetryLeaseOwner = leaseOwner;
    final row = rows[rowKey(eventId, targetBeaconId)];
    if (row == null || row.leaseOwner != leaseOwner) return;
    row.state = 'pending';
    row.attemptCount = attemptCount;
    row.lastSafeErrorCode = safeErrorCode;
    row.leaseOwner = null;
  }

  @override
  Future<bool> operatorParkPoisonedDelivery({
    required String eventId,
    required String targetBeaconId,
  }) async {
    operatorParkCalls++;
    final row = rows[rowKey(eventId, targetBeaconId)];
    if (row == null || row.attemptCount < BeaconHierarchyDeliverySafeError.poisonAttemptThreshold) {
      return false;
    }
    row.state = 'parked';
    return true;
  }

  @override
  Future<int?> loadDeliveryAttemptCount({
    required String eventId,
    required String targetBeaconId,
  }) async =>
      rows[rowKey(eventId, targetBeaconId)]?.attemptCount;

  @override
  dynamic noSuchMethod(Invocation invocation) => throw UnimplementedError('$invocation');
}

final class _DeliveryRow {
  _DeliveryRow({
    required this.eventId,
    required this.targetBeaconId,
    required this.direction,
    required this.state,
    required this.leaseOwner,
    required this.attemptCount,
  });

  final String eventId;
  final String targetBeaconId;
  final BeaconHierarchyDeliveryDirection direction;
  String state;
  String? leaseOwner;
  int attemptCount;
  String? lastSafeErrorCode;
  String? noticeMessageId;
}

BeaconHierarchyEvent _event({
  required String eventId,
  required String sourceBeaconId,
  required int sourceSequence,
  BeaconStatus toStatus = BeaconStatus.closed,
  String? actorUserId,
}) =>
    BeaconHierarchyEvent(
      eventId: eventId,
      sourceBeaconId: sourceBeaconId,
      sourceSequence: sourceSequence,
      fromStatus: BeaconStatus.open,
      toStatus: toStatus,
      occurredAt: DateTime.utc(2026, 3, 1),
      actorUserId: actorUserId,
    );

BeaconHierarchyDeliveryCase _case({
  required _InMemoryDeliveryOutbox outbox,
  TestAttentionHarness? harness,
}) {
  final h = harness ?? TestAttentionHarness();
  return BeaconHierarchyDeliveryCase(
    outbox,
    h.transactional,
    h.intents,
    env: Env(environment: Environment.test),
    logger: Logger('beacon_hierarchy_delivery_case_test'),
  );
}

void main() {
  group('BeaconHierarchyDeliveryCase', () {
    test('runDue with no claims is a no-op', () async {
      final outbox = _InMemoryDeliveryOutbox();
      final delivery = _case(outbox: outbox);

      await delivery.runDue(workerId: 'worker-1', now: DateTime.utc(2026, 3, 2));

      expect(outbox.scheduleRetryCalls, 0);
    });

    test('deleted destination is suppressed without attention', () async {
      final outbox = _InMemoryDeliveryOutbox();
      final harness = TestAttentionHarness();
      final event = _event(eventId: 'HE-del', sourceBeaconId: 'B-src', sourceSequence: 1);
      outbox.seedDelivery(
        event: event,
        targetBeaconId: 'B-target',
        destination: BeaconStatus.deleted,
      );
      outbox.destinationStatus['B-src'] = BeaconStatus.open;

      await _case(outbox: outbox, harness: harness).runDue(
        workerId: 'worker-a',
        now: DateTime.utc(2026, 3, 2),
      );

      expect(outbox.rows['HE-del::B-target']!.state, 'suppressed');
      expect(harness.recorded, isEmpty);
    });

    test('successful delivery records attention and marks delivered', () async {
      final outbox = _InMemoryDeliveryOutbox();
      final harness = TestAttentionHarness(
        context: const BeaconNotificationContext(beaconAuthorId: 'U-author'),
      );
      final event = _event(
        eventId: 'HE-ok',
        sourceBeaconId: 'B-src',
        sourceSequence: 1,
        actorUserId: 'U-actor',
      );
      outbox.seedDelivery(
        event: event,
        targetBeaconId: 'B-target',
        destination: BeaconStatus.open,
      );
      outbox.destinationStatus['B-src'] = BeaconStatus.open;
      outbox.destinationStatus['B-target'] = BeaconStatus.open;

      await _case(outbox: outbox, harness: harness).runDue(
        workerId: 'worker-a',
        now: DateTime.utc(2026, 3, 2),
      );

      expect(outbox.rows['HE-ok::B-target']!.state, 'delivered');
      expect(harness.recorded, hasLength(1));
      expect(
        harness.recorded.single.eventType,
        AttentionEventType.beaconHierarchyStatusChanged,
      );
      expect(
        harness.recorded.single.sourceEventKey,
        'hierarchy:HE-ok:B-target',
      );
      expect(harness.recorded.single.beaconId, 'B-target');
    });

    test('notice insert failure schedules owner-qualified retry with safe code', () async {
      final outbox = _InMemoryDeliveryOutbox();
      final event = _event(eventId: 'HE-fail', sourceBeaconId: 'B-src', sourceSequence: 1);
      outbox.seedDelivery(
        event: event,
        targetBeaconId: 'B-target',
        destination: BeaconStatus.open,
      );
      outbox.destinationStatus['B-src'] = BeaconStatus.open;
      outbox.destinationStatus['B-target'] = BeaconStatus.open;
      outbox.failOnNoticeInsert = true;

      await _case(outbox: outbox).runDue(
        workerId: 'worker-a',
        now: DateTime.utc(2026, 3, 2),
      );

      expect(outbox.scheduleRetryCalls, 1);
      expect(outbox.lastRetryLeaseOwner, 'worker-a');
      expect(outbox.lastSafeErrorCode, BeaconHierarchyDeliverySafeError.unknown);
      expect(outbox.rows['HE-fail::B-target']!.state, 'pending');
    });

    test('stale worker retry update is ignored after row is delivered', () async {
      final outbox = _InMemoryDeliveryOutbox();
      final event = _event(eventId: 'HE-stale', sourceBeaconId: 'B-src', sourceSequence: 1);
      outbox.seedDelivery(
        event: event,
        targetBeaconId: 'B-target',
        destination: BeaconStatus.open,
      );
      outbox.destinationStatus['B-src'] = BeaconStatus.open;
      outbox.destinationStatus['B-target'] = BeaconStatus.open;
      outbox.rows['HE-stale::B-target']!.state = 'delivered';
      outbox.rows['HE-stale::B-target']!.leaseOwner = null;

      await outbox.scheduleDeliveryRetry(
        eventId: event.eventId,
        targetBeaconId: 'B-target',
        leaseOwner: 'worker-stale',
        now: DateTime.utc(2026, 3, 2),
        attemptCount: 2,
        safeErrorCode: BeaconHierarchyDeliverySafeError.unknown,
      );

      expect(outbox.rows['HE-stale::B-target']!.state, 'delivered');
    });

    test('parkPoisonedDeliveryAsOperator delegates to outbox', () async {
      final outbox = _InMemoryDeliveryOutbox();
      final event = _event(eventId: 'HE-poison', sourceBeaconId: 'B-src', sourceSequence: 1);
      outbox.seedDelivery(
        event: event,
        targetBeaconId: 'B-target',
        destination: BeaconStatus.open,
      );
      outbox.rows['HE-poison::B-target']!.state = 'pending';
      outbox.rows['HE-poison::B-target']!.attemptCount =
          BeaconHierarchyDeliverySafeError.poisonAttemptThreshold;

      final parked = await _case(outbox: outbox).parkPoisonedDeliveryAsOperator(
        eventId: event.eventId,
        targetBeaconId: 'B-target',
        operatorId: 'U-operator',
      );

      expect(parked, isTrue);
      expect(outbox.operatorParkCalls, 1);
      expect(outbox.rows['HE-poison::B-target']!.state, 'parked');
    });

    test('beaconHierarchyStatusChanged suppresses actor and blocked peers', () async {
      const actor = 'U-actor';
      const blocked = 'U-blocked';
      final blocks = FakeUserBlockRepository()..blockPair(actor, blocked);
      final harness = TestAttentionHarness(
        context: BeaconNotificationContext(
          beaconAuthorId: 'U-author',
          admittedUserIds: {blocked, 'U-admitted'},
        ),
        userBlocks: blocks,
      );

      final intent = await harness.intents.beaconHierarchyStatusChanged(
        destinationBeaconId: 'B-target',
        messageId: 'R-msg',
        direction: BeaconHierarchyDeliveryDirection.child,
        toStatus: BeaconStatus.closed,
        occurredAt: DateTime.utc(2026, 3, 1),
        sourceEventKey: 'hierarchy:HE-aud:B-target',
        sourceDeleted: false,
        actorUserId: actor,
      );

      final recipientIds = intent.recipients.map((r) => r.recipientId).toSet();
      expect(recipientIds, isNot(contains(actor)));
      expect(recipientIds, isNot(contains(blocked)));
      expect(recipientIds, contains('U-author'));
    });
  });

  group('BeaconHierarchyDeliverySafeError', () {
    test('classify maps injected failures to closed safe codes', () {
      expect(
        BeaconHierarchyDeliverySafeError.classify(
          StateError('NoticeInsertFailure injected'),
        ),
        BeaconHierarchyDeliverySafeError.unknown,
      );
      expect(
        BeaconHierarchyDeliverySafeError.classify(
          StateError('AttentionDispatchFailure injected'),
        ),
        BeaconHierarchyDeliverySafeError.unknown,
      );
      expect(
        BeaconHierarchyDeliverySafeError.retryDelayForAttemptCount(1),
        const Duration(seconds: 5),
      );
      // 5s doubling per attempt reaches the 1-hour cap at attempt 11
      // (5 * 2^9 = 2560s at attempt 10, still under the cap); attempt 20
      // proves the cap holds well beyond that, not just at the boundary.
      expect(
        BeaconHierarchyDeliverySafeError.retryDelayForAttemptCount(20),
        const Duration(seconds: 3600),
      );
    });
  });
}
