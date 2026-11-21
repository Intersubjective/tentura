@Tags(['pg'])
library;

import 'package:graphql_server2/graphql_server2.dart' show GraphQL;
import 'package:mockito/mockito.dart' show Fake;
import 'package:postgres/postgres.dart';
import 'package:test/test.dart';
import 'package:tentura_root/domain/entity/beacon_status.dart';

import 'package:tentura_server/api/controllers/graphql/input/_input_types.dart';
import 'package:tentura_server/api/controllers/graphql/schema.dart';
import 'package:tentura_server/app/di.dart';
import 'package:tentura_server/consts/beacon_activity_event_consts.dart';
import 'package:tentura_server/data/database/tentura_db.dart'
    hide isNotNull, isNull;
import 'package:tentura_server/domain/entity/jwt_entity.dart';
import 'package:tentura_server/domain/port/beacon_access_guard.dart';
import 'package:tentura_server/domain/use_case/beacon_display_case.dart';
import 'package:tentura_server/domain/use_case/beacon_room_case.dart';
import 'package:tentura_server/env.dart';

import '../../../support/disposable_pg_target.dart';
import '../../../support/pg_test_public_keys.dart';

const _author = 'Ua00000000001';
const _member = 'Ua00000000002';
const _reader = 'Ua00000000003';
const _outsider = 'Ua00000000004';
const _request = 'Ba00000000001';
const _secondRequest = 'Ba00000000002';
const _hiddenRequest = 'Ba00000000003';
const _publicEvent = 'Ea00000000001';
const _roomEvent = 'Ea00000000002';

Future<void> main() async {
  final target = DisposablePgTarget.fromNamedEnvironment(
    envVarName: 'TENTURA_REQUEST_VISIBILITY_PG_TEST_DB',
    defaultNamePrefix: 'tentura_test_request_visibility',
    useDevBindings: true,
  );
  final skip = await pgSkipReason(target);

  setUpAll(() async {
    final session = await setUpDisposablePgWriter(target: target);
    addTearDown(() => tearDownDisposablePgWriter(session: session));
    await _seed(session.writer);

    final warnSetting = driftRuntimeOptions.dontWarnAboutMultipleDatabases;
    driftRuntimeOptions.dontWarnAboutMultipleDatabases = true;
    addTearDown(() {
      driftRuntimeOptions.dontWarnAboutMultipleDatabases = warnSetting;
    });

    addTearDown(getIt.reset);
    await configureDependencies(target.databaseEnv);
    await getIt.allReady(ignorePendingAsyncCreation: true);
  });

  test(
    'Request activity uses the disposable database pool size',
    () {
      expect(
        getIt<Env>().pgPoolSettings.maxConnectionCount,
        target.databaseEnv.pgPoolSettings.maxConnectionCount,
      );
    },
    skip: skip,
  );

  test(
    'activity events are visible to content readers and room members '
    'according to their access',
    () async {
      final room = getIt<BeaconRoomCase>();

      Future<Iterable<Object?>> activityIds(String viewer) async =>
          (await room.listActivityEvents(
            beaconId: _request,
            userId: viewer,
          )).map((row) => row['id']);

      expect(await activityIds(_reader), [_publicEvent]);
      expect(
        await activityIds(_author),
        unorderedEquals([_publicEvent, _roomEvent]),
      );
      expect(
        await activityIds(_member),
        unorderedEquals([_publicEvent, _roomEvent]),
      );
      expect(await activityIds(_outsider), isEmpty);
    },
    skip: skip,
  );

  test(
    'the activity query serves authorized results without a resolver access check',
    () async {
      final schema = graphqlSchema;
      // The use case and schema already hold their production dependencies.
      // Count guard calls resolved directly by the GraphQL request.
      final guard = _RecordingAccessGuard(getIt<BeaconAccessGuard>());
      getIt.pushNewScope(
        init: (scope) => scope.registerSingleton<BeaconAccessGuard>(guard),
      );
      addTearDown(getIt.popScope);

      expect(await _graphqlActivityIds(schema, _outsider), isEmpty);
      expect(
        await _graphqlActivityIds(schema, _member),
        unorderedEquals([_publicEvent, _roomEvent]),
      );
      expect(guard.checks, isEmpty);
    },
    skip: skip,
  );

  test(
    'display statuses evaluate content access once per Request and omit '
    'unreadable Requests',
    () async {
      final db = getIt<TenturaDb>();
      final display = getIt<BeaconDisplayCase>();
      final ids = [_request, _hiddenRequest, _secondRequest];

      final (statuses, calls) = await db.withTransaction(() async {
        await db.customStatement("SET LOCAL track_functions = 'all'");
        final before = await _contentAccessCalls(db);
        final result = await display.displayStatuses(
          beaconIds: ids,
          viewerId: _reader,
        );
        final after = await _contentAccessCalls(db);
        return (result, after - before);
      });
      expect(
        statuses.map((status) => (status.beaconId, status.status)),
        [
          (_request, BeaconStatus.open),
          (_secondRequest, BeaconStatus.open),
        ],
      );
      expect(calls, ids.length);
    },
    skip: skip,
  );
}

Future<Iterable<Object?>> _graphqlActivityIds(
  GraphQL schema,
  String viewer,
) async {
  final result =
      await schema.parseAndExecute(
            r'''
query RequestActivity($id: String!) {
  BeaconActivityEventList(beaconId: $id) { id }
}
''',
            variableValues: {'id': _request},
            globalVariables: {kGlobalInputQueryJwt: JwtEntity(sub: viewer)},
          )
          as Map<String, dynamic>;
  final rows = result['BeaconActivityEventList'] as List<dynamic>;
  return rows.map((row) => (row as Map<String, dynamic>)['id']);
}

final class _RecordingAccessGuard extends Fake implements BeaconAccessGuard {
  _RecordingAccessGuard(this._delegate);

  final BeaconAccessGuard _delegate;
  final checks = <(String, String)>[];

  @override
  Future<bool> canReadContent({
    required String beaconId,
    required String viewerId,
  }) {
    checks.add((beaconId, viewerId));
    return _delegate.canReadContent(beaconId: beaconId, viewerId: viewerId);
  }
}

Future<int> _contentAccessCalls(TenturaDb db) async {
  final row = await db.customSelect('''
SELECT COALESCE(SUM(calls), 0)::int AS calls
FROM pg_stat_xact_user_functions
WHERE schemaname = 'public' AND funcname = 'beacon_can_read_content'
''').getSingle();
  return row.read<int>('calls');
}

Future<void> _seed(Connection writer) async {
  for (final (index, id) in [_author, _member, _reader, _outsider].indexed) {
    await writer.execute(
      Sql.named('''
INSERT INTO public."user" (id, display_name, public_key)
VALUES (@id, @id, @key)
'''),
      parameters: {
        'id': id,
        'key': pgTestPublicKey('activityPrivacy', index + 1),
      },
    );
  }

  await writer.execute('''
INSERT INTO public.beacon (id, user_id, title, description, status, published_at)
VALUES ('$_request', '$_author', 'Request with activity', '', 0, now()),
       ('$_secondRequest', '$_author', 'Second readable Request', '', 0, now()),
       ('$_hiddenRequest', '$_author', 'Unreadable Request', '', 0, now())
''');
  await writer.execute('''
INSERT INTO public.beacon_participant (beacon_id, user_id, role, status, room_access)
VALUES ('$_request', '$_member', 2, 0, 3)
''');
  await writer.execute('''
INSERT INTO public.beacon_forward_edge (beacon_id, sender_id, recipient_id)
VALUES ('$_request', '$_author', '$_reader'),
       ('$_secondRequest', '$_author', '$_reader')
''');
  await writer.execute('''
INSERT INTO public.beacon_activity_event (id, beacon_id, visibility, type, actor_id, created_at)
VALUES ('$_publicEvent', '$_request', ${BeaconActivityEventVisibilityBits.public},
        ${BeaconActivityEventTypeBits.beaconPublished}, '$_author', now()),
       ('$_roomEvent', '$_request', ${BeaconActivityEventVisibilityBits.room},
        ${BeaconActivityEventTypeBits.planUpdated}, '$_author', now())
''');
}
