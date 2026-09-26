@Tags(['pg'])
library;

import 'package:drift_postgres/drift_postgres.dart';
import 'package:injectable/injectable.dart' show Environment;
import 'package:logging/logging.dart';
import 'package:postgres/postgres.dart';
import 'package:test/test.dart';

import 'package:tentura_server/consts/beacon_fact_card_consts.dart';
import 'package:tentura_server/data/database/tentura_db.dart'
    hide isNotNull, isNull;
import 'package:tentura_server/data/repository/beacon_access_repository.dart';
import 'package:tentura_server/data/repository/beacon_fact_card_repository.dart';
import 'package:tentura_server/data/repository/beacon_hierarchy_repository.dart';
import 'package:tentura_server/data/repository/beacon_room_repository.dart';
import 'package:tentura_server/domain/use_case/beacon_fact_card_case.dart';
import 'package:tentura_server/env.dart';

import '../../support/disposable_pg_target.dart';
import '../../support/pg_test_public_keys.dart';
import '../../support/query_counter.dart';

/// tentura-617.17 (issue #181 plan §8.4 "Room message page — quoted facts",
/// §8.11): `listMessagesEnriched` resolves the quoted revision snapshots of
/// the page in one `customSelect` and nests them under `quotedFact`.
///
/// Contract under test (per message map):
///
/// ```dart
/// 'quotedFact': null | {
///   'factCardId': String, 'seq': int, 'text': String /* quoted revision */,
///   'pinnedById': String?, 'pinnedByTitle': String,
///   'visibility': int, 'status': int, 'currentSeq': int /* fact head */,
/// }
/// ```
///
/// A page without quotes issues no extra statement; a page with quotes
/// issues exactly one (pinner ids merge into the author batch, source
/// message ids into the attachment batch).
Future<void> main() async {
  final target = DisposablePgTarget.fromNamedEnvironment(
    envVarName: 'TENTURA_ROOM_QUOTE_PAGE_PG_TEST_DB',
    defaultNamePrefix: 'tentura_test_room_quote_page',
  );
  final reachable = await canReachPostgresAdmin(target);
  final skipReason = reachable
      ? false as Object
      : 'Postgres admin database not reachable for disposable test target';

  group(
    'BeaconRoomRepository.listMessagesEnriched quotedFact — disposable '
    'Postgres',
    () {
      late DisposablePgWriterSession session;
      late Connection writer;
      late TenturaDb db;
      late _RecordingCounter counter;
      late BeaconRoomRepository room;
      late BeaconFactCardCase facts;

      if (reachable) {
        setUpAll(() async {
          session = await setUpDisposablePgWriter(target: target);
          writer = session.writer;
          await _seed(writer);
          await writer.execute('ANALYZE public.beacon_fact_card');
          await writer.execute('ANALYZE public.beacon_fact_card_revision');

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
          room = BeaconRoomRepository(db);
          facts = BeaconFactCardCase(
            BeaconFactCardRepository(db, room),
            room,
            BeaconHierarchyRepository(db),
            BeaconAccessRepository(db),
            env: Env(environment: Environment.test),
            logger: Logger('BeaconRoomQuotePagePgTest'),
          );
        });

        tearDownAll(() async {
          await tearDownDisposablePgWriter(session: session, drift: db);
        });
      }

      /// The fixed three-message page (m3, m2, m1); the older fact source
      /// message is outside it, so its attachments are only fetched when the
      /// quote batch folds its id into the attachment batch.
      Future<List<Map<String, Object?>>> page() => room.listMessagesEnriched(
        beaconId: _beaconId,
        viewerUserId: _authorId,
        before: _t0.add(const Duration(minutes: 4)),
        limit: 3,
      );

      Future<void> setQuote(String messageId, String? factId, int? seq) =>
          writer.execute(
            Sql.named('''
UPDATE public.beacon_room_message
SET quoted_fact_card_id = @fact, quoted_fact_revision_seq = @seq::integer
WHERE id = @id
'''),
            parameters: {'id': messageId, 'fact': factId, 'seq': seq},
          );

      Future<void> quotePage() async {
        await setQuote(_m1Id, _factAId, 1);
        await setQuote(_m2Id, _factBId, 1);
      }

      Future<void> unquotePage() async {
        await setQuote(_m1Id, null, null);
        await setQuote(_m2Id, null, null);
      }

      Future<int> countPage() async {
        counter.reset();
        final rows = await page();
        expect(rows.map((r) => r['id']), [_m3Id, _m2Id, _m1Id]);
        return counter.count;
      }

      String statements() =>
          counter.selects.map((s) => s.statement).join('\n---\n');

      Map<String, Object?> quotedFactOf(Map<String, Object?> row) {
        final quoted = row['quotedFact'];
        expect(
          quoted,
          isA<Map<String, Object?>>(),
          reason: 'message ${row['id']} must carry a quotedFact map',
        );
        return quoted! as Map<String, Object?>;
      }

      test(
        'a page without quotes costs the baseline; the same page with quotes '
        'costs baseline + 1; removing the quotes returns to the baseline',
        () async {
          await unquotePage();
          final baseline = await countPage();
          final baselineStatements = statements();

          await quotePage();
          try {
            final quoted = await countPage();
            expect(
              quoted,
              baseline + 1,
              reason:
                  'one quote batch; pinner and source ids must merge into '
                  'the existing batches.\nbaseline:\n$baselineStatements\n'
                  '=== quoted:\n${statements()}',
            );
            expect(
              counter.selects.where(
                (s) => s.statement.contains('beacon_fact_card_revision'),
              ),
              hasLength(1),
              reason: statements(),
            );
          } finally {
            await unquotePage();
          }

          final again = await countPage();
          expect(again, baseline, reason: statements());
          expect(
            counter.selects.where(
              (s) => s.statement.contains('beacon_fact_card_revision'),
            ),
            isEmpty,
            reason: 'no quote on the page → no quote batch\n${statements()}',
          );
        },
        skip: skipReason,
      );

      test(
        'quoted messages carry the quoted revision snapshot; plain messages '
        'carry null quotedFact',
        () async {
          await quotePage();
          try {
            final rows = await page();
            final byId = {for (final r in rows) r['id']! as String: r};

            final a = quotedFactOf(byId[_m1Id]!);
            expect(a['factCardId'], _factAId);
            expect(a['seq'], 1);
            expect(a['currentSeq'], 1);
            expect(a['text'], 'Tap water is on');
            expect(a['pinnedById'], _pinnerId);
            expect(a['pinnedByTitle'], 'Pinner Person');
            expect(a['visibility'], BeaconFactCardVisibilityBits.public);
            expect(a['status'], BeaconFactCardStatusBits.active);

            final b = quotedFactOf(byId[_m2Id]!);
            expect(b['factCardId'], _factBId);
            expect(b['seq'], 1);
            expect(b['currentSeq'], 2, reason: 'head moved past the quote');
            expect(
              b['text'],
              'Gate code is 1234',
              reason: 'quoted revision text, not the current head text',
            );
            expect(b['pinnedById'], _pinnerId);
            expect(b['pinnedByTitle'], 'Pinner Person');
            expect(b['visibility'], BeaconFactCardVisibilityBits.room);
            expect(b['status'], BeaconFactCardStatusBits.corrected);

            expect(byId[_m3Id]!['quotedFact'], isNull);
          } finally {
            await unquotePage();
          }
        },
        skip: skipReason,
      );

      test(
        'after a later edit currentSeq ≠ seq and text is still the quoted '
        'revision (roomMessageTarget, limit 1)',
        () async {
          final record = await room.insertRoomMessage(
            beaconId: _beaconId,
            authorId: _authorId,
            body: 'see this fact',
            quotedFactCardId: _factAId,
            quotedFactRevisionSeq: 1,
          );

          final before = await room.roomMessageTarget(
            beaconId: _beaconId,
            messageId: record.id,
            viewerUserId: _authorId,
          );
          expect(before, isNotNull);
          final q1 = quotedFactOf(before!);
          expect(q1['factCardId'], _factAId);
          expect(q1['seq'], 1);
          expect(q1['currentSeq'], 1);
          expect(q1['text'], 'Tap water is on');

          final newSeq = await facts.correct(
            factCardId: _factAId,
            beaconId: _beaconId,
            actorUserId: _pinnerId,
            newText: 'Tap water is off',
            baseRevisionSeq: 1,
          );
          expect(newSeq, 2);

          final after = await room.roomMessageTarget(
            beaconId: _beaconId,
            messageId: record.id,
            viewerUserId: _authorId,
          );
          expect(after, isNotNull);
          final q2 = quotedFactOf(after!);
          expect(q2['factCardId'], _factAId);
          expect(q2['seq'], 1);
          expect(q2['currentSeq'], 2);
          expect(q2['currentSeq'], isNot(q2['seq']));
          expect(
            q2['text'],
            'Tap water is on',
            reason: 'the quote keeps the quoted revision text after an edit',
          );
          expect(q2['status'], BeaconFactCardStatusBits.corrected);
          expect(q2['pinnedById'], _pinnerId);
          expect(q2['pinnedByTitle'], 'Pinner Person');
          expect(q2['visibility'], BeaconFactCardVisibilityBits.public);
        },
        skip: skipReason,
      );

      test(
        'EXPLAIN (enable_seqscan off) of the quote batch uses '
        'beacon_fact_card_revision_seq_uq and beacon_fact_card_pkey',
        () async {
          await quotePage();
          try {
            counter.reset();
            await page();
          } finally {
            await unquotePage();
          }
          final selects = counter.selects
              .where((s) => s.statement.contains('beacon_fact_card_revision'))
              .toList();
          expect(selects, hasLength(1), reason: 'one quote batch');
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
              contains('beacon_fact_card_revision_seq_uq'),
              reason: 'plan:\n$plan',
            );
            expect(
              plan,
              contains('beacon_fact_card_pkey'),
              reason: 'plan:\n$plan',
            );
            expect(
              plan,
              isNot(
                matches(
                  RegExp(
                    r'Seq Scan on (?:public\.)?'
                    r'(?:beacon_fact_card_revision|beacon_fact_card)\b',
                  ),
                ),
              ),
              reason: 'plan:\n$plan',
            );
          } finally {
            await executor.runCustom('RESET enable_seqscan');
          }
        },
        skip: skipReason,
      );
    },
  );
}

// ---------------------------------------------------------------------------
// Fixture: the pinner owns the beacon and pins both facts but authors no
// message on the page; a separate author writes the source message (oldest,
// outside the page) and the three page messages m1..m3. Fact A is active at
// head seq 1; fact B is room-visible, corrected, head seq 2, and was pinned
// from the source message.

const _pinnerId = 'Uqppinner01';
const _authorId = 'Uqpauthor01';

const _beaconId = 'Bqpbeacon01';

const _sourceMsgId = 'Rqpsource01';
const _m1Id = 'Rqpmessage1';
const _m2Id = 'Rqpmessage2';
const _m3Id = 'Rqpmessage3';

const _factAId = 'Fqpfacta001';
const _factBId = 'Fqpfactb001';

final _t0 = DateTime.utc(2026, 3, 1, 12);

Future<void> _seed(Connection writer) async {
  await writer.execute(
    Sql.named('''
INSERT INTO public."user" (id, display_name, public_key)
VALUES (@pinner, 'Pinner Person', @pinnerKey),
       (@author, 'Quote Author', @authorKey)
'''),
    parameters: {
      'pinner': _pinnerId,
      'pinnerKey': pgTestPublicKey('roomquotepage', 1),
      'author': _authorId,
      'authorKey': pgTestPublicKey('roomquotepage', 2),
    },
  );
  await writer.execute(
    Sql.named('''
INSERT INTO public.beacon
  (id, user_id, title, description, status, published_at, is_discoverable)
VALUES (@beacon, @pinner, 't', 'd', 0, @t0, false)
'''),
    parameters: {'beacon': _beaconId, 'pinner': _pinnerId, 't0': _t0},
  );
  for (final (i, id) in [_sourceMsgId, _m1Id, _m2Id, _m3Id].indexed) {
    await writer.execute(
      Sql.named('''
INSERT INTO public.beacon_room_message
  (id, beacon_id, author_id, body, mentions, thread_item_id, created_at)
VALUES (@id, @beacon, @author, @body, ARRAY[]::text[], NULL, @at)
'''),
      parameters: {
        'id': id,
        'beacon': _beaconId,
        'author': _authorId,
        'body': 'message $i',
        'at': _t0.add(Duration(minutes: i)),
      },
    );
  }

  final cards = <(String, String, int, int, int, String?)>[
    (
      _factAId,
      'Tap water is on',
      BeaconFactCardVisibilityBits.public,
      BeaconFactCardStatusBits.active,
      1,
      null,
    ),
    (
      _factBId,
      'Gate code is 4412',
      BeaconFactCardVisibilityBits.room,
      BeaconFactCardStatusBits.corrected,
      2,
      _sourceMsgId,
    ),
  ];
  for (final (id, text, visibility, status, head, source) in cards) {
    await writer.execute(
      Sql.named('''
INSERT INTO public.beacon_fact_card
  (id, beacon_id, fact_text, visibility, pinned_by, source_message_id,
   status, revision_seq, other_editor_count, history_truncated,
   created_at, updated_at)
VALUES
  (@id, @beacon, @text, @visibility, @pinner, @source, @status,
   @head::integer, 0, false, @t0, @t0)
'''),
      parameters: {
        'id': id,
        'beacon': _beaconId,
        'text': text,
        'visibility': visibility,
        'pinner': _pinnerId,
        'source': source,
        'status': status,
        'head': head,
        't0': _t0,
      },
    );
  }

  final revisions = <(String, String, int, String, int)>[
    (
      'Vqpfacta1',
      _factAId,
      1,
      'Tap water is on',
      BeaconFactCardRevisionKindBits.created,
    ),
    (
      'Vqpfactb1',
      _factBId,
      1,
      'Gate code is 1234',
      BeaconFactCardRevisionKindBits.created,
    ),
    (
      'Vqpfactb2',
      _factBId,
      2,
      'Gate code is 4412',
      BeaconFactCardRevisionKindBits.edited,
    ),
  ];
  for (final (id, factId, seq, text, kind) in revisions) {
    await writer.execute(
      Sql.named('''
INSERT INTO public.beacon_fact_card_revision
  (id, fact_card_id, seq, fact_text, actor_id, kind, created_at)
VALUES (@id, @fact, @seq::integer, @text, @actor, @kind::integer, @at)
'''),
      parameters: {
        'id': id,
        'fact': factId,
        'seq': seq,
        'text': text,
        'actor': _pinnerId,
        'kind': kind,
        'at': _t0.add(Duration(seconds: seq)),
      },
    );
  }
}

/// Counts every statement (see [QueryCounter]) and records each select so a
/// test can EXPLAIN the quote batch the page actually issued, on the same
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
