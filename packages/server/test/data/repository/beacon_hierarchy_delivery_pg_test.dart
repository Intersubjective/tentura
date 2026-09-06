@Tags(['pg'])
library;

import 'package:injectable/injectable.dart' show Environment;
import 'package:logging/logging.dart';
import 'package:mockito/mockito.dart';
import 'package:postgres/postgres.dart';
import 'package:test/test.dart';
import 'package:tentura_root/domain/entity/beacon_hierarchy_delivery_direction.dart';
import 'package:tentura_root/domain/entity/beacon_hierarchy_event.dart';
import 'package:tentura_root/domain/entity/beacon_status.dart';

import 'package:tentura_server/consts/beacon_hierarchy_consts.dart';
import 'package:tentura_server/consts/beacon_hierarchy_delivery_consts.dart';
import 'package:tentura_server/data/repository/attention_dispatch_repository.dart';
import 'package:tentura_server/data/repository/beacon_access_repository.dart';
import 'package:tentura_server/data/repository/beacon_hierarchy_outbox_repository.dart';
import 'package:tentura_server/data/repository/beacon_room_notification_context_repository.dart';
import 'package:tentura_server/data/repository/beacon_room_repository.dart';
import 'package:tentura_server/data/repository/commitment_repository.dart';
import 'package:tentura_server/data/repository/help_offer_repository.dart';
import 'package:tentura_server/data/repository/mutating_unit_of_work.dart';
import 'package:tentura_server/data/repository/mock/invite_seed_prompt_repository_mock.dart';
import 'package:tentura_server/data/repository/user_repository.dart';
import 'package:tentura_server/domain/attention/attention_models.dart';
import 'package:tentura_server/domain/port/attention_dispatch_port.dart';
import 'package:tentura_server/domain/port/beacon_hierarchy_outbox_port.dart';
import 'package:tentura_server/domain/port/invite_genealogy_repository_port.dart';
import 'package:tentura_server/domain/port/trust_evidence_repository_port.dart';
import 'package:tentura_server/domain/use_case/attention_intent_case.dart';
import 'package:tentura_server/domain/use_case/beacon_hierarchy_delivery_case.dart';
import 'package:tentura_server/domain/use_case/transactional_attention_case.dart';
import 'package:tentura_server/env.dart';

import '../../support/beacon_hierarchy_fixture.dart';
import '../../support/fake_user_block_repository.dart';
import 'beacon_hierarchy_pg_helpers.dart';

final class _NoopTrustEvidenceRepository extends Fake
    implements TrustEvidenceRepositoryPort {}

final class _NoopInviteGenealogyRepository extends Fake
    implements InviteGenealogyRepositoryPort {}

final class _ThrowingAttentionDispatch implements AttentionDispatchPort {
  _ThrowingAttentionDispatch(this._inner);

  final AttentionDispatchPort _inner;
  var failNextRecord = false;
  int recordCalls = 0;

  @override
  Future<void> record(AttentionDispatchIntent intent) async {
    recordCalls++;
    if (failNextRecord) {
      failNextRecord = false;
      throw StateError('AttentionDispatchFailure injected');
    }
    await _inner.record(intent);
  }
}

final class _FailingNoticeOutbox implements BeaconHierarchyOutboxPort {
  _FailingNoticeOutbox(this._inner);

  final BeaconHierarchyOutboxPort _inner;
  var failNextNoticeInsert = false;

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
    if (failNextNoticeInsert) {
      failNextNoticeInsert = false;
      throw StateError('NoticeInsertFailure injected');
    }
    return _inner.insertHierarchyLifecycleNotice(
      eventId: eventId,
      targetBeaconId: targetBeaconId,
      direction: direction,
      toStatus: toStatus,
      occurredAt: occurredAt,
      noticeBody: noticeBody,
      sourceDeleted: sourceDeleted,
    );
  }

  @override
  Future<BeaconHierarchyEvent> recordEvent({
    required String sourceBeaconId,
    required BeaconStatus fromStatus,
    required BeaconStatus toStatus,
    required DateTime occurredAt,
    String? actorUserId,
  }) => _inner.recordEvent(
    sourceBeaconId: sourceBeaconId,
    fromStatus: fromStatus,
    toStatus: toStatus,
    occurredAt: occurredAt,
    actorUserId: actorUserId,
  );

  @override
  Future<void> insertDeliveryTargets({
    required BeaconHierarchyEvent event,
    required List<BeaconHierarchyDeliveryTarget> targets,
  }) => _inner.insertDeliveryTargets(event: event, targets: targets);

  @override
  Future<void> insertTopologyDeliveryTargets({
    required String sourceBeaconId,
    required String eventId,
  }) => _inner.insertTopologyDeliveryTargets(
    sourceBeaconId: sourceBeaconId,
    eventId: eventId,
  );

  @override
  Future<List<BeaconHierarchyDeliveryTarget>> claimDueDeliveries({
    required String leaseOwner,
    required DateTime now,
    required int limit,
  }) => _inner.claimDueDeliveries(leaseOwner: leaseOwner, now: now, limit: limit);

  @override
  Future<BeaconHierarchyEvent?> loadEvent(String eventId) =>
      _inner.loadEvent(eventId);

  @override
  Future<BeaconStatus?> loadDestinationBeaconStatus(String targetBeaconId) =>
      _inner.loadDestinationBeaconStatus(targetBeaconId);

  @override
  Future<void> scheduleDeliveryRetry({
    required String eventId,
    required String targetBeaconId,
    required String leaseOwner,
    required DateTime now,
    required int attemptCount,
    required String safeErrorCode,
  }) => _inner.scheduleDeliveryRetry(
    eventId: eventId,
    targetBeaconId: targetBeaconId,
    leaseOwner: leaseOwner,
    now: now,
    attemptCount: attemptCount,
    safeErrorCode: safeErrorCode,
  );

  @override
  Future<bool> operatorParkPoisonedDelivery({
    required String eventId,
    required String targetBeaconId,
  }) => _inner.operatorParkPoisonedDelivery(
    eventId: eventId,
    targetBeaconId: targetBeaconId,
  );

  @override
  Future<int?> loadDeliveryAttemptCount({
    required String eventId,
    required String targetBeaconId,
  }) => _inner.loadDeliveryAttemptCount(
    eventId: eventId,
    targetBeaconId: targetBeaconId,
  );

  @override
  Future<void> markDeliveryDelivered({
    required String eventId,
    required String targetBeaconId,
    required String leaseOwner,
    String? noticeMessageId,
  }) => _inner.markDeliveryDelivered(
    eventId: eventId,
    targetBeaconId: targetBeaconId,
    leaseOwner: leaseOwner,
    noticeMessageId: noticeMessageId,
  );

  @override
  Future<void> markDeliverySuppressed({
    required String eventId,
    required String targetBeaconId,
    required String leaseOwner,
  }) => _inner.markDeliverySuppressed(
    eventId: eventId,
    targetBeaconId: targetBeaconId,
    leaseOwner: leaseOwner,
  );

  @override
  Future<void> markDeliveryParked({
    required String eventId,
    required String targetBeaconId,
    required String leaseOwner,
    required String safeErrorCode,
  }) => _inner.markDeliveryParked(
    eventId: eventId,
    targetBeaconId: targetBeaconId,
    leaseOwner: leaseOwner,
    safeErrorCode: safeErrorCode,
  );
}

Future<void> _cleanupDeliveryArtifacts(Connection writer) async {
  await writer.execute(
    r'''
DELETE FROM public.attention_channel_delivery
WHERE occurrence_id IN (
  SELECT id FROM public.attention_occurrence WHERE source_event_key LIKE 'hierarchy:%'
)''',
  );
  await writer.execute(
    r'''
DELETE FROM public.notification_outbox
WHERE occurrence_id IN (
  SELECT id FROM public.attention_occurrence WHERE source_event_key LIKE 'hierarchy:%'
)''',
  );
  await writer.execute(
    r'''
DELETE FROM public.attention_occurrence_recipient
WHERE occurrence_id IN (
  SELECT id FROM public.attention_occurrence WHERE source_event_key LIKE 'hierarchy:%'
)''',
  );
  await writer.execute(
    "DELETE FROM public.attention_occurrence WHERE source_event_key LIKE 'hierarchy:%'",
  );
  await writer.execute(
    "DELETE FROM public.beacon_hierarchy_deliveries WHERE event_id LIKE 'HE%'",
  );
  await writer.execute(
    "DELETE FROM public.beacon_hierarchy_events WHERE id LIKE 'HE%'",
  );
  await writer.execute(
    "DELETE FROM public.beacon_room_message WHERE hierarchy_notice_identity LIKE 'hierarchy:%'",
  );
}

Future<BeaconHierarchyEvent> _seedDeliveryTarget({
  required BeaconHierarchyOutboxRepository outbox,
  required String sourceBeaconId,
  required String targetBeaconId,
  required BeaconHierarchyDeliveryDirection direction,
  BeaconStatus fromStatus = BeaconStatus.open,
  BeaconStatus toStatus = BeaconStatus.closed,
  DateTime? occurredAt,
  String? actorUserId,
}) async {
  final event = await outbox.recordEvent(
    sourceBeaconId: sourceBeaconId,
    fromStatus: fromStatus,
    toStatus: toStatus,
    occurredAt: occurredAt ?? DateTime.utc(2026, 6, 1),
    actorUserId: actorUserId,
  );
  await outbox.insertDeliveryTargets(
    event: event,
    targets: [
      BeaconHierarchyDeliveryTarget(
        eventId: event.eventId,
        targetBeaconId: targetBeaconId,
        direction: direction,
      ),
    ],
  );
  return event;
}

Future<void> main() async {
  final reachable = await canConnectBeaconHierarchyPostgres();
  final skipReason = reachable
      ? false
      : 'Postgres admin database not reachable for hierarchy delivery PG test';

  group('BeaconHierarchyDeliveryCase — disposable Postgres', () {
    late BeaconHierarchyDisposablePgTarget target;
    late Connection writer;
    late BeaconHierarchyFixture fixture;
    late BeaconHierarchyOutboxRepository outbox;
    late _ThrowingAttentionDispatch throwingDispatch;
    late AttentionIntentCase attentionIntents;
    late BeaconHierarchyDeliveryCase delivery;
    late FakeUserBlockRepository userBlocks;

    setUpAll(() async {
      if (skipReason != false) {
        return;
      }
      target = BeaconHierarchyDisposablePgTarget.fromEnvironment();
      await target.recreate();
      final session = await openBeaconHierarchyPgSession(target);
      writer = session.writer;
      fixture = BeaconHierarchyFixture(writer: writer, db: session.db);
      outbox = BeaconHierarchyOutboxRepository(session.db);
      throwingDispatch = _ThrowingAttentionDispatch(
        AttentionDispatchRepository(session.db, Logger('HierarchyDeliveryPg')),
      );
      userBlocks = FakeUserBlockRepository();
      final room = BeaconRoomRepository(session.db);
      attentionIntents = AttentionIntentCase(
        BeaconRoomNotificationContextRepository(
          room,
          session.db,
          HelpOfferRepository(session.db),
          CommitmentRepository(session.db),
        ),
        UserRepository(
          Env(environment: Environment.test),
          session.db,
          _NoopTrustEvidenceRepository(),
          _NoopInviteGenealogyRepository(),
          InviteSeedPromptRepositoryMock(),
        ),
        BeaconAccessRepository(session.db),
        userBlocks,
      );
      delivery = BeaconHierarchyDeliveryCase(
        outbox,
        TransactionalAttentionCase(
          MutatingUnitOfWork(session.db),
          throwingDispatch,
        ),
        attentionIntents,
        env: Env(environment: Environment.test),
        logger: Logger('HierarchyDeliveryPg'),
      );
    });

    setUp(() async {
      if (skipReason != false) {
        return;
      }
      userBlocks.clear();
      throwingDispatch.failNextRecord = false;
      await _cleanupDeliveryArtifacts(writer);
    });

    tearDown(() async {
      if (skipReason != false) {
        return;
      }
      await _cleanupDeliveryArtifacts(writer);
      await fixture.tearDown();
    });

    tearDownAll(() async {
      if (skipReason != false) {
        return;
      }
      await fixture.db.close();
      await writer.close();
      await target.drop();
    });

    BeaconHierarchyDeliveryCase _deliveryWithOutbox(
      BeaconHierarchyOutboxPort port,
    ) =>
        BeaconHierarchyDeliveryCase(
          port,
          TransactionalAttentionCase(
            MutatingUnitOfWork(fixture.db),
            throwingDispatch,
          ),
          attentionIntents,
          env: Env(environment: Environment.test),
          logger: Logger('HierarchyDeliveryPg'),
        );

    Future<Map<String, Object?>> _deliveryRow(
      String eventId,
      String targetBeaconId,
    ) async {
      final rows = await writer.execute(
        Sql.named(r'''
SELECT state, attempt_count, last_safe_error_code, notice_message_id, lease_owner
FROM public.beacon_hierarchy_deliveries
WHERE event_id = @eventId AND target_beacon_id = @target
'''),
        parameters: {'eventId': eventId, 'target': targetBeaconId},
      );
      expect(rows, hasLength(1));
      return {
        'state': rows.single[0],
        'attempt_count': rows.single[1],
        'last_safe_error_code': rows.single[2],
        'notice_message_id': rows.single[3],
        'lease_owner': rows.single[4],
      };
    }

    test('delivers notice, attention occurrence, and marks row delivered', () async {
      await fixture.seedFullTopology();
      await seedPublishedHierarchyTree(writer);
      final event = await _seedDeliveryTarget(
        outbox: outbox,
        sourceBeaconId: BeaconHierarchyTopology.beaconA,
        targetBeaconId: BeaconHierarchyTopology.beaconB,
        direction: BeaconHierarchyDeliveryDirection.ancestor,
        actorUserId: BeaconHierarchyTopology.aliceId,
      );

      await delivery.runDue(workerId: 'worker-1', now: DateTime.timestamp());

      final row = await _deliveryRow(event.eventId, BeaconHierarchyTopology.beaconB);
      expect(row['state'], BeaconHierarchyDeliveryStateWire.delivered);
      expect(row['notice_message_id'], isNotNull);

      final notices = await writer.execute(
        Sql.named(r'''
SELECT author_id, body, system_payload::text
FROM public.beacon_room_message
WHERE hierarchy_notice_identity = @identity
'''),
        parameters: {
          'identity': 'hierarchy:${event.eventId}:${BeaconHierarchyTopology.beaconB}',
        },
      );
      expect(notices, hasLength(1));
      expect(notices.single[0], isNull);
      expect(notices.single[1], contains('2026-06-01'));
      expect(notices.single[1], isNot(contains('Request A')));
      expect(notices.single[2], isNot(contains('Uhier')));

      final occurrences = await writer.execute(
        Sql.named(
          'SELECT count(*) FROM public.attention_occurrence WHERE source_event_key = @key',
        ),
        parameters: {
          'key': 'hierarchy:${event.eventId}:${BeaconHierarchyTopology.beaconB}',
        },
      );
      expect(occurrences.single.first, 1);
    }, skip: skipReason);

    test('replay after delivered commit is idempotent', () async {
      await fixture.seedFullTopology();
      await seedPublishedHierarchyTree(writer);
      final event = await _seedDeliveryTarget(
        outbox: outbox,
        sourceBeaconId: BeaconHierarchyTopology.beaconA,
        targetBeaconId: BeaconHierarchyTopology.beaconB,
        direction: BeaconHierarchyDeliveryDirection.ancestor,
      );

      await delivery.runDue(workerId: 'worker-1', now: DateTime.timestamp());
      await delivery.runDue(workerId: 'worker-1', now: DateTime.timestamp());

      final noticeCount = await writer.execute(
        Sql.named(
          'SELECT count(*) FROM public.beacon_room_message WHERE hierarchy_notice_identity = @identity',
        ),
        parameters: {
          'identity': 'hierarchy:${event.eventId}:${BeaconHierarchyTopology.beaconB}',
        },
      );
      final occurrenceCount = await writer.execute(
        Sql.named(
          'SELECT count(*) FROM public.attention_occurrence WHERE source_event_key = @key',
        ),
        parameters: {
          'key': 'hierarchy:${event.eventId}:${BeaconHierarchyTopology.beaconB}',
        },
      );
      expect(noticeCount.single.first, 1);
      expect(occurrenceCount.single.first, 1);
    }, skip: skipReason);

    test('notice insert failure rolls back and schedules retry', () async {
      await fixture.seedFullTopology();
      await seedPublishedHierarchyTree(writer);
      final failingOutbox = _FailingNoticeOutbox(outbox)..failNextNoticeInsert = true;
      final failingDelivery = _deliveryWithOutbox(failingOutbox);
      final event = await _seedDeliveryTarget(
        outbox: outbox,
        sourceBeaconId: BeaconHierarchyTopology.beaconA,
        targetBeaconId: BeaconHierarchyTopology.beaconB,
        direction: BeaconHierarchyDeliveryDirection.ancestor,
      );

      await failingDelivery.runDue(workerId: 'worker-1', now: DateTime.timestamp());

      final row = await _deliveryRow(event.eventId, BeaconHierarchyTopology.beaconB);
      expect(row['state'], BeaconHierarchyDeliveryStateWire.pending);
      expect(row['last_safe_error_code'], BeaconHierarchyDeliverySafeError.unknown);
      final noticeCount = await writer.execute(
        Sql.named(
          'SELECT count(*) FROM public.beacon_room_message WHERE hierarchy_notice_identity = @identity',
        ),
        parameters: {
          'identity': 'hierarchy:${event.eventId}:${BeaconHierarchyTopology.beaconB}',
        },
      );
      expect(noticeCount.single.first, 0);
    }, skip: skipReason);

    test('attention dispatch failure rolls back notice and schedules retry', () async {
      await fixture.seedFullTopology();
      await seedPublishedHierarchyTree(writer);
      throwingDispatch.failNextRecord = true;
      final event = await _seedDeliveryTarget(
        outbox: outbox,
        sourceBeaconId: BeaconHierarchyTopology.beaconA,
        targetBeaconId: BeaconHierarchyTopology.beaconB,
        direction: BeaconHierarchyDeliveryDirection.ancestor,
      );

      await delivery.runDue(workerId: 'worker-1', now: DateTime.timestamp());

      final row = await _deliveryRow(event.eventId, BeaconHierarchyTopology.beaconB);
      expect(row['state'], BeaconHierarchyDeliveryStateWire.pending);
      expect(row['last_safe_error_code'], BeaconHierarchyDeliverySafeError.unknown);
      final noticeCount = await writer.execute(
        Sql.named(
          'SELECT count(*) FROM public.beacon_room_message WHERE hierarchy_notice_identity = @identity',
        ),
        parameters: {
          'identity': 'hierarchy:${event.eventId}:${BeaconHierarchyTopology.beaconB}',
        },
      );
      expect(noticeCount.single.first, 0);
    }, skip: skipReason);

    test('deleted destination is suppressed without chat or attention', () async {
      await fixture.seedFullTopology();
      await seedPublishedHierarchyTree(writer);
      await writer.execute(
        Sql.named('UPDATE public.beacon SET status = 2 WHERE id = @id'),
        parameters: {'id': BeaconHierarchyTopology.beaconB},
      );
      final event = await _seedDeliveryTarget(
        outbox: outbox,
        sourceBeaconId: BeaconHierarchyTopology.beaconA,
        targetBeaconId: BeaconHierarchyTopology.beaconB,
        direction: BeaconHierarchyDeliveryDirection.ancestor,
      );

      await delivery.runDue(workerId: 'worker-1', now: DateTime.timestamp());

      final row = await _deliveryRow(event.eventId, BeaconHierarchyTopology.beaconB);
      expect(row['state'], BeaconHierarchyDeliveryStateWire.suppressed);
      final noticeCount = await writer.execute(
        Sql.named(
          'SELECT count(*) FROM public.beacon_room_message WHERE hierarchy_notice_identity = @identity',
        ),
        parameters: {
          'identity': 'hierarchy:${event.eventId}:${BeaconHierarchyTopology.beaconB}',
        },
      );
      expect(noticeCount.single.first, 0);
    }, skip: skipReason);

    test('concurrent workers partition due rows without double delivery', () async {
      await fixture.seedFullTopology();
      await seedPublishedHierarchyTree(writer);
      final event1 = await _seedDeliveryTarget(
        outbox: outbox,
        sourceBeaconId: BeaconHierarchyTopology.beaconA,
        targetBeaconId: BeaconHierarchyTopology.beaconB,
        direction: BeaconHierarchyDeliveryDirection.ancestor,
        occurredAt: DateTime.utc(2026, 6, 1),
      );
      final event2 = await _seedDeliveryTarget(
        outbox: outbox,
        sourceBeaconId: BeaconHierarchyTopology.beaconA,
        targetBeaconId: BeaconHierarchyTopology.beaconC,
        direction: BeaconHierarchyDeliveryDirection.ancestor,
        occurredAt: DateTime.utc(2026, 6, 2),
      );

      await Future.wait([
        delivery.runDue(workerId: 'worker-a', now: DateTime.timestamp()),
        delivery.runDue(workerId: 'worker-b', now: DateTime.timestamp()),
      ]);

      final delivered = await writer.execute(
        Sql.named(
          "SELECT count(*) FROM public.beacon_hierarchy_deliveries WHERE state = 'delivered'",
        ),
      );
      expect(delivered.single.first, 2);
      expect(
        (await _deliveryRow(event1.eventId, BeaconHierarchyTopology.beaconB))['state'],
        BeaconHierarchyDeliveryStateWire.delivered,
      );
      expect(
        (await _deliveryRow(event2.eventId, BeaconHierarchyTopology.beaconC))['state'],
        BeaconHierarchyDeliveryStateWire.delivered,
      );
    }, skip: skipReason);

    test('failed predecessor blocks later event for same pair only', () async {
      await fixture.seedFullTopology();
      await seedPublishedHierarchyTree(writer);
      final first = await _seedDeliveryTarget(
        outbox: outbox,
        sourceBeaconId: BeaconHierarchyTopology.beaconA,
        targetBeaconId: BeaconHierarchyTopology.beaconB,
        direction: BeaconHierarchyDeliveryDirection.ancestor,
        occurredAt: DateTime.utc(2026, 6, 1),
      );
      final second = await _seedDeliveryTarget(
        outbox: outbox,
        sourceBeaconId: BeaconHierarchyTopology.beaconA,
        targetBeaconId: BeaconHierarchyTopology.beaconB,
        direction: BeaconHierarchyDeliveryDirection.ancestor,
        occurredAt: DateTime.utc(2026, 6, 2),
        toStatus: BeaconStatus.reviewOpen,
      );
      final unrelated = await _seedDeliveryTarget(
        outbox: outbox,
        sourceBeaconId: BeaconHierarchyTopology.beaconA,
        targetBeaconId: BeaconHierarchyTopology.beaconC,
        direction: BeaconHierarchyDeliveryDirection.ancestor,
        occurredAt: DateTime.utc(2026, 6, 3),
      );

      // A single sweep claims every currently-due row in one batch (first,
      // sorted before unrelated by occurred_at, consumes the injected
      // failure and gets retry-scheduled; second is excluded from the
      // batch entirely because first is still pending for the same pair;
      // unrelated is unaffected and delivers normally in the same sweep).
      throwingDispatch.failNextRecord = true;
      await delivery.runDue(workerId: 'worker-1', now: DateTime.timestamp());

      expect(
        (await _deliveryRow(unrelated.eventId, BeaconHierarchyTopology.beaconC))['state'],
        BeaconHierarchyDeliveryStateWire.delivered,
      );
      final secondAfterFirstSweep = await _deliveryRow(
        second.eventId,
        BeaconHierarchyTopology.beaconB,
      );
      expect(secondAfterFirstSweep['state'], BeaconHierarchyDeliveryStateWire.pending);
      expect(secondAfterFirstSweep['attempt_count'], 0);

      // With first still unresolved (pending, retry-scheduled), a fresh
      // claim must not select second — it stays blocked for this pair
      // specifically, not merely "not yet due".
      final claimedWhileBlocked = await outbox.claimDueDeliveries(
        leaseOwner: 'worker-2',
        now: DateTime.timestamp(),
        limit: 10,
      );
      expect(claimedWhileBlocked.map((t) => t.eventId), isNot(contains(second.eventId)));

      // Simulate the elapsed retry delay (5s initial backoff) rather than a
      // real wall-clock sleep — next_attempt_at only becomes due once this
      // future `now` is passed in.
      final afterRetryDelay = DateTime.timestamp().add(
        const Duration(seconds: 10),
      );
      throwingDispatch.failNextRecord = false;
      await delivery.runDue(workerId: 'worker-3', now: afterRetryDelay);
      await delivery.runDue(workerId: 'worker-4', now: afterRetryDelay);

      expect(
        (await _deliveryRow(first.eventId, BeaconHierarchyTopology.beaconB))['state'],
        BeaconHierarchyDeliveryStateWire.delivered,
      );
      expect(
        (await _deliveryRow(second.eventId, BeaconHierarchyTopology.beaconB))['state'],
        BeaconHierarchyDeliveryStateWire.delivered,
      );
    }, skip: skipReason);

    test('source events for one target deliver in sequence order', () async {
      await fixture.seedFullTopology();
      await seedPublishedHierarchyTree(writer);
      final first = await _seedDeliveryTarget(
        outbox: outbox,
        sourceBeaconId: BeaconHierarchyTopology.beaconA,
        targetBeaconId: BeaconHierarchyTopology.beaconB,
        direction: BeaconHierarchyDeliveryDirection.ancestor,
        occurredAt: DateTime.utc(2026, 6, 1),
        toStatus: BeaconStatus.reviewOpen,
      );
      final second = await _seedDeliveryTarget(
        outbox: outbox,
        sourceBeaconId: BeaconHierarchyTopology.beaconA,
        targetBeaconId: BeaconHierarchyTopology.beaconB,
        direction: BeaconHierarchyDeliveryDirection.ancestor,
        occurredAt: DateTime.utc(2026, 6, 8),
        toStatus: BeaconStatus.closed,
      );

      await delivery.runDue(workerId: 'worker-1', now: DateTime.timestamp());
      await delivery.runDue(workerId: 'worker-1', now: DateTime.timestamp());

      final bodies = await writer.execute(
        Sql.named(r'''
SELECT body
FROM public.beacon_room_message
WHERE hierarchy_notice_identity IN (@first, @second)
ORDER BY body
'''),
        parameters: {
          'first': 'hierarchy:${first.eventId}:${BeaconHierarchyTopology.beaconB}',
          'second': 'hierarchy:${second.eventId}:${BeaconHierarchyTopology.beaconB}',
        },
      );
      expect(bodies.map((r) => r[0]), [
        contains('2026-06-01'),
        contains('2026-06-08'),
      ]);
    }, skip: skipReason);

    test('audience snapshot reflects membership at delivery time', () async {
      await fixture.seedFullTopology();
      await seedPublishedHierarchyTree(writer);
      final event = await _seedDeliveryTarget(
        outbox: outbox,
        sourceBeaconId: BeaconHierarchyTopology.beaconA,
        targetBeaconId: BeaconHierarchyTopology.beaconB,
        direction: BeaconHierarchyDeliveryDirection.ancestor,
        actorUserId: BeaconHierarchyTopology.aliceId,
      );
      await writer.execute(
        Sql.named(r'''
INSERT INTO public.beacon_participant (
  id, beacon_id, user_id, role, status, room_access, created_at, updated_at
) VALUES (
  'Phierlate001', @beacon, @user, 0, 0, 3,
  '2026-01-01T00:00:00Z', '2026-01-01T00:00:00Z'
)
ON CONFLICT DO NOTHING
'''),
        parameters: {
          'beacon': BeaconHierarchyTopology.beaconB,
          'user': BeaconHierarchyTopology.carolId,
        },
      );

      await delivery.runDue(workerId: 'worker-1', now: DateTime.timestamp());

      final recipients = await writer.execute(
        Sql.named(r'''
SELECT account_id
FROM public.attention_occurrence_recipient
WHERE occurrence_id = (
  SELECT id FROM public.attention_occurrence
  WHERE source_event_key = @key
)
'''),
        parameters: {
          'key': 'hierarchy:${event.eventId}:${BeaconHierarchyTopology.beaconB}',
        },
      );
      expect(
        recipients.map((r) => r[0]),
        contains(BeaconHierarchyTopology.carolId),
      );
      expect(
        recipients.map((r) => r[0]),
        isNot(contains(BeaconHierarchyTopology.aliceId)),
      );
    }, skip: skipReason);

    test('actor suppression, watcher channel policy, and blocks are preserved', () async {
      await fixture.seedFullTopology();
      await seedPublishedHierarchyTree(writer);
      await writer.execute(
        Sql.named(r'''
INSERT INTO public.inbox_item (
  user_id, beacon_id, status, forward_count, latest_forward_at, latest_note_preview, rejection_message
) VALUES (@user, @beacon, 1, 0, '2026-01-02T00:00:00Z', '', '')
ON CONFLICT (user_id, beacon_id) DO UPDATE SET status = EXCLUDED.status
'''),
        parameters: {
          'user': BeaconHierarchyTopology.frankId,
          'beacon': BeaconHierarchyTopology.beaconB,
        },
      );
      userBlocks.blockPair(
        BeaconHierarchyTopology.aliceId,
        BeaconHierarchyTopology.bobId,
      );
      final event = await _seedDeliveryTarget(
        outbox: outbox,
        sourceBeaconId: BeaconHierarchyTopology.beaconA,
        targetBeaconId: BeaconHierarchyTopology.beaconB,
        direction: BeaconHierarchyDeliveryDirection.ancestor,
        actorUserId: BeaconHierarchyTopology.aliceId,
      );

      await delivery.runDue(workerId: 'worker-1', now: DateTime.timestamp());

      final recipients = await writer.execute(
        Sql.named(r'''
SELECT account_id, channel_eligible, reasons
FROM public.attention_occurrence_recipient
WHERE occurrence_id = (
  SELECT id FROM public.attention_occurrence
  WHERE source_event_key = @key
)
'''),
        parameters: {
          'key': 'hierarchy:${event.eventId}:${BeaconHierarchyTopology.beaconB}',
        },
      );
      final byId = {
        for (final row in recipients) row[0] as String: row,
      };
      expect(byId.keys, isNot(contains(BeaconHierarchyTopology.aliceId)));
      expect(byId.keys, isNot(contains(BeaconHierarchyTopology.bobId)));
      final watcher = byId[BeaconHierarchyTopology.frankId];
      expect(watcher, isNotNull);
      expect(watcher![1], isFalse);
      expect(watcher[2], contains('inboxStanceHolder'));
    }, skip: skipReason);

    test('claim fencing prevents stale worker from corrupting delivered row', () async {
      await fixture.seedFullTopology();
      await seedPublishedHierarchyTree(writer);
      final event = await _seedDeliveryTarget(
        outbox: outbox,
        sourceBeaconId: BeaconHierarchyTopology.beaconA,
        targetBeaconId: BeaconHierarchyTopology.beaconB,
        direction: BeaconHierarchyDeliveryDirection.ancestor,
      );

      final claimedByA = await outbox.claimDueDeliveries(
        leaseOwner: 'worker-a',
        now: DateTime.timestamp(),
        limit: 1,
      );
      expect(claimedByA, hasLength(1));

      await writer.execute(
        Sql.named(r'''
UPDATE public.beacon_hierarchy_deliveries
SET lease_until = '2000-01-01T00:00:00Z'
WHERE event_id = @eventId AND target_beacon_id = @target
'''),
        parameters: {
          'eventId': event.eventId,
          'target': BeaconHierarchyTopology.beaconB,
        },
      );

      await delivery.runDue(workerId: 'worker-b', now: DateTime.timestamp());
      expect(
        (await _deliveryRow(event.eventId, BeaconHierarchyTopology.beaconB))['state'],
        BeaconHierarchyDeliveryStateWire.delivered,
      );

      await outbox.scheduleDeliveryRetry(
        eventId: event.eventId,
        targetBeaconId: BeaconHierarchyTopology.beaconB,
        leaseOwner: 'worker-a',
        now: DateTime.timestamp(),
        attemptCount: 2,
        safeErrorCode: BeaconHierarchyDeliverySafeError.unknown,
      );

      expect(
        (await _deliveryRow(event.eventId, BeaconHierarchyTopology.beaconB))['state'],
        BeaconHierarchyDeliveryStateWire.delivered,
      );
    }, skip: skipReason);

    test('poison threshold stops ordinary selection and operator park unblocks later events', () async {
      await fixture.seedFullTopology();
      await seedPublishedHierarchyTree(writer);
      final first = await _seedDeliveryTarget(
        outbox: outbox,
        sourceBeaconId: BeaconHierarchyTopology.beaconA,
        targetBeaconId: BeaconHierarchyTopology.beaconB,
        direction: BeaconHierarchyDeliveryDirection.ancestor,
        occurredAt: DateTime.utc(2026, 6, 1),
      );
      final second = await _seedDeliveryTarget(
        outbox: outbox,
        sourceBeaconId: BeaconHierarchyTopology.beaconA,
        targetBeaconId: BeaconHierarchyTopology.beaconB,
        direction: BeaconHierarchyDeliveryDirection.ancestor,
        occurredAt: DateTime.utc(2026, 6, 2),
        toStatus: BeaconStatus.reviewOpen,
      );

      await writer.execute(
        Sql.named(r'''
UPDATE public.beacon_hierarchy_deliveries
SET
  state = 'pending',
  attempt_count = @threshold,
  next_attempt_at = '2000-01-01T00:00:00Z',
  last_safe_error_code = @code
WHERE event_id = @eventId AND target_beacon_id = @target
'''),
        parameters: {
          'threshold': BeaconHierarchyDeliverySafeError.poisonAttemptThreshold,
          'code': BeaconHierarchyDeliverySafeError.attentionDispatchFailed,
          'eventId': first.eventId,
          'target': BeaconHierarchyTopology.beaconB,
        },
      );

      final ordinaryClaim = await outbox.claimDueDeliveries(
        leaseOwner: 'worker-poison',
        now: DateTime.timestamp(),
        limit: 10,
      );
      expect(ordinaryClaim.map((t) => t.eventId), isNot(contains(first.eventId)));

      final parked = await delivery.parkPoisonedDeliveryAsOperator(
        eventId: first.eventId,
        targetBeaconId: BeaconHierarchyTopology.beaconB,
        operatorId: BeaconHierarchyTopology.aliceId,
      );
      expect(parked, isTrue);
      expect(
        (await _deliveryRow(first.eventId, BeaconHierarchyTopology.beaconB))['state'],
        BeaconHierarchyDeliveryStateWire.parked,
      );
      expect(
        (await _deliveryRow(first.eventId, BeaconHierarchyTopology.beaconB))['last_safe_error_code'],
        BeaconHierarchyDeliverySafeError.attentionDispatchFailed,
      );

      await delivery.runDue(workerId: 'worker-after-park', now: DateTime.timestamp());
      expect(
        (await _deliveryRow(second.eventId, BeaconHierarchyTopology.beaconB))['state'],
        BeaconHierarchyDeliveryStateWire.delivered,
      );
    }, skip: skipReason);
  });
}
