@Tags(['pg'])
library;

import 'dart:async';

import 'package:postgres/postgres.dart';
import 'package:test/test.dart';

import 'package:tentura_server/data/repository/attention_cutover_repository.dart';
import 'package:tentura_server/domain/attention/attention_cutover_models.dart';
import 'package:tentura_server/domain/port/attention_cutover_port.dart';
import 'package:tentura_server/domain/use_case/attention_cutover_case.dart';

import '../../support/disposable_pg_target.dart';

/// U18a — the `legacy_seen` backfill.
///
/// The headline acceptance is restartability, and it is asserted against a
/// **real** interruption: the case is handed a port that runs one batch and
/// then throws, the partial state is read back and asserted, and only then is
/// the backfill resumed. Two clean runs would prove nothing — they never
/// exercise the cursor, the NULL guard or the already-fixed instant.
Future<void> main() async {
  final target = DisposablePgTarget.fromNamedEnvironment(
    envVarName: 'TENTURA_U18A_BACKFILL_TEST_DB',
    defaultNamePrefix: 'tentura_test_u18a_backfill',
  );
  final reachable = await canReachPostgresAdmin(target);
  final skipReason = reachable
      ? false
      : 'Postgres admin database not reachable for disposable test target';

  group('legacy_seen backfill', () {
    late DisposablePgWriterSession session;
    late Connection writer;
    late AttentionCutoverRepository repository;
    late AttentionCutoverCase backfill;

    setUpAll(() async {
      if (skipReason != false) return;
      session = await setUpDisposablePgWriter(target: target);
      writer = session.writer;
      final database = openDisposablePgDatabase(target);
      addTearDown(database.close);
      repository = AttentionCutoverRepository(database);
      backfill = AttentionCutoverCase(repository);
    });

    tearDownAll(() async {
      if (skipReason != false) return;
      await tearDownDisposablePgWriter(session: session);
    });

    setUp(() async {
      await _resetFixtures(writer);
    });

    test('converts seen optional receipts and leaves everything else', () async {
      await _seed(writer);

      final report = await backfill.cutoverBackfillIfNeeded();

      expect(report.convertedReceipts, 3);
      expect(report.alreadyComplete, isFalse);
      expect(report.cutoverAt, isNotNull);

      for (final id in _convertible) {
        final row = await _receipt(writer, id);
        expect(row['clear_reason'], 'legacy_seen');
        expect(
          row['cleared_at'],
          row['seen_at'],
          reason: 'the clear instant is the moment the user saw it, not now()',
        );
        expect(
          row['cleared_by_operation_id'],
          isNull,
          reason:
              'legacy_seen was never an explicit sweep: giving it an operation '
              'id would make it undoable and put it in a sweep\'s accounting',
        );
      }

      // The obligation and the already-cleared receipt keep the facts they had.
      final obligation = await _receipt(writer, _obligationId);
      expect(obligation['cleared_at'], isNull);
      expect(obligation['clear_reason'], isNull);

      final alreadyCleared = await _receipt(writer, _alreadyClearedId);
      expect(alreadyCleared['clear_reason'], 'explicit');
      expect(alreadyCleared['cleared_by_operation_id'], _operationId);
      expect(
        (alreadyCleared['cleared_at']! as DateTime).toUtc(),
        DateTime.utc(2026, 9, 17, 8),
        reason: 'a receipt cleared by an operation is not re-stamped',
      );

      // A post-cutover receipt names an occurrence; it is governed by the
      // clear operations, never by this backfill.
      final postCutover = await _receipt(writer, _postCutoverId);
      expect(postCutover['cleared_at'], isNull);
      expect(postCutover['clear_reason'], isNull);

      // Inbox stance is a different axis entirely.
      final dismissed = await writer.execute(
        'SELECT tombstone_dismissed_at FROM public.inbox_item '
        "WHERE user_id = '$_viewerId' AND beacon_id = '$_beaconId'",
      );
      expect(
        (dismissed.first.first! as DateTime).toUtc(),
        DateTime.utc(2026, 9, 10, 9),
        reason: 'a prior tombstone dismissal is not the backfill\'s business',
      );

      // D19: the backfill writes state and replays no delivery.
      final jobs = await writer.execute(
        'SELECT count(*) FROM public.attention_channel_delivery',
      );
      expect(jobs.first.first, 0);
    });

    // The assertion this unit is most afraid of being wrong about. Clearing a
    // receipt the user never saw is attention silently gone, and nothing
    // downstream can recover it.
    test('an unseen optional receipt stays active', () async {
      await _seed(writer);

      await backfill.cutoverBackfillIfNeeded();

      final unseen = await _receipt(writer, _unseenId);
      expect(unseen['seen_at'], isNull);
      expect(
        unseen['cleared_at'],
        isNull,
        reason: 'the user never saw it, so it is still their attention',
      );
      expect(unseen['clear_reason'], isNull);
    });

    // Why the UPDATE repeats the candidate predicate instead of trusting the
    // join. The candidate list is read from the statement's snapshot, so it
    // can name a receipt another writer clears while the UPDATE is waiting on
    // its row lock. Postgres re-evaluates the UPDATE's own WHERE after the
    // lock is released — which is the guard's only chance to fire, and the
    // difference between losing that race and overwriting a real clear.
    test('a receipt cleared mid-statement is not re-stamped', () async {
      await _insertReceipt(
        writer,
        id: _convertible.first,
        seenAt: '2026-09-16T07:00:00Z',
      );
      await writer.execute(
        Sql.named(
          'INSERT INTO public.attention_clear_operation '
          '(id, account_id, surface, status) '
          "VALUES (@id, @accountId, 'explicit', 'complete')",
        ),
        parameters: {'id': _operationId, 'accountId': _viewerId},
      );

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
          "WHERE id = '${_convertible.first}' FOR UPDATE",
        );
        held.complete();
        await release.future;
        // The user clears it themselves, for real, while the batch waits.
        await tx.execute(
          'UPDATE public.notification_outbox '
          "SET cleared_at = '2026-09-19T11:00:00Z', "
          "    clear_reason = 'explicit', "
          "    cleared_by_operation_id = '$_operationId' "
          "WHERE id = '${_convertible.first}'",
        );
      });
      await held.future;

      final pass = backfill.cutoverBackfillIfNeeded();
      await _awaitLockWaiters(writer, count: 1);
      release.complete();
      await racing;
      final report = await pass;

      expect(
        report.convertedReceipts,
        0,
        reason: 'the backfill lost the race and says so',
      );
      final row = await _receipt(writer, _convertible.first);
      expect(row['clear_reason'], 'explicit');
      expect(row['cleared_by_operation_id'], _operationId);
      expect(
        (row['cleared_at']! as DateTime).toUtc(),
        DateTime.utc(2026, 9, 19, 11),
        reason: 'the user\'s own clear is not overwritten with seen_at',
      );
    });

    test(
      'an interrupted backfill resumed produces the one-shot state',
      () async {
        await _seed(writer);

        // A real interruption: one batch of one row commits, and the next call
        // throws before it can run.
        final interrupted = _FailAfterBatches(repository, failAfter: 1);
        await expectLater(
          AttentionCutoverCase(interrupted).cutoverBackfillIfNeeded(
            batchSize: 1,
          ),
          throwsA(isA<_InjectedInterruption>()),
        );

        // The partial state, asserted rather than assumed: exactly one receipt
        // converted, the cursor naming it, the phase not marked done.
        expect(await _legacySeenIds(writer), [_convertible.first]);
        final progress = await _progress(writer);
        expect(progress['legacy_seen_cursor'], _convertible.first);
        expect(progress['legacy_seen_completed_at'], isNull);
        expect(progress['cutover_at'], isNotNull);

        final fixedInstant = progress['cutover_at']! as DateTime;
        final firstClearedAt = (await _receipt(
          writer,
          _convertible.first,
        ))['cleared_at'];

        final resumed = await backfill.cutoverBackfillIfNeeded(batchSize: 1);
        expect(
          resumed.convertedReceipts,
          2,
          reason: 'the resumed pass does the remaining work, not all of it',
        );

        final afterResume = await _snapshot(writer);
        expect(
          (await _progress(writer))['cutover_at'],
          fixedInstant,
          reason: 'the boundary a restart resumes against cannot move',
        );
        expect(
          (await _receipt(writer, _convertible.first))['cleared_at'],
          firstClearedAt,
          reason: 'the second pass does not re-stamp what the first cleared',
        );
        expect(
          (await _progress(writer))['legacy_seen_completed_at'],
          isNotNull,
        );

        // A third entry, with the phase complete, must be a pure no-op.
        final again = await backfill.cutoverBackfillIfNeeded(batchSize: 1);
        expect(again.alreadyComplete, isTrue);
        expect(again.convertedReceipts, 0);
        expect(await _snapshot(writer), afterResume);

        // And the comparison the acceptance names: the same fixtures, one
        // uninterrupted pass, the same resulting state.
        await _resetFixtures(writer);
        await _seed(writer);
        final oneShot = await backfill.cutoverBackfillIfNeeded();
        expect(oneShot.convertedReceipts, 3);
        expect(await _snapshot(writer), afterResume);
      },
    );
  }, skip: skipReason);
}

/// Runs [failAfter] batches for real, then refuses to run another.
///
/// Delegation rather than a stub: the batches that do run are the production
/// statement, against the production database, so the state the resume finds
/// is the state a crashed backfill would really have left.
final class _FailAfterBatches implements AttentionCutoverPort {
  _FailAfterBatches(this._inner, {required this.failAfter});

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
  }) async {
    if (_batches >= failAfter) throw const _InjectedInterruption();
    _batches++;
    return _inner.convertLegacySeenBatch(batchSize: batchSize);
  }

  @override
  Future<void> markLegacySeenComplete() => _inner.markLegacySeenComplete();
}

final class _InjectedInterruption implements Exception {
  const _InjectedInterruption();
}

const _viewerId = 'Uu18a0001';
const _authorId = 'Uu18a0002';
const _beaconId = 'Bu18a00001';

const _convertible = ['Nu18a01', 'Nu18a02', 'Nu18a03'];
const _unseenId = 'Nu18a04';
const _obligationId = 'Nu18a05';
const _alreadyClearedId = 'Nu18a06';
const _postCutoverId = 'Nu18a07';
const _operationId = 'OPu18a01';
const _occurrenceId = 'AOu18a01';

Future<void> _resetFixtures(Connection writer) async {
  await writer.execute('''
TRUNCATE TABLE
  public.attention_cutover,
  public.attention_clear_operation,
  public.attention_occurrence,
  public.notification_outbox,
  public.inbox_item,
  public.beacon,
  public."user"
CASCADE
''');
  for (final id in [_viewerId, _authorId]) {
    await writer.execute(
      Sql.named(
        'INSERT INTO public."user" (id, display_name, public_key) '
        'VALUES (@id, @id, @key)',
      ),
      parameters: {'id': id, 'key': '$id-key'},
    );
  }
  await writer.execute(
    Sql.named(
      'INSERT INTO public.beacon (id, user_id, title, description, status) '
      "VALUES (@id, @userId, 'Request', 'Request', 0)",
    ),
    parameters: {'id': _beaconId, 'userId': _authorId},
  );
}

/// The fixture set, seeded identically for the interrupted and the one-shot
/// run so their final states are comparable value for value.
Future<void> _seed(Connection writer) async {
  for (var i = 0; i < _convertible.length; i++) {
    await _insertReceipt(
      writer,
      id: _convertible[i],
      seenAt: '2026-09-1${6 + i}T0${7 + i}:00:00Z',
    );
  }
  await _insertReceipt(writer, id: _unseenId);
  await _insertReceipt(
    writer,
    id: _obligationId,
    seenAt: '2026-09-17T09:00:00Z',
    requiresAction: true,
  );

  await writer.execute(
    Sql.named(
      'INSERT INTO public.attention_clear_operation '
      '(id, account_id, surface, status) '
      "VALUES (@id, @accountId, 'explicit', 'complete')",
    ),
    parameters: {'id': _operationId, 'accountId': _viewerId},
  );
  await _insertReceipt(
    writer,
    id: _alreadyClearedId,
    seenAt: '2026-09-17T07:30:00Z',
  );
  await writer.execute(
    "UPDATE public.notification_outbox "
    "SET cleared_at = '2026-09-17T08:00:00Z', clear_reason = 'explicit', "
    "    cleared_by_operation_id = '$_operationId' "
    "WHERE id = '$_alreadyClearedId'",
  );

  await writer.execute(
    Sql.named('''
INSERT INTO public.attention_occurrence
  (id, source_event_key, event_type, actor_user_id, immutable_payload)
VALUES (@id, @id, 'relayReceived', @actorId, '{}'::jsonb)
'''),
    parameters: {'id': _occurrenceId, 'actorId': _authorId},
  );
  await _insertReceipt(
    writer,
    id: _postCutoverId,
    seenAt: '2026-09-17T10:00:00Z',
    occurrenceId: _occurrenceId,
  );

  await writer.execute(
    Sql.named('''
INSERT INTO public.inbox_item
  (user_id, beacon_id, status, tombstone_dismissed_at)
VALUES (@userId, @beaconId, 1, '2026-09-10T09:00:00Z')
'''),
    parameters: {'userId': _viewerId, 'beaconId': _beaconId},
  );
}

Future<void> _insertReceipt(
  Connection writer, {
  required String id,
  String? seenAt,
  bool requiresAction = false,
  String? occurrenceId,
}) => writer.execute(
  Sql.named('''
INSERT INTO public.notification_outbox (
  id, account_id, category, kind, priority,
  title, body, action_url, dedup_key, created_at, seen_at,
  beacon_id, source_event_key, occurrence_id,
  destination_kind, presentation_key, presentation_payload,
  suppression_class, access_policy,
  requires_action, attention_thread_key
) VALUES (
  @id, @accountId, 'coordination', 'coordinationChanged', 'normal',
  'Title', 'Body', '/attention', @dedupKey,
  '2026-09-16T10:00:00Z', CAST(@seenAt AS timestamptz),
  @beaconId, @sourceEventKey, @occurrenceId,
  'beacon', 'request_status_changed', '{"eventType":"fixture"}'::jsonb,
  'standard', 'beacon_content',
  @requiresAction, @threadKey
)
'''),
  parameters: {
    'id': id,
    'accountId': _viewerId,
    'dedupKey': 'dedup-$id',
    'seenAt': seenAt,
    'beaconId': _beaconId,
    'sourceEventKey': 'source-$id',
    'occurrenceId': occurrenceId,
    'requiresAction': requiresAction,
    'threadKey': requiresAction ? 'v1|needsMe|$id|$_viewerId' : null,
  },
);

Future<Map<String, Object?>> _receipt(Connection writer, String id) async {
  final rows = await writer.execute(
    Sql.named(
      'SELECT seen_at, cleared_at, clear_reason, cleared_by_operation_id '
      'FROM public.notification_outbox WHERE id = @id',
    ),
    parameters: {'id': id},
  );
  return {
    'seen_at': rows.first[0],
    'cleared_at': rows.first[1],
    'clear_reason': rows.first[2],
    'cleared_by_operation_id': rows.first[3],
  };
}

Future<List<String>> _legacySeenIds(Connection writer) async {
  final rows = await writer.execute(
    "SELECT id FROM public.notification_outbox "
    "WHERE clear_reason = 'legacy_seen' ORDER BY id",
  );
  return [for (final row in rows) row.first! as String];
}

Future<Map<String, Object?>> _progress(Connection writer) async {
  final rows = await writer.execute(
    'SELECT cutover_at, legacy_seen_cursor, legacy_seen_completed_at '
    'FROM public.attention_cutover WHERE id',
  );
  return {
    'cutover_at': rows.first[0],
    'legacy_seen_cursor': rows.first[1],
    'legacy_seen_completed_at': rows.first[2],
  };
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

/// Every fact this backfill could have touched, for every receipt.
Future<List<List<Object?>>> _snapshot(Connection writer) async {
  final rows = await writer.execute(
    'SELECT id, seen_at, cleared_at, clear_reason, cleared_by_operation_id '
    'FROM public.notification_outbox ORDER BY id',
  );
  return [for (final row in rows) row.toList()];
}
