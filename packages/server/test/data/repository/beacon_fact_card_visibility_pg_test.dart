@Tags(['pg'])
library;

import 'package:drift_postgres/drift_postgres.dart';
import 'package:injectable/injectable.dart' show Environment;
import 'package:logging/logging.dart';
import 'package:postgres/postgres.dart';
import 'package:test/test.dart';

import 'package:tentura_server/consts/beacon_activity_event_consts.dart';
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

/// tentura-617.7 (issue #181 plan §8.3 "Set visibility", §14.3
/// setVisibility, §14.4): toggling a fact's visibility is one CTE inside
/// `withMutatingUser` that updates the card and writes one
/// `factVisibilityChanged` event carrying the `fact_card_id` column and a
/// `previousVisibility`/`visibility` diff. A visibility-only change does not
/// advance `revision_seq` and writes no revision.
///
/// `BeaconFactCardCase.setVisibility` costs exactly 5 statements: the fused
/// `loadRoomAccess` preflight, BEGIN, the `set_config` actor line, the CTE and
/// COMMIT.
Future<void> main() async {
  final target = DisposablePgTarget.fromNamedEnvironment(
    envVarName: 'TENTURA_FACT_VISIBILITY_PG_TEST_DB',
    defaultNamePrefix: 'tentura_test_fact_visibility',
  );
  final reachable = await canReachPostgresAdmin(target);
  final skipReason = reachable
      ? false as Object
      : 'Postgres admin database not reachable for disposable test target';

  group('BeaconFactCardCase.setVisibility — disposable Postgres', () {
    late DisposablePgWriterSession session;
    late Connection writer;
    late TenturaDb db;
    late QueryCounter counter;
    late BeaconFactCardCase useCase;

    if (reachable) {
      setUpAll(() async {
        session = await setUpDisposablePgWriter(target: target);
        writer = session.writer;
        await _seed(writer);

        counter = QueryCounter();
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
        useCase = BeaconFactCardCase(
          BeaconFactCardRepository(db, room),
          room,
          BeaconHierarchyRepository(db),
          BeaconAccessRepository(db),
          env: Env(environment: Environment.test),
          logger: Logger('BeaconFactCardVisibilityPgTest'),
        );
      });

      tearDownAll(() async {
        await tearDownDisposablePgWriter(session: session, drift: db);
      });
    }

    Future<int> countOf(String sql, Map<String, Object?> parameters) async {
      final rows = await writer.execute(Sql.named(sql), parameters: parameters);
      return rows.single.single! as int;
    }

    Future<List<ResultRow>> visibilityEvents(String factId) async =>
        writer.execute(
          Sql.named('''
SELECT fact_card_id, actor_id, visibility, source_message_id,
       diff->>'factCardId',
       (diff->>'previousVisibility')::integer,
       (diff->>'visibility')::integer
FROM public.beacon_activity_event
WHERE beacon_id = @beacon
  AND type = ${BeaconActivityEventTypeBits.factVisibilityChanged}
  AND diff->>'factCardId' = @id
'''),
          parameters: {'beacon': _beaconId, 'id': factId},
        );

    test(
      'toggling visibility writes one factVisibilityChanged event carrying '
      'fact_card_id and a previousVisibility/visibility diff',
      () async {
        final ok = await useCase.setVisibility(
          factCardId: _factEventId,
          beaconId: _beaconId,
          actorUserId: _authorId,
          visibility: BeaconFactCardVisibilityBits.room,
        );
        expect(ok, isTrue);

        final fact = await writer.execute(
          Sql.named(
            'SELECT visibility FROM public.beacon_fact_card WHERE id = @id',
          ),
          parameters: {'id': _factEventId},
        );
        expect(fact.single.single, BeaconFactCardVisibilityBits.room);

        final events = await visibilityEvents(_factEventId);
        expect(events, hasLength(1), reason: 'one event per toggle');
        final event = events.single;
        expect(
          event[0],
          _factEventId,
          reason: 'factVisibilityChanged event must carry the fact_card_id '
              'column',
        );
        expect(event[1], _authorId, reason: 'actor');
        expect(
          event[2],
          BeaconActivityEventVisibilityBits.room,
          reason: 'event visibility follows the new fact visibility',
        );
        expect(event[3], _sourceEventId, reason: 'source message');
        expect(event[4], _factEventId, reason: 'diff.factCardId');
        expect(
          event[5],
          BeaconFactCardVisibilityBits.public,
          reason: 'diff.previousVisibility',
        );
        expect(
          event[6],
          BeaconFactCardVisibilityBits.room,
          reason: 'diff.visibility',
        );
      },
      skip: skipReason,
    );

    test(
      'toggling visibility leaves revision_seq unchanged and writes no '
      'revision',
      () async {
        await useCase.setVisibility(
          factCardId: _factRevisionId,
          beaconId: _beaconId,
          actorUserId: _authorId,
          visibility: BeaconFactCardVisibilityBits.public,
        );

        final fact = await writer.execute(
          Sql.named('''
SELECT visibility, revision_seq
FROM public.beacon_fact_card WHERE id = @id
'''),
          parameters: {'id': _factRevisionId},
        );
        expect(fact.single[0], BeaconFactCardVisibilityBits.public);
        expect(
          fact.single[1],
          _seededRevisionSeq,
          reason: 'visibility-only change must not bump revision_seq',
        );
        expect(
          await countOf(
            '''
SELECT count(*)::integer FROM public.beacon_fact_card_revision
WHERE fact_card_id = @id
''',
            {'id': _factRevisionId},
          ),
          0,
          reason: 'visibility-only change must not write a revision',
        );

        final events = await visibilityEvents(_factRevisionId);
        expect(events, hasLength(1));
        expect(events.single[0], _factRevisionId);
        expect(events.single[5], BeaconFactCardVisibilityBits.room);
        expect(events.single[6], BeaconFactCardVisibilityBits.public);
      },
      skip: skipReason,
    );

    test(
      'setVisibility through the use case costs exactly 5 statements',
      () async {
        counter.reset();
        await useCase.setVisibility(
          factCardId: _factCountId,
          beaconId: _beaconId,
          actorUserId: _authorId,
          visibility: BeaconFactCardVisibilityBits.room,
        );
        expect(
          counter.count,
          5,
          reason:
              'loadRoomAccess + BEGIN + set_config + one visibility CTE + '
              'COMMIT',
        );
        expect(await visibilityEvents(_factCountId), hasLength(1));
      },
      skip: skipReason,
    );
  });
}

// ---------------------------------------------------------------------------
// Fixture: one published beacon authored by the actor (so the actor can use
// the room), one source message and one fact per test. Facts start at
// revision_seq 3 so an accidental bump or reset is visible.

const _authorId = 'Ufvauthor01';

const _beaconId = 'Bfvbeacon01';

const _sourceEventId = 'Rfvsrcevt01';

const _factEventId = 'Ffvfactevt1';
const _factRevisionId = 'Ffvfactrev1';
const _factCountId = 'Ffvfactcnt1';

const _seededRevisionSeq = 3;

final _t0 = DateTime.utc(2026, 3, 1, 12);

Future<void> _seed(Connection writer) async {
  await writer.execute(
    Sql.named('''
INSERT INTO public."user" (id, display_name, public_key)
VALUES (@id, 'Fact Author', @key)
'''),
    parameters: {'id': _authorId, 'key': pgTestPublicKey('factvis', 1)},
  );
  await writer.execute(
    Sql.named('''
INSERT INTO public.beacon
  (id, user_id, title, description, status, published_at, is_discoverable)
VALUES (@beacon, @author, 't', 'd', 0, @t0, false)
'''),
    parameters: {'beacon': _beaconId, 'author': _authorId, 't0': _t0},
  );
  await writer.execute(
    Sql.named('''
INSERT INTO public.beacon_room_message (id, beacon_id, author_id, body)
VALUES (@src, @beacon, @author, 'event source')
'''),
    parameters: {
      'src': _sourceEventId,
      'beacon': _beaconId,
      'author': _authorId,
    },
  );
  await writer.execute(
    Sql.named('''
INSERT INTO public.beacon_fact_card
  (id, beacon_id, fact_text, visibility, pinned_by, source_message_id,
   status, revision_seq)
VALUES
  (@evt, @beacon, 'event fact', @public, @author, @src, @active, @seq),
  (@rev, @beacon, 'revision fact', @room, @author, NULL, @active, @seq),
  (@cnt, @beacon, 'count fact', @public, @author, NULL, @active, @seq)
'''),
    parameters: {
      'evt': _factEventId,
      'rev': _factRevisionId,
      'cnt': _factCountId,
      'beacon': _beaconId,
      'author': _authorId,
      'src': _sourceEventId,
      'public': BeaconFactCardVisibilityBits.public,
      'room': BeaconFactCardVisibilityBits.room,
      'active': BeaconFactCardStatusBits.active,
      'seq': _seededRevisionSeq,
    },
  );
}
