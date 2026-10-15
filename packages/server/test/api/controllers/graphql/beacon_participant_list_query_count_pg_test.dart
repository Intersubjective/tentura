@Tags(['pg'])
library;

import 'package:drift_postgres/drift_postgres.dart';
import 'package:graphql_server2/graphql_server2.dart' show GraphQL;
import 'package:injectable/injectable.dart' show Environment;
import 'package:logging/logging.dart';
import 'package:mockito/mockito.dart';
import 'package:postgres/postgres.dart';
import 'package:test/test.dart';
import 'package:tentura_server/api/controllers/graphql/gql_nodel_base.dart';
import 'package:tentura_server/api/controllers/graphql/input/_input_types.dart';
import 'package:tentura_server/api/controllers/graphql/query/query_beacon_room.dart';
import 'package:tentura_server/data/database/tentura_db.dart'
    hide isNotNull, isNull;
import 'package:tentura_server/data/repository/beacon_room_repository.dart';
import 'package:tentura_server/domain/entity/jwt_entity.dart';
import 'package:tentura_server/domain/exception.dart';
import 'package:tentura_server/domain/policy/discussion_product_policy.dart';
import 'package:tentura_server/domain/port/beacon_fact_card_repository_port.dart';
import 'package:tentura_server/domain/port/coordination_item_repository_port.dart';
import 'package:tentura_server/domain/port/image_repository_port.dart';
import 'package:tentura_server/domain/port/polling_repository_port.dart';
import 'package:tentura_server/domain/port/remote_storage_port.dart';
import 'package:tentura_server/domain/port/task_repository_port.dart';
import 'package:tentura_server/domain/port/upload_quota_repository_port.dart';
import 'package:tentura_server/domain/use_case/beacon_room_case.dart';
import 'package:tentura_server/env.dart';

import '../../../support/disposable_pg_target.dart';
import '../../../support/fake_beacon_hierarchy_repository.dart';
import '../../../support/fake_user_block_repository.dart';
import '../../../support/query_counter.dart';

const _author = 'Upartlistauthor';
const _outsider = 'Upartlistoutside';
const _requested = 'Upartlistrequested';
const _left = 'Upartlistleft';
const _deniedBeacon = 'Bpartlistdenied';
const _query = r'''
query BeaconParticipantList($beaconId: String!) {
  BeaconParticipantList(beaconId: $beaconId) {
    id beaconId userId userTitle userHandle userHasPicture
    userPicHeight userPicWidth userBlurHash userImageId
    role status roomAccess offerNote nextMoveText nextMoveStatus
    nextMoveSource linkedMessageId lastSeenRoomAt helpType roleLabel
    createdAt updatedAt
  }
}
''';
final _at = DateTime.utc(2026, 10, 1, 12);

/// Counts actual Drift statements through the production GraphQL resolver,
/// use case and room repository. Fixture writes use a separate connection and
/// are excluded from the measurement.
Future<void> main() async {
  final target = DisposablePgTarget.fromNamedEnvironment(
    envVarName: 'TENTURA_PARTICIPANT_LIST_QUERY_COUNT_TEST_DB',
    defaultNamePrefix: 'tentura_test_participant_list_queries',
  );
  final skip = await pgSkipReason(target);
  if (skip != null) {
    test('Postgres unavailable', () {}, skip: skip);
    return;
  }

  group('BeaconParticipantList query scaling and projection', () {
    late DisposablePgWriterSession session;
    late TenturaDb db;
    late _RecordingQueryCounter counter;
    late GraphQL graphQL;

    setUpAll(() async {
      session = await setUpDisposablePgWriter(target: target);
      counter = _RecordingQueryCounter();
      db = TenturaDb.forTest(
        database: PgDatabase.opened(
          Pool<dynamic>.withEndpoints(
            [target.databaseEnv.pgEndpoint],
            settings: target.databaseEnv.pgPoolSettings,
          ),
          enableMigrations: false,
        ).interceptWith(counter),
      );
      final roomCase = BeaconRoomCase(
        BeaconRoomRepository(db),
        _UnusedItems(),
        _UnusedFacts(),
        _UnusedImages(),
        _UnusedTasks(),
        _UnusedStorage(),
        _UnusedPolling(),
        _UnusedQuota(),
        FakeUserBlockRepository(),
        PassThroughMutatingUnitOfWork(),
        FakeBeaconHierarchyRepository(),
        const ProductionDiscussionProductPolicy(),
        env: Env(environment: Environment.test),
        logger: Logger('BeaconParticipantListQueryCountTest'),
      );
      graphQL = GraphQL(
        GraphQLSchema(
          queryType: GraphQLObjectType('Query', null)
            ..fields.add(
              QueryBeaconRoom(beaconRoomCase: roomCase).beaconParticipantList,
            ),
        ),
      );
      for (final id in [
        _author,
        _outsider,
        _requested,
        _left,
        for (var i = 0; i < 25; i++) _user(i),
      ]) {
        await session.writer.execute(
          Sql.named('''
INSERT INTO public."user" (id, display_name, handle, public_key)
VALUES (@id, @title, @handle, @key)
'''),
          parameters: {
            'id': id,
            'title': 'Name $id',
            'handle': 'peer_${id.toLowerCase()}',
            'key': id.padRight(44, 'x'),
          },
        );
      }
      for (var i = 0; i < 25; i += 2) {
        await session.writer.execute(
          Sql.named('''
INSERT INTO public.image (id, author_id, height, width, hash)
VALUES (@id::uuid, @user, 48, 64, @hash)
'''),
          parameters: {
            'id': _image(i),
            'user': _user(i),
            'hash': 'blur$i',
          },
        );
        await session.writer.execute(
          Sql.named('''
UPDATE public."user" SET image_id = @image::uuid WHERE id = @user
'''),
          parameters: {'image': _image(i), 'user': _user(i)},
        );
      }
      for (final size in [1, 8, 25]) {
        await _seedParticipants(session.writer, size);
      }
      await _seedDeniedBeacon(session.writer);
    });

    tearDownAll(() async {
      await tearDownDisposablePgWriter(session: session, drift: db);
    });

    Future<Map<String, dynamic>> execute(
      String beaconId,
      String? viewer,
    ) async {
      final result = await graphQL.parseAndExecute(
        _query,
        variableValues: {'beaconId': beaconId},
        globalVariables: {
          if (viewer != null) kGlobalInputQueryJwt: JwtEntity(sub: viewer),
        },
      );
      return result as Map<String, dynamic>;
    }

    for (final viewer in [_author, _user(0)]) {
      test(
        'query count stays constant for 1, 8 and 25 participants viewed by '
        '${viewer == _author ? 'the author' : 'an admitted member'}',
        () async {
          final counts = <int>[];
          for (final size in [1, 8, 25]) {
            counter.reset();
            final result = await execute(_beacon(size), viewer);
            counts.add(counter.count);
            final rows = result['BeaconParticipantList'] as List<dynamic>;
            expect(
              rows.cast<Map<String, dynamic>>(),
              unorderedEquals([
                for (var i = 0; i < size; i++) _expectedParticipant(size, i),
              ]),
              reason: 'Rows for $size participants must be unchanged',
            );
          }
          expect(counts.first, greaterThan(0));
          expect(
            counts,
            everyElement(counts.first),
            reason:
                'Participant enrichment must use set-based reads; '
                'statement counts for N=1,8,25 were $counts',
          );
        },
      );
    }

    // Besides the constant statement count above, the profile fields of the
    // listed participants (title, handle, picture) must come from a single
    // read of the user table, not one identical set-based read per field.
    // Only reads that carry two or more participant ids are considered, so
    // the viewer's own access-check lookups are not affected.
    for (final viewer in [_author, _user(0)]) {
      test(
        'participant profiles are read from the user table at most once for '
        '25 participants viewed by '
        '${viewer == _author ? 'the author' : 'an admitted member'}',
        () async {
          counter.reset();
          await execute(_beacon(25), viewer);
          final participantIds = {for (var i = 0; i < 25; i++) _user(i)};
          final userTableReads = counter.reads.where(
            (read) =>
                read.statement.contains('FROM "user"') &&
                read.args
                        .whereType<String>()
                        .where(participantIds.contains)
                        .length >=
                    2,
          );
          expect(
            userTableReads,
            hasLength(lessThanOrEqualTo(1)),
            reason:
                'Participant title, handle and picture must be fetched '
                'together; user-table reads over the participant set: '
                '${userTableReads.map((r) => r.statement.substring(0, 60)).toList()}',
          );
        },
      );
    }

    for (final (label, beaconId, viewer) in [
      ('a user with no participant row', _beacon(25), _outsider),
      ('an unauthenticated caller', _beacon(25), null),
      (
        'a participant whose room access was only requested',
        _deniedBeacon,
        _requested,
      ),
      ('a participant who left the room', _deniedBeacon, _left),
    ]) {
      test('listing participants is refused for $label', () async {
        // The resolver surfaces the refusal as an exception; it must never
        // resolve to a response that carries participant rows.
        await expectLater(
          execute(beaconId, viewer),
          throwsA(isA<UnauthorizedException>()),
          reason: 'Participant data must not be returned to $label',
        );
      });
    }
  });
}

/// [QueryCounter] that also remembers every SELECT with its parameters.
class _RecordingQueryCounter extends QueryCounter {
  final List<({String statement, List<Object?> args})> reads = [];

  @override
  void reset() {
    super.reset();
    reads.clear();
  }

  @override
  Future<List<Map<String, Object?>>> runSelect(
    QueryExecutor executor,
    String statement,
    List<Object?> args,
  ) {
    reads.add((statement: statement, args: args));
    return super.runSelect(executor, statement, args);
  }
}

String _user(int i) => 'Upartlist${i.toString().padLeft(3, '0')}';
String _beacon(int size) => 'Bpartlist$size';
String _participant(int size, int i) => 'Ppartlist${size}_$i';
String _image(int i) => '00000000-0000-4000-8000-${'$i'.padLeft(12, '0')}';

Future<void> _seedParticipants(Connection writer, int size) async {
  await writer.execute(
    Sql.named('''
INSERT INTO public.beacon (id, user_id, title, description, status, published_at)
VALUES (@id, @author, 'Request', '', 0, @at)
'''),
    parameters: {'id': _beacon(size), 'author': _author, 'at': _at},
  );
  for (var i = 0; i < size; i++) {
    await writer.execute(
      Sql.named('''
INSERT INTO public.beacon_participant
  (id, beacon_id, user_id, role, status, room_access, offer_note,
   next_move_text, next_move_status, next_move_source, created_at, updated_at)
VALUES (@id, @beacon, @user, 2, 3, 3, @note, @next, 0, 1, @at, @at)
'''),
      parameters: {
        'id': _participant(size, i),
        'beacon': _beacon(size),
        'user': _user(i),
        'note': 'Offer $i',
        'next': 'Next $i',
        'at': _at,
      },
    );
    if (i.isEven) {
      await writer.execute(
        Sql.named('''
INSERT INTO public.beacon_room_seen (beacon_id, user_id, last_seen_at)
VALUES (@beacon, @user, @at)
'''),
        parameters: {'beacon': _beacon(size), 'user': _user(i), 'at': _at},
      );
    }
    await writer.execute(
      Sql.named('''
INSERT INTO public.beacon_help_offer
  (beacon_id, user_id, help_type, role_label, status)
VALUES (@beacon, @user, 'hands', @label, @status)
'''),
      parameters: {
        'beacon': _beacon(size),
        'user': _user(i),
        'label': 'Role $i',
        'status': i.isEven ? 0 : 1,
      },
    );
  }
}

/// A Request whose only participants never gained (or lost) room access.
Future<void> _seedDeniedBeacon(Connection writer) async {
  await writer.execute(
    Sql.named('''
INSERT INTO public.beacon (id, user_id, title, description, status, published_at)
VALUES (@id, @author, 'Request', '', 0, @at)
'''),
    parameters: {'id': _deniedBeacon, 'author': _author, 'at': _at},
  );
  for (final (user, access) in [(_requested, 1), (_left, 5)]) {
    await writer.execute(
      Sql.named('''
INSERT INTO public.beacon_participant
  (id, beacon_id, user_id, role, status, room_access, created_at, updated_at)
VALUES (@id, @beacon, @user, 2, 1, @access, @at, @at)
'''),
      parameters: {
        'id': 'P$user',
        'beacon': _deniedBeacon,
        'user': user,
        'access': access,
        'at': _at,
      },
    );
  }
}

Map<String, Object?> _expectedParticipant(int size, int i) => {
  'id': _participant(size, i),
  'beaconId': _beacon(size),
  'userId': _user(i),
  'userTitle': 'Name ${_user(i)}',
  'userHandle': 'peer_${_user(i).toLowerCase()}',
  'userHasPicture': i.isEven,
  'userPicHeight': i.isEven ? 48 : 0,
  'userPicWidth': i.isEven ? 64 : 0,
  'userBlurHash': i.isEven ? 'blur$i' : '',
  'userImageId': i.isEven ? _image(i) : '',
  'role': 2,
  'status': 3,
  'roomAccess': 3,
  'offerNote': 'Offer $i',
  'nextMoveText': 'Next $i',
  'nextMoveStatus': 0,
  'nextMoveSource': 1,
  'linkedMessageId': null,
  'lastSeenRoomAt': i.isEven ? _at.toIso8601String() : null,
  'helpType': i.isEven ? 'hands' : null,
  'roleLabel': i.isEven ? 'Role $i' : null,
  'createdAt': _at.toIso8601String(),
  'updatedAt': _at.toIso8601String(),
};

class _UnusedItems extends Fake implements CoordinationItemRepositoryPort {}

class _UnusedFacts extends Fake implements BeaconFactCardRepositoryPort {}

class _UnusedImages extends Fake implements ImageRepositoryPort {}

class _UnusedTasks extends Fake implements TaskRepositoryPort {}

class _UnusedStorage extends Fake implements RemoteStoragePort {}

class _UnusedPolling extends Fake implements PollingRepositoryPort {}

class _UnusedQuota extends Fake implements UploadQuotaRepositoryPort {}
