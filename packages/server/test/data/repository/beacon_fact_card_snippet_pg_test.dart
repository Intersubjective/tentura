@Tags(['pg'])
library;

import 'package:drift_postgres/drift_postgres.dart';
import 'package:postgres/postgres.dart';
import 'package:test/test.dart';

import 'package:tentura_server/consts/beacon_fact_card_consts.dart';
import 'package:tentura_server/data/database/tentura_db.dart'
    hide isNotNull, isNull;
import 'package:tentura_server/data/repository/beacon_fact_card_repository.dart';
import 'package:tentura_server/data/repository/beacon_room_repository.dart';

import '../../support/disposable_pg_target.dart';
import '../../support/pg_test_public_keys.dart';
import '../../support/query_counter.dart';

/// tentura-617.15 (issue #181 plan §8.6): Inbox / My Work read the public
/// fact snippets of up to 80 beacons in one statement.
///
/// Contract under test:
///
/// ```dart
/// Future<Map<String, String>> publicFactSnippetsByBeaconIds(
///   List<String> beaconIds,
/// );
/// ```
///
/// The snippet is the newest live public fact of each beacon (visibility 0,
/// status active 0 or corrected 1), at most 160 chars (157 + `…`). Beacons
/// with no live public fact have no entry. The read is one `customSelect`
/// served by the partial index `beacon_fact_card_public_live_idx`.
Future<void> main() async {
  final target = DisposablePgTarget.fromNamedEnvironment(
    envVarName: 'TENTURA_FACT_SNIPPET_PG_TEST_DB',
    defaultNamePrefix: 'tentura_test_fact_snippet',
  );
  final reachable = await canReachPostgresAdmin(target);
  final skipReason = reachable
      ? false as Object
      : 'Postgres admin database not reachable for disposable test target';

  group('BeaconFactCardRepository.publicFactSnippetsByBeaconIds', () {
    late DisposablePgWriterSession session;
    late TenturaDb db;
    late _RecordingCounter counter;
    late BeaconFactCardRepository repository;

    if (reachable) {
      setUpAll(() async {
        session = await setUpDisposablePgWriter(target: target);
        await _seed(session.writer);
        await session.writer.execute('ANALYZE public.beacon_fact_card');

        counter = _RecordingCounter();
        db = TenturaDb.forTest(
          database: PgDatabase.opened(
            Pool<dynamic>.withEndpoints(
              [target.databaseEnv.pgEndpoint],
              settings: target.databaseEnv.pgPoolSettings,
            ),
            enableMigrations: false,
          ).interceptWith(counter),
        );
        repository = BeaconFactCardRepository(db, BeaconRoomRepository(db));
      });

      tearDownAll(() async {
        await tearDownDisposablePgWriter(session: session, drift: db);
      });
    }

    test(
      '1 beacon costs exactly 1 statement',
      () async {
        counter.reset();
        final snippets = await repository.publicFactSnippetsByBeaconIds([
          _activeBeaconId,
        ]);

        expect(
          counter.count,
          1,
          reason: counter.selects.map((s) => s.statement).join('\n---\n'),
        );
        expect(snippets, {_activeBeaconId: 'active public fact'});
      },
      skip: skipReason,
    );

    test(
      '80 beacons cost exactly 1 statement',
      () async {
        expect(_allBeaconIds, hasLength(80));
        counter.reset();
        final snippets = await repository.publicFactSnippetsByBeaconIds(
          _allBeaconIds,
        );

        expect(
          counter.count,
          1,
          reason: counter.selects.map((s) => s.statement).join('\n---\n'),
        );
        expect(snippets[_activeBeaconId], 'active public fact');
        expect(snippets[_correctedBeaconId], 'edited public fact');
        expect(
          snippets[_mixedBeaconId],
          'newer corrected fact',
          reason: 'newest live public fact wins over an older active one',
        );
        expect(snippets[_paddedBeaconId], 'padded fact');
        expect(snippets[_longBeaconId], _expectedLongSnippet);
        for (final id in [
          _roomOnlyBeaconId,
          _removedBeaconId,
          _noFactBeaconId,
        ]) {
          expect(snippets, isNot(contains(id)), reason: id);
        }
        for (final id in _fillerBeaconIds) {
          expect(snippets[id], 'filler fact $id', reason: id);
        }
        expect(snippets, hasLength(_fillerBeaconIds.length + 5));
      },
      skip: skipReason,
    );

    test(
      'an edited (status corrected) public fact still yields a snippet',
      () async {
        final snippets = await repository.publicFactSnippetsByBeaconIds([
          _correctedBeaconId,
          _mixedBeaconId,
        ]);

        expect(snippets[_correctedBeaconId], 'edited public fact');
        expect(
          snippets[_mixedBeaconId],
          'newer corrected fact',
          reason: 'newest live public fact wins, corrected included',
        );
      },
      skip: skipReason,
    );

    test(
      'room-only and removed facts yield no snippet',
      () async {
        final snippets = await repository.publicFactSnippetsByBeaconIds([
          _roomOnlyBeaconId,
          _removedBeaconId,
          _noFactBeaconId,
        ]);

        expect(snippets, isEmpty);
      },
      skip: skipReason,
    );

    test(
      'the snippet is trimmed, then cut to 157 chars + … (at most 160)',
      () async {
        final snippets = await repository.publicFactSnippetsByBeaconIds([
          _longBeaconId,
          _paddedBeaconId,
        ]);

        final snippet = snippets[_longBeaconId];
        expect(snippet, isNotNull);
        expect(snippet!.length, lessThanOrEqualTo(160));
        expect(snippet, hasLength(158));
        expect(
          snippet,
          _expectedLongSnippet,
          reason: 'leading whitespace must be trimmed before the cut',
        );
        expect(
          snippets[_paddedBeaconId],
          'padded fact',
          reason: 'short facts are trimmed and not cut',
        );
      },
      skip: skipReason,
    );

    test(
      'empty beaconIds returns no snippets',
      () async {
        final snippets = await repository.publicFactSnippetsByBeaconIds(
          const <String>[],
        );
        expect(snippets, isEmpty);
      },
      skip: skipReason,
    );

    test(
      'EXPLAIN (enable_seqscan off) uses beacon_fact_card_public_live_idx',
      () async {
        counter.reset();
        await repository.publicFactSnippetsByBeaconIds(_allBeaconIds);
        final selects = counter.selects
            .where((s) => s.statement.contains('beacon_fact_card'))
            .toList();
        expect(selects, hasLength(1), reason: 'one snippet batch');
        final select = selects.single;

        final executor = select.executor;
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
            contains('beacon_fact_card_public_live_idx'),
            reason: 'plan:\n$plan',
          );
          expect(
            plan,
            isNot(
              matches(RegExp(r'Seq Scan on (?:public\.)?beacon_fact_card\b')),
            ),
            reason: 'plan:\n$plan',
          );
        } finally {
          await executor.runCustom('RESET enable_seqscan');
        }
      },
      skip: skipReason,
    );
  });
}

// ---------------------------------------------------------------------------
// Fixture: one author and 80 beacons. Seven carry the cases under test (one
// active public fact; one corrected public fact; an older active plus a newer
// corrected fact; room-only facts only; removed public facts only; no facts;
// one over-long public fact padded with whitespace; one short public fact
// padded with whitespace). The remaining 72 each carry one active public
// fact.

const _authorId = 'Usnauthor01';

const _activeBeaconId = 'Bsnactive01';
const _correctedBeaconId = 'Bsncorrect1';
const _mixedBeaconId = 'Bsnmixed001';
const _roomOnlyBeaconId = 'Bsnroomonly';
const _removedBeaconId = 'Bsnremoved1';
const _noFactBeaconId = 'Bsnnofact01';
const _longBeaconId = 'Bsnlong0001';
const _paddedBeaconId = 'Bsnpadded01';

const _caseBeaconIds = [
  _activeBeaconId,
  _correctedBeaconId,
  _mixedBeaconId,
  _roomOnlyBeaconId,
  _removedBeaconId,
  _noFactBeaconId,
  _longBeaconId,
  _paddedBeaconId,
];

final _fillerBeaconIds = [
  for (var i = 0; i < 80 - _caseBeaconIds.length; i++)
    'Bsnf${i.toString().padLeft(7, '0')}',
];

final _allBeaconIds = [..._caseBeaconIds, ..._fillerBeaconIds];

/// Over 160 chars once trimmed; the padding must be trimmed before the cut,
/// so the snippet starts at `word0`, not at a space.
final _longBody = List.generate(40, (i) => 'word$i').join(' ');
final _longText = '   $_longBody  \n';
final _expectedLongSnippet = '${_longBody.substring(0, 157)}…';

final _t0 = DateTime.utc(2026, 3, 1, 12);

Future<void> _seed(Connection writer) async {
  await writer.execute(
    Sql.named('''
INSERT INTO public."user" (id, display_name, public_key)
VALUES (@id, 'Snippet Author', @key)
'''),
    parameters: {'id': _authorId, 'key': pgTestPublicKey('factsnippet', 1)},
  );
  for (final id in _allBeaconIds) {
    await writer.execute(
      Sql.named('''
INSERT INTO public.beacon
  (id, user_id, title, description, status, published_at, is_discoverable)
VALUES (@id, @author, 't', 'd', 0, @t0, false)
'''),
      parameters: {'id': id, 'author': _authorId, 't0': _t0},
    );
  }

  const public = BeaconFactCardVisibilityBits.public;
  const room = BeaconFactCardVisibilityBits.room;
  const active = BeaconFactCardStatusBits.active;
  const corrected = BeaconFactCardStatusBits.corrected;
  const removed = BeaconFactCardStatusBits.removed;

  final facts = <(String, String, String, int, int, int)>[
    ('Fsnactive01', _activeBeaconId, 'active public fact', public, active, 0),
    (
      'Fsncorrect1',
      _correctedBeaconId,
      'edited public fact',
      public,
      corrected,
      0,
    ),
    ('Fsnmixold01', _mixedBeaconId, 'older active fact', public, active, 0),
    (
      'Fsnmixnew01',
      _mixedBeaconId,
      'newer corrected fact',
      public,
      corrected,
      5,
    ),
    ('Fsnroom0001', _roomOnlyBeaconId, 'room fact', room, active, 0),
    ('Fsnroom0002', _roomOnlyBeaconId, 'room corrected', room, corrected, 1),
    ('Fsnremove01', _removedBeaconId, 'removed public', public, removed, 0),
    ('Fsnremove02', _removedBeaconId, 'removed room', room, removed, 1),
    ('Fsnlong0001', _longBeaconId, _longText, public, active, 0),
    ('Fsnpadded01', _paddedBeaconId, '  padded fact \t', public, active, 0),
    for (final (i, id) in _fillerBeaconIds.indexed)
      (
        'Fsnf${i.toString().padLeft(7, '0')}',
        id,
        'filler fact $id',
        public,
        active,
        0,
      ),
  ];
  for (final (id, beaconId, text, visibility, status, minutes) in facts) {
    final at = _t0.add(Duration(minutes: minutes));
    await writer.execute(
      Sql.named('''
INSERT INTO public.beacon_fact_card
  (id, beacon_id, fact_text, visibility, pinned_by, status, revision_seq,
   other_editor_count, history_truncated, created_at, updated_at)
VALUES
  (@id, @beacon, @text, @visibility, @author, @status, 1, 0, false, @at, @at)
'''),
      parameters: {
        'id': id,
        'beacon': beaconId,
        'text': text,
        'visibility': visibility,
        'status': status,
        'author': _authorId,
        'at': at,
      },
    );
  }
}

/// Counts every statement (see [QueryCounter]) and records each select so a
/// test can EXPLAIN what the snippet path actually issued, on the same
/// session.
class _RecordingCounter extends QueryCounter {
  final selects =
      <({String statement, List<Object?> args, QueryExecutor executor})>[];

  @override
  void reset() {
    super.reset();
    selects.clear();
  }

  @override
  Future<List<Map<String, Object?>>> runSelect(
    QueryExecutor executor,
    String statement,
    List<Object?> args,
  ) {
    selects.add((
      statement: statement,
      args: List.of(args),
      executor: executor,
    ));
    return super.runSelect(executor, statement, args);
  }
}
