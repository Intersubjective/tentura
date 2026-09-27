@Tags(['pg'])
library;

import 'package:drift_postgres/drift_postgres.dart';
import 'package:injectable/injectable.dart' show Environment;
import 'package:logging/logging.dart';
import 'package:postgres/postgres.dart';
import 'package:mockito/mockito.dart';
import 'package:test/test.dart';

import 'package:tentura_server/consts/beacon_activity_event_consts.dart';
import 'package:tentura_server/consts/beacon_fact_card_consts.dart';
import 'package:tentura_server/consts/beacon_room_consts.dart';
import 'package:tentura_server/data/database/tentura_db.dart'
    hide isNotNull, isNull;
import 'package:tentura_server/data/repository/beacon_access_repository.dart';
import 'package:tentura_server/data/repository/beacon_fact_card_repository.dart';
import 'package:tentura_server/data/repository/beacon_hierarchy_repository.dart';
import 'package:tentura_server/data/repository/beacon_room_repository.dart';
import 'package:tentura_server/domain/use_case/beacon_fact_card_case.dart';
import 'package:tentura_server/env.dart';
import 'package:tentura_server/domain/port/image_repository_port.dart';
import 'package:tentura_server/domain/port/task_repository_port.dart';

import '../../support/disposable_pg_target.dart';
import '../../support/pg_test_public_keys.dart';
import '../../support/query_counter.dart';

/// tentura-617.12 (issue #181 plan §8.3 "Unpin", §14.4 rule 12): removing a
/// fact is one CTE inside `withMutatingUser` that locks the fact, sets its
/// status to removed, clears `linked_fact_card_id` on the source message by
/// primary key (never `WHERE linked_fact_card_id = …`), writes one marker-11
/// room line (`factCardId`/`pinnedBy`/`factText`, text left 160) and one
/// `factRemoved` (type 20) event carrying the `fact_card_id` column.
///
/// `BeaconFactCardCase.remove` returns true only when this call unpinned the
/// fact and costs exactly 5 statements: the fused `loadRoomAccess` preflight,
/// BEGIN, the `set_config` actor line, the CTE and COMMIT.
Future<void> main() async {
  final target = DisposablePgTarget.fromNamedEnvironment(
    envVarName: 'TENTURA_FACT_UNPIN_PG_TEST_DB',
    defaultNamePrefix: 'tentura_test_fact_unpin',
  );
  final reachable = await canReachPostgresAdmin(target);
  final skipReason = reachable
      ? false as Object
      : 'Postgres admin database not reachable for disposable test target';

  group('BeaconFactCardCase.remove — disposable Postgres', () {
    late DisposablePgWriterSession session;
    late Connection writer;
    late TenturaDb db;
    late _RecordingCounter counter;
    late BeaconFactCardRepository repository;
    late BeaconFactCardCase useCase;

    if (reachable) {
      setUpAll(() async {
        session = await setUpDisposablePgWriter(target: target);
        writer = session.writer;
        await _seed(writer);

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
        final room = BeaconRoomRepository(db);
        repository = BeaconFactCardRepository(db, room);
        useCase = BeaconFactCardCase(
          repository,
          room,
          _UnusedImage(),
          _UnusedTasks(),
          BeaconHierarchyRepository(db),
          BeaconAccessRepository(db),
          env: Env(environment: Environment.test),
          logger: Logger('BeaconFactCardUnpinPgTest'),
        );
      });

      tearDownAll(() async {
        await tearDownDisposablePgWriter(session: session, drift: db);
      });
    }

    Future<List<ResultRow>> unpinLines(String factId) async => writer.execute(
      Sql.named('''
SELECT author_id, system_payload
FROM public.beacon_room_message
WHERE beacon_id = @beacon
  AND semantic_marker = ${BeaconRoomSemanticMarker.factUnpinned}
  AND system_payload->>'factCardId' = @id
'''),
      parameters: {'beacon': _beaconId, 'id': factId},
    );

    Future<List<ResultRow>> removedEvents(String factId) async =>
        writer.execute(
          Sql.named('''
SELECT fact_card_id, actor_id
FROM public.beacon_activity_event
WHERE beacon_id = @beacon
  AND type = ${BeaconActivityEventTypeBits.factRemoved}
  AND fact_card_id = @id
'''),
          parameters: {'beacon': _beaconId, 'id': factId},
        );

    Future<Object?> linkedFactOf(String messageId) async {
      final rows = await writer.execute(
        Sql.named(
          'SELECT linked_fact_card_id FROM public.beacon_room_message '
          'WHERE id = @id',
        ),
        parameters: {'id': messageId},
      );
      return rows.single.single;
    }

    Future<Object?> statusOf(String factId) async {
      final rows = await writer.execute(
        Sql.named('SELECT status FROM public.beacon_fact_card WHERE id = @id'),
        parameters: {'id': factId},
      );
      return rows.single.single;
    }

    test(
      'remove sets status removed, unlinks the source message, writes one '
      'marker-11 line and one type-20 event with fact_card_id',
      () async {
        final removed = await useCase.remove(
          factCardId: _factMainId,
          beaconId: _beaconId,
          actorUserId: _authorId,
        );
        expect(removed, isTrue, reason: 'this call unpinned the fact');

        expect(await statusOf(_factMainId), BeaconFactCardStatusBits.removed);
        expect(
          await linkedFactOf(_srcMainId),
          isNull,
          reason: 'source message must no longer link the fact',
        );

        final lines = await unpinLines(_factMainId);
        expect(lines, hasLength(1), reason: 'one marker-11 line');
        expect(lines.single[0], _authorId, reason: 'line author is the actor');
        final payload = lines.single[1]! as Map<String, dynamic>;
        expect(
          payload.keys.toSet(),
          {'factCardId', 'pinnedBy', 'factText'},
          reason: 'system_payload keys must be exactly these three',
        );
        expect(payload['factCardId'], _factMainId);
        expect(payload['pinnedBy'], _pinnerId);
        expect(
          payload['factText'],
          _longFactText.substring(0, 160),
          reason: 'factText is left(fact_text, 160) like the edit line',
        );

        final events = await removedEvents(_factMainId);
        expect(events, hasLength(1), reason: 'one type-20 event');
        expect(
          events.single[0],
          _factMainId,
          reason: 'factRemoved event must carry the fact_card_id column',
        );
        expect(events.single[1], _authorId, reason: 'actor');
      },
      skip: skipReason,
    );

    test(
      'a second remove returns false and writes nothing',
      () async {
        final first = await useCase.remove(
          factCardId: _factTwiceId,
          beaconId: _beaconId,
          actorUserId: _authorId,
        );
        expect(first, isTrue);
        final updatedAt = await writer.execute(
          Sql.named(
            'SELECT updated_at FROM public.beacon_fact_card WHERE id = @id',
          ),
          parameters: {'id': _factTwiceId},
        );

        final second = await useCase.remove(
          factCardId: _factTwiceId,
          beaconId: _beaconId,
          actorUserId: _authorId,
        );
        expect(
          second,
          isFalse,
          reason: 'only the call that unpinned the fact returns true',
        );
        expect(
          await unpinLines(_factTwiceId),
          hasLength(1),
          reason: 'no second marker-11 line',
        );
        expect(
          await removedEvents(_factTwiceId),
          hasLength(1),
          reason: 'no second type-20 event',
        );
        final updatedAtAfter = await writer.execute(
          Sql.named(
            'SELECT updated_at FROM public.beacon_fact_card WHERE id = @id',
          ),
          parameters: {'id': _factTwiceId},
        );
        expect(
          updatedAtAfter.single.single,
          updatedAt.single.single,
          reason: 'an already-removed fact is not touched again',
        );
        expect(await statusOf(_factTwiceId), BeaconFactCardStatusBits.removed);
      },
      skip: skipReason,
    );

    test(
      'remove through the use case costs exactly 5 statements, the '
      'preflight being the fused loadRoomAccess query',
      () async {
        // Capture the exact statement loadRoomAccess issues so the preflight
        // of remove can be compared against it.
        counter.reset();
        await repository.loadRoomAccess(
          beaconId: _beaconId,
          userId: _authorId,
        );
        expect(counter.selects, hasLength(1));
        final loadRoomAccessSql = counter.selects.single.statement;

        counter.reset();
        final removed = await useCase.remove(
          factCardId: _factCountId,
          beaconId: _beaconId,
          actorUserId: _authorId,
        );
        expect(removed, isTrue);
        expect(
          counter.count,
          5,
          reason: 'loadRoomAccess + BEGIN + set_config + one remove CTE + '
              'COMMIT',
        );
        expect(
          counter.selectsBeforeFirstBegin,
          1,
          reason: 'exactly one preflight statement before BEGIN',
        );
        final preflight = counter.selects.first;
        expect(
          preflight.statement,
          loadRoomAccessSql,
          reason: 'the preflight must be the fused loadRoomAccess query, not '
              'hierarchy/lifecycle or other access reads',
        );
        expect(preflight.args, [_beaconId, _authorId]);
        expect(await removedEvents(_factCountId), hasLength(1));
      },
      skip: skipReason,
    );

    test(
      'EXPLAIN (enable_seqscan off) of the unlink UPDATE uses '
      'beacon_room_message_pkey',
      () async {
        counter.reset();
        await useCase.remove(
          factCardId: _factExplainId,
          beaconId: _beaconId,
          actorUserId: _authorId,
        );
        final selects = counter.selects
            .where(
              (s) =>
                  RegExp(
                    r'UPDATE\s+(?:public\.)?beacon_room_message\b',
                    caseSensitive: false,
                  ).hasMatch(s.statement),
            )
            .toList();
        expect(
          selects,
          hasLength(1),
          reason: 'remove issues the unlink UPDATE inside one customSelect '
              'CTE',
        );
        final select = selects.single;
        // Scope to the unlink UPDATE onward: earlier CTEs' WHERE clauses would
        // otherwise pair with its `SET linked_fact_card_id = NULL`.
        final unlinkSql = select.statement.substring(
          select.statement.indexOf(
            RegExp(
              r'UPDATE\s+(?:public\.)?beacon_room_message\b',
              caseSensitive: false,
            ),
          ),
        );
        expect(
          unlinkSql,
          isNot(contains(RegExp(r'WHERE[^;]*linked_fact_card_id\s*='))),
          reason: 'rule 12: unlink by primary key, never by '
              'linked_fact_card_id',
        );

        // EXPLAIN without ANALYZE plans the data-modifying CTE without
        // running it; SET LOCAL keeps enable_seqscan on this transaction.
        final plan = await writer.runTx((tx) async {
          await tx.execute('SET LOCAL enable_seqscan = off');
          final shown = await tx.execute('SHOW enable_seqscan');
          expect(shown.single.single, 'off');
          final rows = await tx.execute(
            'EXPLAIN (COSTS OFF) ${select.statement}',
            parameters: select.args,
          );
          return rows.map((r) => r.single).join('\n');
        });
        expect(
          plan,
          contains('beacon_room_message_pkey'),
          reason: 'plan:\n$plan',
        );
        expect(
          plan,
          isNot(contains('beacon_room_message_linked_fact_idx')),
          reason: 'plan:\n$plan',
        );
        expect(
          plan,
          isNot(matches(RegExp(r'Seq Scan on (?:public\.)?beacon_room_message'
              r'\b'))),
          reason: 'plan:\n$plan',
        );
      },
      skip: skipReason,
    );
  });
}

/// Counts statements like [QueryCounter] and records every Drift select so
/// the test can EXPLAIN the CTE `remove` actually issued, with its binds.
class _RecordingCounter extends QueryCounter {
  final selects = <({String statement, List<Object?> args})>[];

  /// Number of selects recorded when the first transaction began since the
  /// last [reset]; null when no transaction began.
  int? selectsBeforeFirstBegin;

  @override
  void reset() {
    super.reset();
    selects.clear();
    selectsBeforeFirstBegin = null;
  }

  @override
  TransactionExecutor beginTransaction(QueryExecutor parent) {
    selectsBeforeFirstBegin ??= selects.length;
    return super.beginTransaction(parent);
  }

  @override
  Future<List<Map<String, Object?>>> runSelect(
    QueryExecutor executor,
    String statement,
    List<Object?> args,
  ) {
    selects.add((statement: statement, args: List.of(args)));
    return super.runSelect(executor, statement, args);
  }
}

// ---------------------------------------------------------------------------
// Fixture: one published beacon authored by the actor (so the actor can use
// the room), a separate pinner, and per test one live fact pinned from its
// own source message which links back to it.

const _authorId = 'Ufuauthor01';
const _pinnerId = 'Ufupinner01';

const _beaconId = 'Bfubeacon01';

const _srcMainId = 'Rfusrcmain1';
const _srcTwiceId = 'Rfusrctwic1';
const _srcCountId = 'Rfusrccnt01';
const _srcExplainId = 'Rfusrcexp01';

const _factMainId = 'Ffufactmai1';
const _factTwiceId = 'Ffufacttwi1';
const _factCountId = 'Ffufactcnt1';
const _factExplainId = 'Ffufactexp1';

final _longFactText = 'Water tap moved to the square. ' * 8;

final _t0 = DateTime.utc(2026, 3, 1, 12);

Future<void> _seed(Connection writer) async {
  await writer.execute(
    Sql.named('''
INSERT INTO public."user" (id, display_name, public_key)
VALUES (@author, 'Fact Author', @authorKey),
       (@pinner, 'Fact Pinner', @pinnerKey)
'''),
    parameters: {
      'author': _authorId,
      'authorKey': pgTestPublicKey('factunpin', 1),
      'pinner': _pinnerId,
      'pinnerKey': pgTestPublicKey('factunpin', 2),
    },
  );
  await writer.execute(
    Sql.named('''
INSERT INTO public.beacon
  (id, user_id, title, description, status, published_at, is_discoverable)
VALUES (@beacon, @author, 't', 'd', 0, @t0, false)
'''),
    parameters: {'beacon': _beaconId, 'author': _authorId, 't0': _t0},
  );
  const pairs = [
    (_srcMainId, _factMainId),
    (_srcTwiceId, _factTwiceId),
    (_srcCountId, _factCountId),
    (_srcExplainId, _factExplainId),
  ];
  for (final (src, fact) in pairs) {
    await writer.execute(
      Sql.named('''
INSERT INTO public.beacon_room_message (id, beacon_id, author_id, body)
VALUES (@src, @beacon, @pinner, 'fact source')
'''),
      parameters: {'src': src, 'beacon': _beaconId, 'pinner': _pinnerId},
    );
    await writer.execute(
      Sql.named('''
INSERT INTO public.beacon_fact_card
  (id, beacon_id, fact_text, visibility, pinned_by, source_message_id,
   status)
VALUES (@fact, @beacon, @text, @public, @pinner, @src, @active)
'''),
      parameters: {
        'fact': fact,
        'beacon': _beaconId,
        'text': fact == _factMainId ? _longFactText : 'short fact',
        'public': BeaconFactCardVisibilityBits.public,
        'pinner': _pinnerId,
        'src': src,
        'active': BeaconFactCardStatusBits.active,
      },
    );
    await writer.execute(
      Sql.named('''
UPDATE public.beacon_room_message SET linked_fact_card_id = @fact
WHERE id = @src
'''),
      parameters: {'fact': fact, 'src': src},
    );
  }
}

class _UnusedImage extends Fake implements ImageRepositoryPort {}

class _UnusedTasks extends Fake implements TaskRepositoryPort {}

