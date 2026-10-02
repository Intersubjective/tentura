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

/// tentura-p4q: `BeaconRoomRepository.insertActivityEvent` must be able to
/// write `beacon_activity_event.fact_card_id` (m0199). Without it, fact-scoped
/// events inserted through the port are invisible to the fact history UNION,
/// which selects events by `fact_card_id`.
///
/// Contract under test: an optional `String? factCardId` named parameter that
/// is stored in `fact_card_id` (and stays NULL when omitted).
Future<void> main() async {
  final target = DisposablePgTarget.fromNamedEnvironment(
    envVarName: 'TENTURA_INSERT_ACTIVITY_FACT_PG_TEST_DB',
    defaultNamePrefix: 'tentura_test_insert_activity_fact',
  );
  final reachable = await canReachPostgresAdmin(target);
  final skipReason = reachable
      ? false as Object
      : 'Postgres admin database not reachable for disposable test target';

  group('BeaconRoomRepository.insertActivityEvent fact_card_id', () {
    late DisposablePgWriterSession session;
    late Connection writer;
    late TenturaDb db;
    late BeaconRoomRepository room;

    if (reachable) {
      setUpAll(() async {
        session = await setUpDisposablePgWriter(target: target);
        writer = session.writer;
        await _seed(writer);
        db = TenturaDb.forTest(
          database: PgDatabase.opened(
            Pool<dynamic>.withEndpoints(
              [target.databaseEnv.pgEndpoint],
              settings: target.databaseEnv.pgPoolSettings,
            ),
            enableMigrations: false,
          ),
        );
        room = BeaconRoomRepository(db);
      });

      tearDownAll(() async {
        await tearDownDisposablePgWriter(session: session, drift: db);
      });
    }

    test(
      'persists factCardId into beacon_activity_event.fact_card_id',
      () async {
        await room.insertActivityEvent(
          beaconId: _beaconId,
          visibility: BeaconActivityEventVisibilityBits.room,
          type: BeaconActivityEventTypeBits.factEdited,
          actorId: _actorId,
          factCardId: _factId,
          diff: const <String, Object?>{'factCardId': _factId},
        );

        final rows = await writer.execute(
          Sql.named('''
SELECT fact_card_id FROM public.beacon_activity_event
WHERE beacon_id = @beacon AND type = @type
'''),
          parameters: {
            'beacon': _beaconId,
            'type': BeaconActivityEventTypeBits.factEdited,
          },
        );
        expect(rows, hasLength(1));
        expect(rows.single.single, _factId);
      },
      skip: skipReason,
    );

    test(
      'event written with factCardId appears in the fact history',
      () async {
        await room.insertActivityEvent(
          beaconId: _beaconId,
          visibility: BeaconActivityEventVisibilityBits.room,
          type: BeaconActivityEventTypeBits.factRemoved,
          actorId: _actorId,
          factCardId: _factId,
        );

        final history = await BeaconFactCardRepository(db, room).history(
          factCardId: _factId,
          limit: 50,
        );
        final events = history.whereType<BeaconFactHistoryEvent>();
        expect(
          events.map((e) => e.type),
          contains(BeaconActivityEventTypeBits.factRemoved),
        );
      },
      skip: skipReason,
    );

    test(
      'leaves fact_card_id NULL when factCardId is omitted',
      () async {
        await room.insertActivityEvent(
          beaconId: _beaconId,
          visibility: BeaconActivityEventVisibilityBits.room,
          type: BeaconActivityEventTypeBits.doneMarked,
          actorId: _actorId,
          diff: const <String, Object?>{'kind': 'message'},
        );

        final rows = await writer.execute(
          Sql.named('''
SELECT fact_card_id FROM public.beacon_activity_event
WHERE beacon_id = @beacon AND type = @type
'''),
          parameters: {
            'beacon': _beaconId,
            'type': BeaconActivityEventTypeBits.doneMarked,
          },
        );
        expect(rows, hasLength(1));
        expect(rows.single.single, isNull);
      },
      skip: skipReason,
    );
  });
}

const _actorId = 'Uiaeactor001';
const _beaconId = 'Biaebeacon01';
const _factId = 'Fiaefact0001';

Future<void> _seed(Connection writer) async {
  await writer.execute(
    Sql.named('''
INSERT INTO public."user" (id, display_name, public_key)
VALUES (@id, 'Actor', @key)
'''),
    parameters: {'id': _actorId, 'key': pgTestPublicKey('insactfact', 1)},
  );
  await writer.execute(
    Sql.named(
      'INSERT INTO public.beacon (id, user_id, title, description) '
      "VALUES (@id, @user, 't', 'd')",
    ),
    parameters: {'id': _beaconId, 'user': _actorId},
  );
  await writer.execute(
    Sql.named('''
INSERT INTO public.beacon_fact_card
  (id, beacon_id, fact_text, visibility, pinned_by, status, revision_seq)
VALUES
  (@fact, @beacon, 'Fact v1', 0, @actor, ${BeaconFactCardStatusBits.active}, 1)
'''),
    parameters: {'fact': _factId, 'beacon': _beaconId, 'actor': _actorId},
  );
}
