@Tags(['pg'])
library;

import 'package:drift_postgres/drift_postgres.dart';
import 'package:postgres/postgres.dart';
import 'package:test/test.dart';

import 'package:tentura_server/consts/beacon_activity_event_consts.dart';
import 'package:tentura_server/consts/beacon_fact_card_consts.dart';
import 'package:tentura_server/data/database/tentura_db.dart'
    hide isNotNull, isNull;
import 'package:tentura_server/data/repository/beacon_fact_card_repository.dart';
import 'package:tentura_server/data/repository/beacon_room_repository.dart';
import 'package:tentura_server/domain/entity/beacon_fact_history_entry_entity.dart';

import '../../support/disposable_pg_target.dart';
import '../../support/pg_test_public_keys.dart';

/// tentura-617.13 (issue #181 plan §8.4 / §14.3): `history()` is one keyset
/// read over the UNION of a fact's `beacon_fact_card_revision` rows and its
/// `beacon_activity_event` rows of types 2, 14 and 20.
///
/// Contract under test:
///
/// ```dart
/// Future<List<BeaconFactHistoryEntry>> history({
///   required String factCardId,
///   ({DateTime createdAt, String entryKey})? before,
///   int limit = kFactHistoryPageSize,
/// });
/// ```
///
/// `entry_key` is `'r' || lpad(seq::text, 10, '0')` for a revision and
/// `'e' || id` for an event; rows sort by `(created_at, entry_key)` DESC and
/// `before` is the exclusive keyset cursor of the last entry already shown.
/// A page may carry one look-ahead row (`limit + 1`); callers keep `limit`.
Future<void> main() async {
  final target = DisposablePgTarget.fromNamedEnvironment(
    envVarName: 'TENTURA_FACT_HISTORY_PG_TEST_DB',
    defaultNamePrefix: 'tentura_test_fact_history',
  );
  final reachable = await canReachPostgresAdmin(target);
  final skipReason = reachable
      ? false as Object
      : 'Postgres admin database not reachable for disposable test target';

  group('BeaconFactCardRepository.history', () {
    late DisposablePgWriterSession session;
    late TenturaDb db;
    late _SelectRecorder recorder;
    late BeaconFactCardRepository repository;

    if (reachable) {
      setUpAll(() async {
        session = await setUpDisposablePgWriter(target: target);
        await _seed(session.writer);
        await session.writer.execute(
          'ANALYZE public.beacon_fact_card_revision',
        );
        await session.writer.execute('ANALYZE public.beacon_activity_event');

        recorder = _SelectRecorder();
        db = TenturaDb.forTest(
          database: PgDatabase.opened(
            Pool<dynamic>.withEndpoints(
              [target.databaseEnv.pgEndpoint],
              settings: target.databaseEnv.pgPoolSettings,
            ),
            enableMigrations: false,
          ).interceptWith(recorder),
        );
        repository = BeaconFactCardRepository(db, BeaconRoomRepository(db));
      });

      tearDownAll(() async {
        await tearDownDisposablePgWriter(session: session, drift: db);
      });
    }

    test(
      'returns every revision and fact event, newest first by '
      '(created_at, entry_key)',
      () async {
        final List<BeaconFactHistoryEntry> entries = await repository.history(
          factCardId: _factId,
          limit: 200,
        );
        final page = entries.take(200).toList();

        expect(page, hasLength(_fixtureEntryCount));
        final keys = page.map(_sortKey).toList();
        for (var i = 1; i < keys.length; i++) {
          expect(
            _compareSortKeys(keys[i - 1], keys[i]),
            greaterThan(0),
            reason:
                'entry $i ${keys[i]} must sort strictly after '
                '${keys[i - 1]} (DESC)',
          );
        }
        expect(page.first, isA<BeaconFactHistoryEvent>());
        expect(
          (page.first as BeaconFactHistoryEvent).type,
          BeaconActivityEventTypeBits.factRemoved,
        );
      },
      skip: skipReason,
    );

    test(
      'maps revision and event fields from their rows',
      () async {
        final List<BeaconFactHistoryEntry> entries = await repository.history(
          factCardId: _factId,
          limit: 200,
        );

        final revisions = entries.whereType<BeaconFactHistoryRevision>();
        final bySeq = {for (final r in revisions) r.seq: r};
        expect(bySeq.keys.toSet(), {1, 2, 3});
        for (final seq in bySeq.keys) {
          final r = bySeq[seq]!;
          expect(r.factText, _revisionText(seq), reason: 'seq $seq text');
          expect(
            r.createdAt.toUtc(),
            _revisionAt(seq),
            reason: 'seq $seq createdAt',
          );
          expect(r.actorId, _pinnerId, reason: 'seq $seq actor');
          expect(r.actorTitle, _pinnerTitle, reason: 'seq $seq actorTitle');
        }
        expect(bySeq[1]!.kind, BeaconFactCardRevisionKindBits.created);
        expect(bySeq[2]!.kind, BeaconFactCardRevisionKindBits.edited);
        expect(bySeq[3]!.kind, BeaconFactCardRevisionKindBits.edited);

        final pinned = entries
            .whereType<BeaconFactHistoryEvent>()
            .where((e) => e.type == BeaconActivityEventTypeBits.factPinned)
            .single;
        expect(pinned.createdAt.toUtc(), _t0);
        expect(pinned.actorId, _pinnerId);
      },
      skip: skipReason,
    );

    test(
      "a pin's revision 1 and its factPinned event with equal created_at "
      'order deterministically',
      () async {
        for (var attempt = 0; attempt < 3; attempt++) {
          final List<BeaconFactHistoryEntry> entries = await repository.history(
            factCardId: _factId,
            limit: 200,
          );
          final tail = entries.take(200).toList().reversed.take(2).toList();

          // Oldest entry is the pin event; revision 1 sorts just above it
          // because 'r0000000001' > 'e…' under entry_key DESC.
          expect(tail[0], isA<BeaconFactHistoryEvent>(), reason: 'oldest');
          expect(
            (tail[0] as BeaconFactHistoryEvent).type,
            BeaconActivityEventTypeBits.factPinned,
          );
          expect(tail[1], isA<BeaconFactHistoryRevision>());
          expect((tail[1] as BeaconFactHistoryRevision).seq, 1);
          expect(tail[0].createdAt.toUtc(), tail[1].createdAt.toUtc());

          // Same rule at the seq 2 / event 20 tie in the middle of the list.
          final seq2 = entries.indexWhere(
            (e) => e is BeaconFactHistoryRevision && e.seq == 2,
          );
          final tied = entries[seq2 + 1];
          expect(tied, isA<BeaconFactHistoryEvent>());
          expect(tied.createdAt.toUtc(), _revisionAt(2));
        }
      },
      skip: skipReason,
    );

    test(
      'paging with limit 50 using the last entry as cursor returns all 63 '
      'entries exactly once',
      () async {
        const limit = kFactHistoryPageSize;
        expect(limit, 50);

        final seen = <_SortKey>[];
        ({DateTime createdAt, String entryKey})? before;
        var pages = 0;
        while (true) {
          pages++;
          expect(pages, lessThanOrEqualTo(3), reason: 'paging must terminate');
          final List<BeaconFactHistoryEntry> page = await repository.history(
            factCardId: _factId,
            before: before,
            limit: limit,
          );
          expect(page.length, lessThanOrEqualTo(limit + 1));
          final kept = page.take(limit).toList();
          seen.addAll(kept.map(_sortKey));
          if (page.length < limit || kept.isEmpty) break;
          final last = _sortKey(kept.last);
          before = (createdAt: last.createdAt, entryKey: last.entryKey);
        }

        expect(seen, hasLength(_fixtureEntryCount));
        expect(seen.toSet(), hasLength(_fixtureEntryCount), reason: 'no dups');
        expect(seen.toSet(), _allFixtureKeys().toSet());
        for (var i = 1; i < seen.length; i++) {
          expect(_compareSortKeys(seen[i - 1], seen[i]), greaterThan(0));
        }
      },
      skip: skipReason,
    );

    test(
      'the default page size is kFactHistoryPageSize',
      () async {
        final List<BeaconFactHistoryEntry> page = await repository.history(
          factCardId: _factId,
        );
        expect(
          page.length,
          inInclusiveRange(kFactHistoryPageSize, kFactHistoryPageSize + 1),
        );
        expect(_sortKey(page.first), _allFixtureKeys().first);
      },
      skip: skipReason,
    );

    test(
      'events of other types and other facts are excluded',
      () async {
        final List<BeaconFactHistoryEntry> entries = await repository.history(
          factCardId: _factId,
          limit: 200,
        );

        final events = entries.whereType<BeaconFactHistoryEvent>().toList();
        expect(events, hasLength(_eventCount));
        expect(
          events.map((e) => e.type).toSet(),
          everyElement(
            isIn({
              BeaconActivityEventTypeBits.factPinned,
              BeaconActivityEventTypeBits.factVisibilityChanged,
              BeaconActivityEventTypeBits.factRemoved,
            }),
          ),
        );
        for (final e in events) {
          expect(
            e.actorId,
            isNot(_otherId),
            reason: 'noise events are all by $_otherId',
          );
        }
        final revisions = entries.whereType<BeaconFactHistoryRevision>();
        expect(revisions.map((r) => r.seq).toList()..sort(), [1, 2, 3]);
        expect(
          revisions.map((r) => r.factText),
          everyElement(isNot(startsWith('Other fact'))),
        );

        final List<BeaconFactHistoryEntry> other = await repository.history(
          factCardId: _otherFactId,
          limit: 200,
        );
        expect(other, hasLength(2), reason: 'other fact: 1 revision, 1 event');
      },
      skip: skipReason,
    );

    test(
      'EXPLAIN (enable_seqscan off) uses beacon_fact_card_revision_seq_uq '
      'and beacon_activity_event_fact_card_idx',
      () async {
        Future<void> expectIndexPlan({
          required String label,
          ({DateTime createdAt, String entryKey})? before,
        }) async {
          recorder.reset();
          await repository.history(
            factCardId: _factId,
            before: before,
            limit: kFactHistoryPageSize,
          );
          final selects = recorder.selects
              .where(
                (s) => s.statement.contains('beacon_fact_card_revision'),
              )
              .toList();
          expect(
            selects,
            hasLength(1),
            reason: '$label: history() is one UNION select',
          );
          final select = selects.single;
          expect(select.statement, contains('beacon_activity_event'));

          final executor = recorder.executor!;
          await executor.runCustom('SET enable_seqscan = off');
          try {
            final shown = await executor.runSelect('SHOW enable_seqscan', []);
            expect(shown.single.values.single, 'off');
            final rows = await executor.runSelect(
              'EXPLAIN (COSTS OFF) ${select.statement}',
              select.args,
            );
            final plan = rows.map((r) => r.values.single).join('\n');
            expect(
              plan,
              contains('beacon_fact_card_revision_seq_uq'),
              reason: '$label plan:\n$plan',
            );
            expect(
              plan,
              contains('beacon_activity_event_fact_card_idx'),
              reason: '$label plan:\n$plan',
            );
            expect(
              plan,
              isNot(
                matches(
                  RegExp(
                    r'Seq Scan on (?:public\.)?'
                    r'(?:beacon_fact_card_revision|beacon_activity_event)\b',
                  ),
                ),
              ),
              reason: '$label plan:\n$plan',
            );
          } finally {
            await executor.runCustom('RESET enable_seqscan');
          }
        }

        await expectIndexPlan(label: 'first page');
        await expectIndexPlan(
          label: 'cursor page',
          before: (createdAt: _eventAt(30), entryKey: 'e${_eventId(30)}'),
        );
      },
      skip: skipReason,
    );
  });
}

// ---------------------------------------------------------------------------
// Fixture: fact [_factId] has 3 revisions and 60 events (types 2, 14, 20)
// interleaved one minute apart. Revision 1 ties the factPinned event at [_t0];
// revision 2 ties event 20. Noise: other event types on the same fact, and a
// second fact with its own revision and event.

const _pinnerId = 'Ufhpinner01';
const _pinnerTitle = 'Fact Pinner';
const _otherId = 'Ufhother001';
const _beaconId = 'Bfhbeacon01';
const _factId = 'Ffhfact0001';
const _otherFactId = 'Ffhfact0002';

const _eventCount = 60;
const _revisionCount = 3;
const _fixtureEntryCount = _eventCount + _revisionCount;
const _lastEventIndex = _eventCount - 1;

final _t0 = DateTime.utc(2026, 3, 1, 12);

DateTime _eventAt(int i) => _t0.add(Duration(minutes: i));

String _eventId(int i) => 'Vfhevt${i.toString().padLeft(3, '0')}';

int _eventType(int i) => switch (i) {
  0 => BeaconActivityEventTypeBits.factPinned,
  _lastEventIndex => BeaconActivityEventTypeBits.factRemoved,
  _ => BeaconActivityEventTypeBits.factVisibilityChanged,
};

DateTime _revisionAt(int seq) => switch (seq) {
  1 => _t0,
  2 => _eventAt(20),
  _ => _eventAt(40).add(const Duration(seconds: 30)),
};

String _revisionText(int seq) => 'Fact text v$seq';

String _revisionKey(int seq) => 'r${seq.toString().padLeft(10, '0')}';

typedef _SortKey = ({DateTime createdAt, String entryKey});

int _compareSortKeys(_SortKey a, _SortKey b) {
  final byTime = a.createdAt.compareTo(b.createdAt);
  return byTime != 0 ? byTime : a.entryKey.compareTo(b.entryKey);
}

/// Every entry of [_factId], newest first.
List<_SortKey> _allFixtureKeys() {
  final keys = <_SortKey>[
    for (var seq = 1; seq <= _revisionCount; seq++)
      (createdAt: _revisionAt(seq), entryKey: _revisionKey(seq)),
    for (var i = 0; i < _eventCount; i++)
      (createdAt: _eventAt(i), entryKey: 'e${_eventId(i)}'),
  ]..sort((a, b) => _compareSortKeys(b, a));
  return keys;
}

/// The entity carries no event id, so events are resolved through the
/// fixture: each [_factId] event has a unique `(type, created_at)`.
_SortKey _sortKey(BeaconFactHistoryEntry entry) {
  final at = entry.createdAt.toUtc();
  switch (entry) {
    case BeaconFactHistoryRevision(:final seq):
      return (createdAt: at, entryKey: _revisionKey(seq));
    case BeaconFactHistoryEvent(:final type):
      for (var i = 0; i < _eventCount; i++) {
        if (_eventAt(i) == at && _eventType(i) == type) {
          return (createdAt: at, entryKey: 'e${_eventId(i)}');
        }
      }
      fail('unexpected event type $type at $at');
  }
}

Future<void> _seed(Connection writer) async {
  for (final (id, title, slot) in [
    (_pinnerId, _pinnerTitle, 1),
    (_otherId, 'Other Actor', 2),
  ]) {
    await writer.execute(
      Sql.named('''
INSERT INTO public."user" (id, display_name, public_key)
VALUES (@id, @title, @key)
'''),
      parameters: {
        'id': id,
        'title': title,
        'key': pgTestPublicKey('facthist', slot),
      },
    );
  }
  await writer.execute(
    Sql.named(
      'INSERT INTO public.beacon (id, user_id, title, description) '
      "VALUES (@id, @user, 't', 'd')",
    ),
    parameters: {'id': _beaconId, 'user': _pinnerId},
  );
  await writer.execute(
    Sql.named('''
INSERT INTO public.beacon_fact_card
  (id, beacon_id, fact_text, visibility, pinned_by, status, revision_seq,
   created_at, updated_at)
VALUES
  (@fact, @beacon, @text, 0, @pinner, ${BeaconFactCardStatusBits.removed}, 3,
   @t0, @t0),
  (@other, @beacon, 'Other fact v1', 0, @otherActor,
   ${BeaconFactCardStatusBits.active}, 1, @t0, @t0)
'''),
    parameters: {
      'fact': _factId,
      'other': _otherFactId,
      'beacon': _beaconId,
      'text': _revisionText(3),
      'pinner': _pinnerId,
      'otherActor': _otherId,
      't0': _t0,
    },
  );

  Future<void> insertRevision({
    required String factId,
    required int seq,
    required String text,
    required String actorId,
    required int kind,
    required DateTime at,
  }) => writer.execute(
    Sql.named('''
INSERT INTO public.beacon_fact_card_revision
  (fact_card_id, seq, fact_text, actor_id, kind, created_at)
VALUES (@fact, @seq, @text, @actor, @kind, @at)
'''),
    parameters: {
      'fact': factId,
      'seq': seq,
      'text': text,
      'actor': actorId,
      'kind': kind,
      'at': at,
    },
  );

  for (var seq = 1; seq <= _revisionCount; seq++) {
    await insertRevision(
      factId: _factId,
      seq: seq,
      text: _revisionText(seq),
      actorId: _pinnerId,
      kind: seq == 1
          ? BeaconFactCardRevisionKindBits.created
          : BeaconFactCardRevisionKindBits.edited,
      at: _revisionAt(seq),
    );
  }
  await insertRevision(
    factId: _otherFactId,
    seq: 1,
    text: 'Other fact v1',
    actorId: _otherId,
    kind: BeaconFactCardRevisionKindBits.created,
    at: _eventAt(10),
  );

  Future<void> insertEvent({
    required String id,
    required int type,
    required String actorId,
    required String? factId,
    required DateTime at,
    String? diffFactId,
  }) => writer.execute(
    Sql.named('''
INSERT INTO public.beacon_activity_event
  (id, beacon_id, visibility, type, actor_id, fact_card_id, diff, created_at)
VALUES (@id, @beacon, 0, @type, @actor, @fact,
        jsonb_build_object('factCardId', @diffFact::text), @at)
'''),
    parameters: {
      'id': id,
      'beacon': _beaconId,
      'type': type,
      'actor': actorId,
      'fact': factId,
      'diffFact': diffFactId ?? factId,
      'at': at,
    },
  );

  for (var i = 0; i < _eventCount; i++) {
    await insertEvent(
      id: _eventId(i),
      type: _eventType(i),
      actorId: _pinnerId,
      factId: _factId,
      at: _eventAt(i),
    );
  }

  // Same fact, excluded types (all by [_otherId]).
  var noise = 0;
  for (final type in [
    BeaconActivityEventTypeBits.factEdited,
    BeaconActivityEventTypeBits.planUpdated,
    BeaconActivityEventTypeBits.blockerOpened,
  ]) {
    await insertEvent(
      id: 'Vfhnoise${noise++}',
      type: type,
      actorId: _otherId,
      factId: _factId,
      at: _eventAt(5).add(const Duration(seconds: 15)),
    );
  }
  // Fact type but another fact, and one on no fact at all.
  await insertEvent(
    id: 'Vfhnoise${noise++}',
    type: BeaconActivityEventTypeBits.factPinned,
    actorId: _otherId,
    factId: _otherFactId,
    at: _eventAt(10),
  );
  await insertEvent(
    id: 'Vfhnoise${noise++}',
    type: BeaconActivityEventTypeBits.factVisibilityChanged,
    actorId: _otherId,
    factId: null,
    diffFactId: 'Ffhnofact01',
    at: _eventAt(15).add(const Duration(seconds: 15)),
  );
}

/// Records every Drift select so the test can EXPLAIN the statement
/// `history()` actually issued, with its real binds, on the same session.
class _SelectRecorder extends QueryInterceptor {
  final selects = <({String statement, List<Object?> args})>[];

  QueryExecutor? executor;

  void reset() => selects.clear();

  @override
  Future<List<Map<String, Object?>>> runSelect(
    QueryExecutor executor,
    String statement,
    List<Object?> args,
  ) {
    this.executor = executor;
    selects.add((statement: statement, args: List.of(args)));
    return super.runSelect(executor, statement, args);
  }
}
