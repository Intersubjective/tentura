@Tags(['pg'])
library;

import 'package:injectable/injectable.dart' show Environment;
import 'package:postgres/postgres.dart';
import 'package:test/test.dart';

import 'package:tentura_server/data/database/tentura_db.dart';
import 'package:tentura_server/data/repository/realtime_watch_authorization_repository.dart';
import 'package:tentura_server/domain/entity/realtime_watch_grant.dart';
import 'package:tentura_server/env.dart';

const _viewerId = 'Uwatchauth001';
const _participantId = 'Uwatchauth002';
const _outsiderId = 'Uwatchauth003';
const _missingId = 'Uwatchauth004';
const _beaconId = 'Bwatchauth001';

Future<void> main() async {
  final env = _testEnv();
  final reachable = await _canConnect(env);
  final skipReason = reachable ? false : 'local Postgres not reachable';

  group('RealtimeWatchAuthorizationRepository', () {
    late TenturaDb db;
    late RealtimeWatchAuthorizationRepository repository;

    setUpAll(() async {
      db = TenturaDb(env);
      repository = RealtimeWatchAuthorizationRepository(db);
      await db.customStatement(
        r'''DELETE FROM public."user" WHERE id IN ($1, $2, $3)''',
        [_viewerId, _participantId, _outsiderId],
      );
      for (final entry in [
        (_viewerId, 'watch-auth-viewer-key'),
        (_participantId, 'watch-auth-participant-key'),
        (_outsiderId, 'watch-auth-outsider-key'),
      ]) {
        await db.customStatement(
          r'''
INSERT INTO public."user" (id, display_name, public_key)
VALUES ($1, $2, $3)
''',
          [entry.$1, entry.$1, entry.$2],
        );
      }
      await db.customStatement(
        r'''
INSERT INTO public.beacon (id, user_id, title, description)
VALUES ($1, $2, 'Watch authorization', 'People projection')
''',
        [_beaconId, _viewerId],
      );
      await db.customStatement(
        r'''
INSERT INTO public.beacon_participant (
  id, beacon_id, user_id, role, status, room_access
) VALUES ('Pwatchauth002', $1, $2, 2, 0, 3)
ON CONFLICT (beacon_id, user_id) DO UPDATE SET room_access = 3
''',
        [_beaconId, _participantId],
      );
    });

    tearDownAll(() async {
      await db.customStatement(
        r'''DELETE FROM public."user" WHERE id IN ($1, $2, $3)''',
        [_viewerId, _participantId, _outsiderId],
      );
      await db.close();
    });

    test(
      'profile mirrors public user visibility but rejects nonexistent IDs',
      () async {
        final authorized = await repository.authorizeSubjects(
          viewerId: _viewerId,
          descriptor: const RealtimeWatchDescriptor(
            scope: RealtimeWatchScope.profile,
            requestedSubjectIds: {_participantId, _missingId},
            profileId: _participantId,
          ),
        );
        expect(authorized, {_participantId});
      },
      skip: skipReason,
    );

    test(
      'people intersects requested IDs with authorized beacon involvement',
      () async {
        final descriptor = const RealtimeWatchDescriptor(
          scope: RealtimeWatchScope.people,
          requestedSubjectIds: {_viewerId, _participantId, _outsiderId},
          beaconId: _beaconId,
        );
        expect(
          await repository.authorizeSubjects(
            viewerId: _viewerId,
            descriptor: descriptor,
          ),
          {_viewerId, _participantId},
        );
        expect(
          await repository.authorizeSubjects(
            viewerId: _outsiderId,
            descriptor: descriptor,
          ),
          isEmpty,
        );
      },
      skip: skipReason,
    );

    test(
      'graph executes the bounded public.graph authorization path',
      () async {
        final requested = {_viewerId, _participantId};
        final authorized = await repository.authorizeSubjects(
          viewerId: _viewerId,
          descriptor: RealtimeWatchDescriptor(
            scope: RealtimeWatchScope.graph,
            requestedSubjectIds: requested,
            focusId: _viewerId,
            context: '',
            positiveOnly: true,
          ),
        );
        expect(authorized.difference(requested), isEmpty);
      },
      skip: skipReason,
    );
  }, skip: skipReason);
}

Future<bool> _canConnect(Env env) async {
  try {
    final connection = await Connection.open(
      env.pgEndpoint,
      settings: env.pgEndpointSettings,
    ).timeout(const Duration(seconds: 2));
    await connection.close();
    return true;
  } on Object {
    return false;
  }
}

Env _testEnv() => Env(
  environment: Environment.test,
  pgHost: '127.0.0.1',
  pgPort: 5432,
  pgPassword: 'password',
  printEnv: false,
  isDebugModeOn: false,
);
