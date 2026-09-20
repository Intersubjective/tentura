@Tags(['pg'])
library;

import 'dart:async';

import 'package:postgres/postgres.dart';
import 'package:test/test.dart';

import 'package:tentura_server/data/repository/attention_cutover_repository.dart';
import 'package:tentura_server/data/repository/attention_reconciliation_repository.dart';
import 'package:tentura_server/domain/attention/attention_cutover_models.dart';
import 'package:tentura_server/domain/port/attention_cutover_port.dart';
import 'package:tentura_server/domain/use_case/attention_cutover_case.dart';

import '../../support/disposable_pg_target.dart';

/// U18b gate 1 — legacy obligation identity.
///
/// A live obligation with a NULL `logical_task_key` is invisible to
/// reconciliation: its CTEs require a non-null key, which is why U17d shows
/// the user `unrepairableObligationCount` instead of pretending. This pass
/// gives a key to the rows whose identity is **provable from what is stored**,
/// and leaves every other row exactly as it found it.
///
/// So the cases are three, not one:
///
/// 1. a row whose identity is derivable → keyed, at generation 1;
/// 2. a row whose identity is **not** derivable → untouched, still counted;
/// 3. a row that would **collide** with another live row on the same key →
///    untouched, still counted.
///
/// Case 2 is the one that matters. A wrong key is worse than no key: it makes
/// reconciliation act on the wrong row, and `unrepairableObligationCount`
/// stops reporting a problem that is still there.
Future<void> main() async {
  final target = DisposablePgTarget.fromNamedEnvironment(
    envVarName: 'TENTURA_U18B_KEYS_TEST_DB',
    defaultNamePrefix: 'tentura_test_u18b_keys',
  );
  final reachable = await canReachPostgresAdmin(target);
  final skipReason = reachable
      ? false
      : 'Postgres admin database not reachable for disposable test target';

  group('obligation key backfill', () {
    late DisposablePgWriterSession session;
    late Connection writer;
    late AttentionCutoverRepository repository;
    late AttentionCutoverCase backfill;
    late AttentionReconciliationRepository reconciliation;

    setUpAll(() async {
      if (skipReason != false) return;
      session = await setUpDisposablePgWriter(target: target);
      writer = session.writer;
      final database = openDisposablePgDatabase(target);
      addTearDown(database.close);
      repository = AttentionCutoverRepository(database);
      backfill = AttentionCutoverCase(repository);
      reconciliation = AttentionReconciliationRepository(database);
    });

    tearDownAll(() async {
      if (skipReason != false) return;
      await tearDownDisposablePgWriter(session: session);
    });

    setUp(() async {
      await _resetFixtures(writer);
    });

    test('keys the obligations whose identity is stored', () async {
      await _seed(writer);

      final report = await backfill.cutoverBackfillIfNeeded();

      expect(report.keyedObligations, 2);

      final offer = await _receipt(writer, _derivableOfferId);
      expect(
        offer['logical_task_key'],
        'v1|helpOfferSubmitted|$_beaconId|$_helperId|$_viewerId',
        reason: 'the key is the policy formula over facts the row itself '
            'carries, not a shape invented here',
      );
      expect(
        offer['lifecycle_generation'],
        1,
        reason: 'the generation is not historically derivable; 1 is what a '
            'single live row for a task can honestly claim',
      );

      final review = await _receipt(writer, _derivableReviewId);
      expect(
        review['logical_task_key'],
        'v1|reviewOpened|$_beaconId|$_beaconId|$_viewerId',
        reason: 'reviewOpened varies its generations over the Request',
      );
      expect(review['lifecycle_generation'], 1);
    });

    // The case a careless widening of the derivability predicate gets wrong.
    // Every one of these rows *looks* like an obligation whose key could be
    // guessed; none of them proves it.
    test('leaves an undecidable obligation exactly as it was', () async {
      await _seed(writer);
      final before = <String, Map<String, Object?>>{
        for (final id in _undecidable) id: await _receipt(writer, id),
      };

      await backfill.cutoverBackfillIfNeeded();

      for (final id in _undecidable) {
        final after = await _receipt(writer, id);
        expect(
          after['logical_task_key'],
          isNull,
          reason: '$id: its identity is not provable from what is stored, and '
              'a guessed key points reconciliation at the wrong task',
        );
        expect(after['lifecycle_generation'], isNull);
        expect(after, before[id], reason: '$id: nothing else moved either');
      }
    });

    test('leaves a would-be duplicate unkeyed rather than colliding', () async {
      await _seed(writer);

      await backfill.cutoverBackfillIfNeeded();

      // Two legacy rows derive the same key. The first takes it; the second
      // cannot, because `notification_outbox__live_logical_task` admits one
      // live row per task and the second is no more the real one than the
      // first.
      expect(
        (await _receipt(writer, _duplicateOfferId))['logical_task_key'],
        isNull,
        reason: 'a second live row on one task is the collision the unique '
            'index exists for; keying it would be a database error at best '
            'and a merged pair of distinct tasks at worst',
      );
      // And the row that would collide with an obligation keyed by the new
      // dispatch path, not with another legacy one.
      expect(
        (await _receipt(writer, _collidesWithLiveId))['logical_task_key'],
        isNull,
      );
      expect(
        (await _receipt(writer, _alreadyKeyedId))['logical_task_key'],
        'v1|helpOfferSubmitted|$_otherBeaconId|$_helperId|$_viewerId',
        reason: 'the live keyed row keeps its key and its generation',
      );
      expect((await _receipt(writer, _alreadyKeyedId))['lifecycle_generation'],
          4);
    });

    // U17d shows this number to the user. It must fall by exactly what was
    // repaired and keep reporting what was not.
    test('unrepairableObligationCount falls by what was repaired', () async {
      await _seed(writer);

      final before = await reconciliation.countUnkeyedLiveObligations(
        accountId: _viewerId,
      );
      expect(before, _undecidable.length + 4);

      await backfill.cutoverBackfillIfNeeded();

      final after = await reconciliation.countUnkeyedLiveObligations(
        accountId: _viewerId,
      );
      expect(
        after,
        before - 2,
        reason: 'the two derivable rows left the count and everything else '
            'stayed in it — the honest answer the user already sees',
      );
    });

    // Why the UPDATE repeats `logical_task_key IS NULL` instead of trusting
    // the candidate list. The candidates are read from the batch's snapshot,
    // so a row can be keyed by the dispatch path while the UPDATE waits on
    // its lock; Postgres re-evaluates the UPDATE's own WHERE when the lock is
    // released, and that is the only chance to lose this race honestly.
    // Overwriting would replace a real generation with 1 and repoint
    // reconciliation at a task the write path had already identified.
    test('an obligation keyed mid-batch is not re-keyed', () async {
      await _seed(writer);

      final rival = await Connection.open(
        target.databaseEnv.pgEndpoint,
        settings: target.databaseEnv.pgEndpointSettings,
      );
      addTearDown(rival.close);
      final release = Completer<void>();
      final held = Completer<void>();
      final racing = rival.runTx((tx) async {
        await tx.execute(
          'SELECT id FROM public.notification_outbox '
          "WHERE id = '$_derivableOfferId' FOR UPDATE",
        );
        held.complete();
        await release.future;
        await tx.execute(
          'UPDATE public.notification_outbox '
          "SET logical_task_key = '$_rivalKey', lifecycle_generation = 7 "
          "WHERE id = '$_derivableOfferId'",
        );
      });
      await held.future;

      final pass = backfill.cutoverBackfillIfNeeded();
      await _awaitLockWaiters(writer, count: 1);
      release.complete();
      await racing;
      final report = await pass;

      expect(
        report.keyedObligations,
        2,
        reason: 'the review obligation, and the second legacy offer — whose '
            'collision disappeared when the rival claimed a different key',
      );
      expect(
        (await _receipt(writer, _duplicateOfferId))['logical_task_key'],
        'v1|helpOfferSubmitted|$_beaconId|$_helperId|$_viewerId',
        reason: 'the duplicate guard asks the database, not a plan made '
            'before the batch started',
      );
      final row = await _receipt(writer, _derivableOfferId);
      expect(row['logical_task_key'], _rivalKey);
      expect(
        row['lifecycle_generation'],
        7,
        reason: 'a real generation is not replaced by this pass\'s 1',
      );
    });

    test('an interrupted key pass resumed produces the one-shot state',
        () async {
      await _seed(writer);

      final interrupted = _FailAfterKeyBatches(repository, failAfter: 1);
      await expectLater(
        AttentionCutoverCase(interrupted).cutoverBackfillIfNeeded(batchSize: 1),
        throwsA(isA<_InjectedInterruption>()),
      );

      final progress = await _progress(writer);
      expect(progress['obligation_key_completed_at'], isNull);
      expect(progress['obligation_key_cursor'], isNotNull);
      final fixedInstant = progress['cutover_at'];
      final keyedFirst = await _keyedIds(writer);
      expect(keyedFirst, isNot(contains(_derivableReviewId)),
          reason: 'one batch of one row did not reach the second obligation');

      final resumed = await backfill.cutoverBackfillIfNeeded(batchSize: 1);
      expect(resumed.alreadyComplete, isFalse);
      final afterResume = await _snapshot(writer);
      expect((await _progress(writer))['cutover_at'], fixedInstant);
      expect(
        (await _progress(writer))['obligation_key_completed_at'],
        isNotNull,
      );

      final again = await backfill.cutoverBackfillIfNeeded(batchSize: 1);
      expect(again.alreadyComplete, isTrue);
      expect(again.keyedObligations, 0);
      expect(await _snapshot(writer), afterResume);

      await _resetFixtures(writer);
      await _seed(writer);
      final oneShot = await backfill.cutoverBackfillIfNeeded();
      expect(oneShot.keyedObligations, 2);
      expect(await _snapshot(writer), afterResume);
    });
  }, skip: skipReason);
}

/// Runs [failAfter] real key batches, then refuses another.
final class _FailAfterKeyBatches implements AttentionCutoverPort {
  _FailAfterKeyBatches(this._inner, {required this.failAfter});

  final AttentionCutoverPort _inner;
  final int failAfter;
  int _batches = 0;

  @override
  Future<DateTime> fixCutoverInstant() => _inner.fixCutoverInstant();

  @override
  Future<DateTime?> readCutoverInstant() => _inner.readCutoverInstant();

  @override
  Future<bool> isLegacySeenComplete() => _inner.isLegacySeenComplete();

  @override
  Future<AttentionCutoverBatch> convertLegacySeenBatch({
    required int batchSize,
  }) => _inner.convertLegacySeenBatch(batchSize: batchSize);

  @override
  Future<void> markLegacySeenComplete() => _inner.markLegacySeenComplete();

  @override
  Future<bool> isObligationKeyComplete() => _inner.isObligationKeyComplete();

  @override
  Future<AttentionCutoverBatch> keyLegacyObligationBatch({
    required int batchSize,
  }) async {
    if (_batches >= failAfter) throw const _InjectedInterruption();
    _batches++;
    return _inner.keyLegacyObligationBatch(batchSize: batchSize);
  }

  @override
  Future<void> markObligationKeyComplete() =>
      _inner.markObligationKeyComplete();

  @override
  Future<bool> isPlacementComplete() => _inner.isPlacementComplete();

  @override
  Future<AttentionCutoverBatch> demoteLegacyPlacementBatch({
    required int batchSize,
  }) => _inner.demoteLegacyPlacementBatch(batchSize: batchSize);

  @override
  Future<void> markPlacementComplete() => _inner.markPlacementComplete();
}

final class _InjectedInterruption implements Exception {
  const _InjectedInterruption();
}

/// The key the dispatch path wrote while the batch was waiting. Deliberately
/// not the key this pass would have derived: what must survive is the other
/// writer's answer, whatever it is.
const _rivalKey = 'v1|helpOfferSubmitted|rival|rival|Uu18b0001';

const _viewerId = 'Uu18b0001';
const _helperId = 'Uu18b0002';

// Every undecidable fixture names a **different** helper, so its derived key
// would be unique. Sharing one helper would have let the duplicate guard
// absorb a loosened derivability predicate, and the case-2 tests would have
// passed for a reason that has nothing to do with what they assert.
const _undecidableHelpers = {
  _noOccurrenceId: 'Uu18b0003',
  _mismatchedOccurrenceId: 'Uu18b0004',
  _collapsedId: 'Uu18b0005',
  _unkeyableFamilyId: 'Uu18b0006',
  _postCutoverId: 'Uu18b0007',
};
const _beaconId = 'Bu18b00001';
const _otherBeaconId = 'Bu18b00002';

// Ordered by id, because the pass walks ids and the first row to derive a key
// is the one that takes it.
const _derivableOfferId = 'Nu18b01';
const _derivableReviewId = 'Nu18b02';
const _noOccurrenceId = 'Nu18b03';
const _mismatchedOccurrenceId = 'Nu18b04';
const _collapsedId = 'Nu18b05';
const _unkeyableFamilyId = 'Nu18b06';
const _postCutoverId = 'Nu18b07';
const _settledId = 'Nu18b08';
const _duplicateOfferId = 'Nu18b09';
const _alreadyKeyedId = 'Nu18b10';
const _collidesWithLiveId = 'Nu18b11';

/// Every row that must come out of the pass unchanged and still counted.
const _undecidable = [
  _noOccurrenceId,
  _mismatchedOccurrenceId,
  _collapsedId,
  _unkeyableFamilyId,
  _postCutoverId,
];

Future<void> _resetFixtures(Connection writer) async {
  await writer.execute('''
TRUNCATE TABLE
  public.attention_cutover,
  public.attention_occurrence,
  public.notification_outbox,
  public.beacon,
  public."user"
CASCADE
''');
  for (final id in [_viewerId, _helperId, ..._undecidableHelpers.values]) {
    await writer.execute(
      Sql.named(
        'INSERT INTO public."user" (id, display_name, public_key) '
        'VALUES (@id, @id, @key)',
      ),
      parameters: {'id': id, 'key': '$id-key'},
    );
  }
  for (final id in [_beaconId, _otherBeaconId]) {
    await writer.execute(
      Sql.named(
        'INSERT INTO public.beacon (id, user_id, title, description, status) '
        "VALUES (@id, @userId, 'Request', 'Request', 0)",
      ),
      parameters: {'id': id, 'userId': _viewerId},
    );
  }
}

Future<void> _seed(Connection writer) async {
  // 1. Derivable: the occurrence and the row's own payload agree on the event
  //    family, the Request and the helper.
  await _occurrence(writer, id: 'AOu18b01', eventType: 'helpOfferSubmitted');
  await _obligation(
    writer,
    id: _derivableOfferId,
    occurrenceId: 'AOu18b01',
    eventType: 'helpOfferSubmitted',
    reasons: ['authorOfBeacon'],
    targetEntityId: _helperId,
  );

  await _occurrence(writer, id: 'AOu18b02', eventType: 'reviewOpened');
  await _obligation(
    writer,
    id: _derivableReviewId,
    occurrenceId: 'AOu18b02',
    eventType: 'reviewOpened',
    reasons: ['reviewParticipant'],
  );

  // 2. Undecidable, five ways.
  //
  // No occurrence at all: the payload alone is one witness, and a collapsed
  // legacy row's payload was rewritten by whatever event landed last.
  await _obligation(
    writer,
    id: _noOccurrenceId,
    eventType: 'helpOfferSubmitted',
    reasons: ['authorOfBeacon'],
    targetEntityId: _undecidableHelpers[_noOccurrenceId],
  );
  // The occurrence and the payload disagree — exactly the repointed-collapse
  // shape, and there is no way to tell which of the two is the row.
  await _occurrence(writer, id: 'AOu18b04', eventType: 'helpOfferSubmitted');
  await _obligation(
    writer,
    id: _mismatchedOccurrenceId,
    occurrenceId: 'AOu18b04',
    eventType: 'requestStatusChanged',
    reasons: ['authorOfBeacon'],
    targetEntityId: _undecidableHelpers[_mismatchedOccurrenceId],
  );
  // Both witnesses agree, but the row stands for more than one event, and the
  // others are not this one.
  await _occurrence(writer, id: 'AOu18b05', eventType: 'helpOfferSubmitted');
  await _obligation(
    writer,
    id: _collapsedId,
    occurrenceId: 'AOu18b05',
    eventType: 'helpOfferSubmitted',
    reasons: ['authorOfBeacon'],
    targetEntityId: _undecidableHelpers[_collapsedId],
    collapsedCount: 3,
  );
  // An obligation family that declares no logical-task subject. The policy
  // refuses to invent one, and so does this.
  await _occurrence(writer, id: 'AOu18b06', eventType: 'blockerOpened');
  await _obligation(
    writer,
    id: _unkeyableFamilyId,
    occurrenceId: 'AOu18b06',
    eventType: 'blockerOpened',
    reasons: ['targetOfAsk'],
    targetEntityId: _undecidableHelpers[_unkeyableFamilyId],
  );
  // Written after the cutover: never legacy, and none of this pass's business.
  await _occurrence(writer, id: 'AOu18b07', eventType: 'helpOfferSubmitted');
  await _obligation(
    writer,
    id: _postCutoverId,
    occurrenceId: 'AOu18b07',
    eventType: 'helpOfferSubmitted',
    reasons: ['authorOfBeacon'],
    targetEntityId: _undecidableHelpers[_postCutoverId],
    createdAt: '2099-01-01T00:00:00Z',
  );

  // 3. Settled: historical, not a live obligation, and outside the count.
  await _occurrence(writer, id: 'AOu18b08', eventType: 'helpOfferSubmitted');
  await _obligation(
    writer,
    id: _settledId,
    occurrenceId: 'AOu18b08',
    eventType: 'helpOfferSubmitted',
    reasons: ['authorOfBeacon'],
    targetEntityId: _helperId,
    settlementKind: 'superseded',
  );

  // 4. Collisions. Two legacy rows deriving one key, and a legacy row deriving
  //    the key a live keyed obligation already holds.
  await _occurrence(writer, id: 'AOu18b09', eventType: 'helpOfferSubmitted');
  await _obligation(
    writer,
    id: _duplicateOfferId,
    occurrenceId: 'AOu18b09',
    eventType: 'helpOfferSubmitted',
    reasons: ['authorOfBeacon'],
    targetEntityId: _helperId,
  );
  await _occurrence(writer, id: 'AOu18b10', eventType: 'helpOfferSubmitted');
  await _obligation(
    writer,
    id: _alreadyKeyedId,
    occurrenceId: 'AOu18b10',
    eventType: 'helpOfferSubmitted',
    reasons: ['authorOfBeacon'],
    targetEntityId: _helperId,
    beaconId: _otherBeaconId,
    logicalTaskKey:
        'v1|helpOfferSubmitted|$_otherBeaconId|$_helperId|$_viewerId',
    lifecycleGeneration: 4,
  );
  await _occurrence(writer, id: 'AOu18b11', eventType: 'helpOfferSubmitted');
  await _obligation(
    writer,
    id: _collidesWithLiveId,
    occurrenceId: 'AOu18b11',
    eventType: 'helpOfferSubmitted',
    reasons: ['authorOfBeacon'],
    targetEntityId: _helperId,
    beaconId: _otherBeaconId,
  );
}

Future<void> _occurrence(
  Connection writer, {
  required String id,
  required String eventType,
}) => writer.execute(
  Sql.named('''
INSERT INTO public.attention_occurrence
  (id, source_event_key, event_type, actor_user_id, immutable_payload)
VALUES (@id, @id, @eventType, @actorId, '{}'::jsonb)
'''),
  parameters: {'id': id, 'eventType': eventType, 'actorId': _helperId},
);

Future<void> _obligation(
  Connection writer, {
  required String id,
  required String eventType,
  required List<String> reasons,
  String? occurrenceId,
  String? targetEntityId,
  String beaconId = _beaconId,
  String createdAt = '2026-09-16T10:00:00Z',
  int collapsedCount = 1,
  String? settlementKind,
  String? logicalTaskKey,
  int? lifecycleGeneration,
}) async {
  final payload = <String, String>{
    'eventType': eventType,
    'beaconId': beaconId,
    if (targetEntityId != null) 'targetEntityId': targetEntityId,
  };
  final payloadJson = [
    '{',
    payload.entries.map((e) => '"${e.key}":"${e.value}"').join(','),
    '}',
  ].join();
  await writer.execute(
    Sql.named('''
INSERT INTO public.notification_outbox (
  id, account_id, category, kind, priority,
  title, body, action_url, dedup_key, created_at, collapsed_count,
  beacon_id, source_event_key, occurrence_id, target_entity_id,
  destination_kind, presentation_key, presentation_payload,
  suppression_class, access_policy,
  requires_action, attention_thread_key, settlement_kind, settled_at,
  logical_task_key, lifecycle_generation
) VALUES (
  @id, @accountId, 'coordination', @eventType, 'normal',
  'Title', 'Body', '/attention', @dedupKey,
  CAST(@createdAt AS timestamptz), @collapsedCount,
  @beaconId, @sourceEventKey, CAST(@occurrenceId AS text), CAST(@targetEntityId AS text),
  'beacon', 'request_status_changed', CAST(@payload AS jsonb),
  'mandatory', 'beacon_content',
  true, @threadKey, CAST(@settlementKind AS text),
  CASE WHEN CAST(@settlementKind AS text) IS NULL THEN NULL ELSE now() END,
  CAST(@logicalTaskKey AS text), CAST(@lifecycleGeneration AS integer)
)
'''),
    parameters: {
      'id': id,
      'accountId': _viewerId,
      'eventType': eventType,
      'dedupKey': 'dedup-$id',
      'createdAt': createdAt,
      'collapsedCount': collapsedCount,
      'beaconId': beaconId,
      'sourceEventKey': 'source-$id',
      'occurrenceId': occurrenceId,
      'targetEntityId': targetEntityId,
      'payload': payloadJson,
      'threadKey': 'v1|$eventType|$id|$_viewerId',
      'settlementKind': settlementKind,
      'logicalTaskKey': logicalTaskKey,
      'lifecycleGeneration': lifecycleGeneration,
    },
  );
  if (occurrenceId != null) {
    await writer.execute(
      Sql.named('''
INSERT INTO public.attention_occurrence_recipient
  (occurrence_id, account_id, reasons, role_facts, collapse_key,
   channel_eligible)
VALUES (@occurrenceId, @accountId, CAST(@reasons AS jsonb), '{}'::jsonb,
        @collapseKey, false)
'''),
      parameters: {
        'occurrenceId': occurrenceId,
        'accountId': _viewerId,
        'reasons': '[${reasons.map((r) => '"$r"').join(',')}]',
        'collapseKey': 'collapse-$id',
      },
    );
  }
}

/// Waits until [count] backends are blocked on a lock, so the race is a
/// barrier rather than whatever the scheduler happened to do.
Future<void> _awaitLockWaiters(
  Connection writer, {
  required int count,
}) async {
  final deadline = DateTime.now().add(const Duration(seconds: 20));
  while (DateTime.now().isBefore(deadline)) {
    final rows = await writer.execute(
      'SELECT count(*) FROM pg_stat_activity '
      "WHERE wait_event_type = 'Lock' AND state = 'active' "
      'AND datname = current_database()',
    );
    if ((rows.first.first! as int) >= count) return;
    await Future<void>.delayed(const Duration(milliseconds: 25));
  }
  throw StateError('timed out waiting for $count blocked backends');
}

Future<Map<String, Object?>> _receipt(Connection writer, String id) async {
  final rows = await writer.execute(
    Sql.named(
      'SELECT logical_task_key, lifecycle_generation, settlement_kind, '
      '       placement, cleared_at '
      'FROM public.notification_outbox WHERE id = @id',
    ),
    parameters: {'id': id},
  );
  return {
    'logical_task_key': rows.first[0],
    'lifecycle_generation': rows.first[1],
    'settlement_kind': rows.first[2],
    'placement': rows.first[3],
    'cleared_at': rows.first[4],
  };
}

Future<List<String>> _keyedIds(Connection writer) async {
  final rows = await writer.execute(
    'SELECT id FROM public.notification_outbox '
    'WHERE logical_task_key IS NOT NULL ORDER BY id',
  );
  return [for (final row in rows) row.first! as String];
}

Future<Map<String, Object?>> _progress(Connection writer) async {
  final rows = await writer.execute(
    'SELECT cutover_at, obligation_key_cursor, obligation_key_completed_at '
    'FROM public.attention_cutover WHERE id',
  );
  return {
    'cutover_at': rows.first[0],
    'obligation_key_cursor': rows.first[1],
    'obligation_key_completed_at': rows.first[2],
  };
}

Future<List<List<Object?>>> _snapshot(Connection writer) async {
  final rows = await writer.execute(
    'SELECT id, logical_task_key, lifecycle_generation, settlement_kind, '
    '       placement, cleared_at, clear_reason '
    'FROM public.notification_outbox ORDER BY id',
  );
  return [for (final row in rows) row.toList()];
}
