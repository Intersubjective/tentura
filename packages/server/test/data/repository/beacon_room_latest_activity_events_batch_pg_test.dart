@Tags(['pg'])
library;

import 'package:drift_postgres/drift_postgres.dart';
import 'package:postgres/postgres.dart';
import 'package:test/test.dart';

import 'package:tentura_server/consts/beacon_activity_event_consts.dart';
import 'package:tentura_server/consts/beacon_room_consts.dart';
import 'package:tentura_server/data/database/tentura_db.dart'
    hide isNotNull, isNull;
import 'package:tentura_server/data/repository/beacon_room_repository.dart';

import '../../support/disposable_pg_target.dart';
import '../../support/query_counter.dart';

/// My Work "last activity" line for a page of Requests
/// (`BeaconRoomRepository.latestActivityEventsByBeaconIds`, behind the
/// `MyWorkLastActivityEvent` GraphQL query).
///
/// The whole page must be served by a bounded number of SQL statements: the
/// cost may not grow with the number of Requests on the page. Results keep
/// the per-viewer visibility rule — room-visible events only for the author,
/// stewards and admitted participants, public events for everyone else.
Future<void> main() async {
  final target = DisposablePgTarget.fromNamedEnvironment(
    envVarName: 'TENTURA_ROOM_LATEST_ACTIVITY_PG_TEST_DB',
    defaultNamePrefix: 'tentura_test_room_latest_activity',
  );
  final reachable = await canReachPostgresAdmin(target);
  final skipReason = reachable
      ? false as Object
      : 'Postgres admin database not reachable for disposable test target';

  group(
    'BeaconRoomRepository.latestActivityEventsByBeaconIds — disposable '
    'Postgres',
    () {
      late DisposablePgWriterSession session;
      late TenturaDb db;
      late QueryCounter counter;
      late BeaconRoomRepository room;

      if (reachable) {
        setUpAll(() async {
          session = await setUpDisposablePgWriter(target: target);
          await _seed(session.writer);

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
          room = BeaconRoomRepository(db);
        });

        tearDownAll(() async {
          await tearDownDisposablePgWriter(session: session, drift: db);
        });
      }

      Future<int> statementsFor(List<String> beaconIds) async {
        counter.reset();
        final rows = await room.latestActivityEventsByBeaconIds(
          beaconIds: beaconIds,
          viewerUserId: _viewerId,
        );
        expect(rows, hasLength(beaconIds.length));
        return counter.count;
      }

      test(
        'statement count does not grow with the number of Requests on the '
        'page',
        () async {
          final small = await statementsFor(
            _beaconIds.take(_smallPage).toList(),
          );
          final large = await statementsFor(_beaconIds);

          expect(
            large,
            small,
            reason:
                '$_smallPage Requests took $small statements, '
                '${_beaconIds.length} took $large',
          );
        },
        skip: skipReason,
      );

      test(
        'each Request gets the newest meaningful event the viewer may see, '
        'in the order requested',
        () async {
          final ids = _beaconIds.reversed.toList();
          final rows = await room.latestActivityEventsByBeaconIds(
            beaconIds: ids,
            viewerUserId: _viewerId,
          );

          expect(rows.map((r) => r.beaconId), ids);
          for (final row in rows) {
            final i = _beaconIds.indexOf(row.beaconId);
            if (i == _noEventsIndex) {
              expect(row.event, isNull, reason: row.beaconId);
              expect(row.actorTitle, isNull, reason: row.beaconId);
              expect(row.actorImageId, isNull, reason: row.beaconId);
              continue;
            }
            final event = row.event;
            expect(event, isNotNull, reason: row.beaconId);
            if (_viewerSeesRoom(i)) {
              expect(event!.id, _roomEventId(i), reason: row.beaconId);
              expect(
                event.type,
                BeaconActivityEventTypeBits.blockerOpened,
                reason: row.beaconId,
              );
              expect(
                event.visibility,
                BeaconActivityEventVisibilityBits.room,
              );
              expect(event.actorId, _roomActorId(i), reason: row.beaconId);
              expect(row.actorTitle, 'Room actor $i', reason: row.beaconId);
              expect(
                row.actorImageId,
                _roomActorImageId(i),
                reason: row.beaconId,
              );
            } else {
              expect(event!.id, _publicEventId(i), reason: row.beaconId);
              expect(
                event.type,
                BeaconActivityEventTypeBits.planUpdated,
                reason: row.beaconId,
              );
              expect(
                event.visibility,
                BeaconActivityEventVisibilityBits.public,
              );
              expect(event.actorId, _publicActorId(i), reason: row.beaconId);
              expect(
                row.actorTitle,
                'Public actor $i',
                reason: row.beaconId,
              );
              expect(
                row.actorImageId,
                _publicActorImageId(i),
                reason: row.beaconId,
              );
            }
          }
        },
        skip: skipReason,
      );
    },
  );
}

// ---------------------------------------------------------------------------
// Fixture: [_pageSize] Requests seen by one viewer in four relationships —
// author, steward, admitted participant, outsider. Every Request carries a
// public event (older), a room event (newer) and a newest event whose type is
// not part of the activity log; each event has its own actor, and every actor
// has a profile picture of their own. One Request has
// no events at all.

const _viewerId = 'Ulatviewer01';

const _pageSize = 24;
const _smallPage = 4;
const _noEventsIndex = 5;

final _t0 = DateTime.utc(2026, 3, 1, 12);

final _beaconIds = [for (var i = 0; i < _pageSize; i++) 'Blatbeacon${_two(i)}'];

String _two(int i) => i.toString().padLeft(2, '0');

String _ownerId(int i) => 'Ulatowner${_two(i)}';
String _publicActorId(int i) => 'Ulatpubact${_two(i)}';
String _roomActorId(int i) => 'Ulatroomact${_two(i)}';
String _publicEventId(int i) => 'Vlatpublic${_two(i)}';
String _roomEventId(int i) => 'Vlatroom${_two(i)}';
String _publicActorImageId(int i) =>
    '00000000-0000-0000-aaaa-0000000000${_two(i)}';
String _roomActorImageId(int i) =>
    '00000000-0000-0000-bbbb-0000000000${_two(i)}';
String _noiseEventId(int i) => 'Vlatnoise${_two(i)}';

/// i % 4: 0 author, 1 steward, 2 admitted participant, 3 outsider.
bool _viewerSeesRoom(int i) => i % 4 != 3;

String _key(int n) => 'k${n.toString().padLeft(3, '0')}'.padRight(44, 'x');

Future<void> _seed(Connection writer) async {
  var keyIndex = 0;
  Future<void> user(String id, String name) => writer.execute(
    Sql.named('''
INSERT INTO public."user" (id, display_name, public_key)
VALUES (@id, @name, @key)
'''),
    parameters: {'id': id, 'name': name, 'key': _key(keyIndex++)},
  );

  await user(_viewerId, 'Latest Viewer');

  for (var i = 0; i < _pageSize; i++) {
    final b = _beaconIds[i];
    // The viewer authors every fourth Request; others are owned by strangers.
    final authorId = i % 4 == 0 ? _viewerId : _ownerId(i);
    if (authorId != _viewerId) {
      await user(authorId, 'Owner $i');
    }
    await user(_publicActorId(i), 'Public actor $i');
    await user(_roomActorId(i), 'Room actor $i');
    for (final (actor, image) in [
      (_publicActorId(i), _publicActorImageId(i)),
      (_roomActorId(i), _roomActorImageId(i)),
    ]) {
      await writer.execute(
        Sql.named(
          'INSERT INTO public.image (id, author_id) VALUES (@image, @actor)',
        ),
        parameters: {'image': image, 'actor': actor},
      );
      await writer.execute(
        Sql.named(
          'UPDATE public."user" SET image_id = @image WHERE id = @actor',
        ),
        parameters: {'image': image, 'actor': actor},
      );
    }

    await writer.execute(
      Sql.named('''
INSERT INTO public.beacon
  (id, user_id, title, description, status, published_at, is_discoverable)
VALUES (@beacon, @author, 't', 'd', 0, @t0, false)
'''),
      parameters: {'beacon': b, 'author': authorId, 't0': _t0},
    );

    if (i % 4 == 1) {
      await writer.execute(
        Sql.named(
          'INSERT INTO public.beacon_steward (beacon_id, user_id) '
          'VALUES (@beacon, @viewer)',
        ),
        parameters: {'beacon': b, 'viewer': _viewerId},
      );
    } else if (i % 4 == 2) {
      await writer.execute(
        Sql.named('''
INSERT INTO public.beacon_participant
  (id, beacon_id, user_id, role, status, room_access)
VALUES (@id, @beacon, @viewer, 2, 0, @admitted)
'''),
        parameters: {
          'id': 'Platpart${_two(i)}',
          'beacon': b,
          'viewer': _viewerId,
          'admitted': RoomAccessBits.admitted,
        },
      );
    }

    if (i == _noEventsIndex) {
      continue;
    }

    final events = <(String, int, int, String, Duration)>[
      (
        _publicEventId(i),
        BeaconActivityEventVisibilityBits.public,
        BeaconActivityEventTypeBits.planUpdated,
        _publicActorId(i),
        const Duration(minutes: 1),
      ),
      (
        _roomEventId(i),
        BeaconActivityEventVisibilityBits.room,
        BeaconActivityEventTypeBits.blockerOpened,
        _roomActorId(i),
        const Duration(minutes: 2),
      ),
      (
        _noiseEventId(i),
        BeaconActivityEventVisibilityBits.room,
        BeaconActivityEventTypeBits.participantJoined,
        _roomActorId(i),
        const Duration(minutes: 3),
      ),
    ];
    for (final (id, visibility, type, actor, offset) in events) {
      await writer.execute(
        Sql.named('''
INSERT INTO public.beacon_activity_event
  (id, beacon_id, visibility, type, actor_id, created_at)
VALUES (@id, @beacon, @visibility::smallint, @type::smallint, @actor, @at)
'''),
        parameters: {
          'id': id,
          'beacon': b,
          'visibility': visibility,
          'type': type,
          'actor': actor,
          'at': _t0.add(offset),
        },
      );
    }
  }
}
