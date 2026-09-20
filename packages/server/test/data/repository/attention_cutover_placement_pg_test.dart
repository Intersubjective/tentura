@Tags(['pg'])
library;

import 'package:postgres/postgres.dart';
import 'package:test/test.dart';

import 'package:tentura_server/data/repository/attention_cutover_repository.dart';
import 'package:tentura_server/domain/attention/attention_cutover_models.dart';
import 'package:tentura_server/domain/port/attention_cutover_port.dart';
import 'package:tentura_server/domain/use_case/attention_cutover_case.dart';

import '../../support/disposable_pg_target.dart';

/// U18b gate 2 — historical `placement`.
///
/// m0189 added the column with a `'primary'` default, so every row written
/// before it claims a placement nobody assigned. That is not neutral: a
/// `beaconHierarchyStatusChanged` receipt is `timeline_only` by policy, and
/// one left `primary` can light an ancestor Request's dot for activity that
/// happened on a child.
///
/// It is **partially** decidable, and the three cases are the unit:
///
/// 1. a row whose family is provable → demoted;
/// 2. a row whose family is not → left `primary`, with the residual
///    ancestor-dot risk documented in the journal rather than guessed away;
/// 3. a row already `timeline_only` → untouched, so a second pass is a no-op.
///
/// Demotion is the irreversible direction here: a row wrongly demoted is
/// still visible in History but silently absent from every primary-surface
/// indicator, which is the same class of loss as clearing an unseen receipt.
Future<void> main() async {
  final target = DisposablePgTarget.fromNamedEnvironment(
    envVarName: 'TENTURA_U18B_PLACEMENT_TEST_DB',
    defaultNamePrefix: 'tentura_test_u18b_placement',
  );
  final reachable = await canReachPostgresAdmin(target);
  final skipReason = reachable
      ? false
      : 'Postgres admin database not reachable for disposable test target';

  group('historical placement backfill', () {
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

    test('demotes the rows provably of a timeline-only family', () async {
      await _seed(writer);

      final report = await backfill.cutoverBackfillIfNeeded();

      expect(report.demotedPlacements, 2);
      for (final id in _demotable) {
        expect(
          await _placement(writer, id),
          'timeline_only',
          reason: '$id: the destination Request must not gain a dot because '
              'a child of it moved',
        );
      }
    });

    test('leaves every row it cannot prove exactly as it was', () async {
      await _seed(writer);

      await backfill.cutoverBackfillIfNeeded();

      for (final id in _undecidable) {
        expect(
          await _placement(writer, id),
          'primary',
          reason: '$id: demoting on a guess removes a row from every primary '
              'indicator, and nothing on the surface says where it went',
        );
      }
    });

    test('a row already timeline_only is not a candidate', () async {
      await _seed(writer);

      final first = await backfill.cutoverBackfillIfNeeded();
      expect(first.demotedPlacements, 2);
      expect(await _placement(writer, _alreadyTimelineOnlyId), 'timeline_only');

      // The phase is complete, so a second entry does no work at all; the
      // cursor and the guard are what make that true even when it is not.
      final again = await backfill.cutoverBackfillIfNeeded();
      expect(again.alreadyComplete, isTrue);
      expect(again.demotedPlacements, 0);
    });

    test('an interrupted placement pass resumed produces the one-shot state',
        () async {
      await _seed(writer);

      final interrupted = _FailAfterPlacementBatches(repository, failAfter: 1);
      await expectLater(
        AttentionCutoverCase(interrupted).cutoverBackfillIfNeeded(batchSize: 1),
        throwsA(isA<_InjectedInterruption>()),
      );

      // Partial, and asserted: the first demotable row only.
      expect(await _demotedIds(writer), [_demotable.first]);
      final progress = await _progress(writer);
      expect(progress['placement_cursor'], _demotable.first);
      expect(progress['placement_completed_at'], isNull);
      final fixedInstant = progress['cutover_at'];

      final resumed = await backfill.cutoverBackfillIfNeeded(batchSize: 1);
      expect(
        resumed.demotedPlacements,
        1,
        reason: 'the resumed pass finishes the work, it does not redo it',
      );
      final afterResume = await _snapshot(writer);
      expect((await _progress(writer))['cutover_at'], fixedInstant);
      expect((await _progress(writer))['placement_completed_at'], isNotNull);

      await _resetFixtures(writer);
      await _seed(writer);
      final oneShot = await backfill.cutoverBackfillIfNeeded();
      expect(oneShot.demotedPlacements, 2);
      expect(await _snapshot(writer), afterResume);
    });
  }, skip: skipReason);
}

final class _FailAfterPlacementBatches implements AttentionCutoverPort {
  _FailAfterPlacementBatches(this._inner, {required this.failAfter});

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
  }) => _inner.keyLegacyObligationBatch(batchSize: batchSize);

  @override
  Future<void> markObligationKeyComplete() =>
      _inner.markObligationKeyComplete();

  @override
  Future<bool> isPlacementComplete() => _inner.isPlacementComplete();

  @override
  Future<AttentionCutoverBatch> demoteLegacyPlacementBatch({
    required int batchSize,
  }) async {
    if (_batches >= failAfter) throw const _InjectedInterruption();
    _batches++;
    return _inner.demoteLegacyPlacementBatch(batchSize: batchSize);
  }

  @override
  Future<void> markPlacementComplete() => _inner.markPlacementComplete();
}

final class _InjectedInterruption implements Exception {
  const _InjectedInterruption();
}

const _viewerId = 'Uu18c0001';
const _actorId = 'Uu18c0002';
const _beaconId = 'Bu18c00001';

const _hierarchyId = 'Nu18c01';
const _hierarchySecondId = 'Nu18c02';
const _noOccurrenceId = 'Nu18c03';
const _mismatchedOccurrenceId = 'Nu18c04';
const _collapsedId = 'Nu18c05';
const _primaryFamilyId = 'Nu18c06';
const _postCutoverId = 'Nu18c07';
const _alreadyTimelineOnlyId = 'Nu18c08';

const _demotable = [_hierarchyId, _hierarchySecondId];
const _undecidable = [
  _noOccurrenceId,
  _mismatchedOccurrenceId,
  _collapsedId,
  _primaryFamilyId,
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
  for (final id in [_viewerId, _actorId]) {
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
    parameters: {'id': _beaconId, 'userId': _viewerId},
  );
}

Future<void> _seed(Connection writer) async {
  // Provable: two witnesses agreeing, one event, before the cutover.
  for (final id in _demotable) {
    await _occurrence(
      writer,
      id: 'AO$id',
      eventType: 'beaconHierarchyStatusChanged',
    );
    await _receipt(
      writer,
      id: id,
      eventType: 'beaconHierarchyStatusChanged',
      occurrenceId: 'AO$id',
    );
  }

  // Not provable, four ways — and one row that is simply primary by policy.
  await _receipt(
    writer,
    id: _noOccurrenceId,
    eventType: 'beaconHierarchyStatusChanged',
  );
  await _occurrence(
    writer,
    id: 'AO$_mismatchedOccurrenceId',
    eventType: 'beaconHierarchyStatusChanged',
  );
  await _receipt(
    writer,
    id: _mismatchedOccurrenceId,
    eventType: 'requestStatusChanged',
    occurrenceId: 'AO$_mismatchedOccurrenceId',
  );
  await _occurrence(
    writer,
    id: 'AO$_collapsedId',
    eventType: 'beaconHierarchyStatusChanged',
  );
  await _receipt(
    writer,
    id: _collapsedId,
    eventType: 'beaconHierarchyStatusChanged',
    occurrenceId: 'AO$_collapsedId',
    collapsedCount: 4,
  );
  await _occurrence(
    writer,
    id: 'AO$_primaryFamilyId',
    eventType: 'requestStatusChanged',
  );
  await _receipt(
    writer,
    id: _primaryFamilyId,
    eventType: 'requestStatusChanged',
    occurrenceId: 'AO$_primaryFamilyId',
  );

  // After the cutover: the producer classified it, so `primary` here is an
  // answer, not a default.
  await _occurrence(
    writer,
    id: 'AO$_postCutoverId',
    eventType: 'beaconHierarchyStatusChanged',
  );
  await _receipt(
    writer,
    id: _postCutoverId,
    eventType: 'beaconHierarchyStatusChanged',
    occurrenceId: 'AO$_postCutoverId',
    createdAt: '2099-01-01T00:00:00Z',
  );

  await _occurrence(
    writer,
    id: 'AO$_alreadyTimelineOnlyId',
    eventType: 'beaconHierarchyStatusChanged',
  );
  await _receipt(
    writer,
    id: _alreadyTimelineOnlyId,
    eventType: 'beaconHierarchyStatusChanged',
    occurrenceId: 'AO$_alreadyTimelineOnlyId',
    placement: 'timeline_only',
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
  parameters: {'id': id, 'eventType': eventType, 'actorId': _actorId},
);

Future<void> _receipt(
  Connection writer, {
  required String id,
  required String eventType,
  String? occurrenceId,
  String createdAt = '2026-09-16T10:00:00Z',
  int collapsedCount = 1,
  String placement = 'primary',
}) => writer.execute(
  Sql.named('''
INSERT INTO public.notification_outbox (
  id, account_id, category, kind, priority,
  title, body, action_url, dedup_key, created_at, collapsed_count,
  beacon_id, source_event_key, occurrence_id,
  destination_kind, presentation_key, presentation_payload,
  suppression_class, access_policy,
  requires_action, placement
) VALUES (
  @id, @accountId, 'coordination', @eventType, 'normal',
  'Title', 'Body', '/attention', @dedupKey,
  CAST(@createdAt AS timestamptz), @collapsedCount,
  @beaconId, @sourceEventKey, CAST(@occurrenceId AS text),
  'beacon', 'request_status_changed', CAST(@payload AS jsonb),
  'standard', 'beacon_content',
  false, @placement
)
'''),
  parameters: {
    'id': id,
    'accountId': _viewerId,
    'eventType': eventType,
    'dedupKey': 'dedup-$id',
    'createdAt': createdAt,
    'collapsedCount': collapsedCount,
    'beaconId': _beaconId,
    'sourceEventKey': 'source-$id',
    'occurrenceId': occurrenceId,
    'payload': '{"eventType":"$eventType","beaconId":"$_beaconId"}',
    'placement': placement,
  },
);

Future<String> _placement(Connection writer, String id) async {
  final rows = await writer.execute(
    Sql.named(
      'SELECT placement FROM public.notification_outbox WHERE id = @id',
    ),
    parameters: {'id': id},
  );
  return rows.first.first! as String;
}

Future<List<String>> _demotedIds(Connection writer) async {
  final rows = await writer.execute(
    "SELECT id FROM public.notification_outbox "
    "WHERE placement = 'timeline_only' AND id <> '$_alreadyTimelineOnlyId' "
    'ORDER BY id',
  );
  return [for (final row in rows) row.first! as String];
}

Future<Map<String, Object?>> _progress(Connection writer) async {
  final rows = await writer.execute(
    'SELECT cutover_at, placement_cursor, placement_completed_at '
    'FROM public.attention_cutover WHERE id',
  );
  return {
    'cutover_at': rows.first[0],
    'placement_cursor': rows.first[1],
    'placement_completed_at': rows.first[2],
  };
}

Future<List<List<Object?>>> _snapshot(Connection writer) async {
  final rows = await writer.execute(
    'SELECT id, placement, cleared_at, clear_reason, logical_task_key '
    'FROM public.notification_outbox ORDER BY id',
  );
  return [for (final row in rows) row.toList()];
}
