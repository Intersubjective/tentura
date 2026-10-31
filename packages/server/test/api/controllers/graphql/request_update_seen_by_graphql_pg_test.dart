@Tags(['pg'])
library;

import 'package:graphql_server2/graphql_server2.dart' show GraphQL;
import 'package:injectable/injectable.dart' show Environment;
import 'package:postgres/postgres.dart';
import 'package:test/test.dart';

import 'package:tentura_server/api/controllers/graphql/input/_input_types.dart';
import 'package:tentura_server/api/controllers/graphql/schema.dart';
import 'package:tentura_server/app/di.dart';
import 'package:tentura_server/domain/entity/jwt_entity.dart';
import 'package:tentura_server/env.dart';

import '../../../support/disposable_pg_target.dart';

const _beaconId = 'Bupdseenby001';
const _authorId = 'Uupdseenauth1';
const _stewardId = 'Uupdseenstew1';
const _helperId = 'Uupdseenhelp1';
const _otherHelperId = 'Uupdseenhelp2';
const _outsiderId = 'Uupdseenout01';

/// The member opens the Request view: records that they have seen the
/// Request's latest next-step / status update.
const _markUpdateSeen = r'''
mutation MarkBeaconUpdateSeen($beaconId: String!) {
  MarkBeaconUpdateSeen(beaconId: $beaconId) {
    beaconId
    seenAt
  }
}
''';

/// Who has seen the Request's latest next-step / status update.
const _seenBy = r'''
query BeaconUpdateSeenBy($id: String!) {
  beaconUpdateSeenBy(id: $id) {
    userId
    seenAt
  }
}
''';

/// The production "set the next step" call.
const _setNextStep = r'''
mutation BeaconRoomNowLineUpdate(
  $beaconId: String!,
  $text: String!,
  $baseRevision: Int!
) {
  BeaconRoomNowLineUpdate(
    beaconId: $beaconId,
    text: $text,
    baseRevision: $baseRevision
  ) {
    updatedAt
    updatedBy
    currentLineRevision
  }
}
''';

const _userDelete = '''
mutation UserDelete {
  userDelete
}
''';

/// "Seen by" for a Request's latest next step / status update (#766), end to
/// end over the real V2 GraphQL schema (real DI, disposable Postgres):
///
/// - a Request member who opens the Request after the update is listed;
/// - a newer update starts the list over;
/// - only the update's author and the Request's author / steward can read
///   the list (the #178 read-receipt rule: own items only);
/// - erasing an account removes that reader from the list.
Future<void> main() async {
  final target = DisposablePgTarget.fromNamedEnvironment(
    envVarName: 'TENTURA_REQUEST_UPDATE_SEEN_BY_GQL_TEST_DB',
    defaultNamePrefix: 'tentura_test_update_seen_by_gql',
  );
  final reachable = await canReachPostgresAdmin(target);
  final skipReason = reachable
      ? false
      : 'Postgres admin database not reachable for disposable test target';

  group('Seen by on the latest next-step update of a Request', () {
    late DisposablePgWriterSession session;
    late Connection writer;
    late GraphQL schema;

    setUpAll(() async {
      session = await setUpDisposablePgWriter(target: target);
      writer = session.writer;
      // Real (dev) repositories against the disposable database.
      final db = target.databaseEnv;
      await configureDependencies(
        Env(
          environment: Environment.dev,
          serverUri: Uri.parse('http://127.0.0.1:2080'),
          publicKey: Env.kJwtPublicKey,
          privateKey: Env.kJwtPrivateKey,
          pgHost: db.pgHost,
          pgPort: db.pgPort,
          pgDatabase: db.pgDatabase,
          pgUsername: db.pgUsername,
          pgPassword: db.pgPassword,
          publicOrigin: 'http://127.0.0.1:2080',
          workersCount: 1,
          printEnv: false,
          isDebugModeOn: false,
        ),
      );
      await getIt.allReady(ignorePendingAsyncCreation: true);
      schema = graphqlSchema;
    });

    tearDownAll(() async {
      await getIt.reset();
      await tearDownDisposablePgWriter(session: session);
    });

    setUp(() async {
      await writer.execute('''
TRUNCATE TABLE
  public.beacon_room_state,
  public.beacon_steward,
  public.beacon_participant,
  public.beacon,
  public."user"
CASCADE
''');
      for (final id in [
        _authorId,
        _stewardId,
        _helperId,
        _otherHelperId,
        _outsiderId,
      ]) {
        await writer.execute(
          Sql.named(
            'INSERT INTO public."user" (id, display_name, public_key) '
            'VALUES (@id, @id, @key)',
          ),
          parameters: {'id': id, 'key': '$id-key'},
        );
      }
      await writer.execute(
        Sql.named('''
INSERT INTO public.beacon (id, user_id, title, description, status)
VALUES (@b, @author, 'Request', 'Needs help', 0)
'''),
        parameters: {'b': _beaconId, 'author': _authorId},
      );
      await writer.execute(
        Sql.named(
          'INSERT INTO public.beacon_steward (beacon_id, user_id) '
          'VALUES (@b, @s)',
        ),
        parameters: {'b': _beaconId, 's': _stewardId},
      );
      // Steward row carries the steward role (1); helpers are admitted
      // (room_access = 3, admitted) members of the Request.
      await writer.execute(
        Sql.named('''
INSERT INTO public.beacon_participant (
  id, beacon_id, user_id, role, status, room_access, created_at, updated_at
) VALUES
  ('Pupdseenstew1', @b, @s, 1, 0, 3,
   '2026-01-01T00:00:00Z', '2026-01-01T00:00:00Z'),
  ('Pupdseenhelp1', @b, @h1, 0, 0, 3,
   '2026-01-01T00:00:00Z', '2026-01-01T00:00:00Z'),
  ('Pupdseenhelp2', @b, @h2, 0, 0, 3,
   '2026-01-01T00:00:00Z', '2026-01-01T00:00:00Z')
'''),
        parameters: {
          'b': _beaconId,
          's': _stewardId,
          'h1': _helperId,
          'h2': _otherHelperId,
        },
      );
    });

    Future<Map<String, dynamic>> run(
      String userId,
      String document, [
      Map<String, dynamic> variables = const {},
    ]) async =>
        await schema.parseAndExecute(
              document,
              variableValues: variables,
              globalVariables: {kGlobalInputQueryJwt: JwtEntity(sub: userId)},
            )
            as Map<String, dynamic>;

    var revision = 0;

    /// [userId] sets the Request's next step through the production mutation.
    Future<void> setNextStep(String userId, String text) async {
      final data = await run(userId, _setNextStep, {
        'beaconId': _beaconId,
        'text': text,
        'baseRevision': revision,
      });
      final row = data['BeaconRoomNowLineUpdate'] as Map<String, dynamic>;
      expect(row['updatedBy'], userId);
      revision = row['currentLineRevision'] as int;
    }

    setUp(() => revision = 0);

    /// [userId] opens the Request view.
    Future<void> openRequest(String userId) async {
      final data = await run(userId, _markUpdateSeen, {'beaconId': _beaconId});
      final result = data['MarkBeaconUpdateSeen'];
      expect(
        result,
        isA<Map<String, dynamic>>(),
        reason: 'opening the Request must record that the member saw it',
      );
      expect((result! as Map<String, dynamic>)['beaconId'], _beaconId);
    }

    /// The ids listed as having seen the latest update, as [viewerId] reads
    /// them.
    Future<List<String>> seenBy(String viewerId) async {
      final data = await run(viewerId, _seenBy, {'id': _beaconId});
      final rows = data['beaconUpdateSeenBy'] as List?;
      return [
        for (final row in (rows ?? const []).cast<Map<String, dynamic>>())
          row['userId'] as String,
      ];
    }

    /// Like [seenBy], but a refusal (an error) reads as "nothing visible".
    Future<List<String>> seenByOrNothing(String viewerId) async {
      try {
        return await seenBy(viewerId);
      } on Object {
        return const [];
      }
    }

    test('a member who opens the Request after the update is listed with '
        'the time they saw it', () async {
      await setNextStep(_authorId, 'Bring the ladder on Saturday');
      final before = DateTime.timestamp();

      await openRequest(_helperId);

      final data = await run(_authorId, _seenBy, {'id': _beaconId});
      final rows = (data['beaconUpdateSeenBy'] as List)
          .cast<Map<String, dynamic>>();
      final helperRow = rows.singleWhere((r) => r['userId'] == _helperId);
      final seenAt = DateTime.parse(helperRow['seenAt'] as String).toUtc();
      expect(
        seenAt.isBefore(before.subtract(const Duration(seconds: 1))),
        isFalse,
      );
      expect(rows.map((r) => r['userId']), isNot(contains(_otherHelperId)));
    });

    test('a member who opened the Request only before the update is not '
        'listed', () async {
      await setNextStep(_authorId, 'Find a ladder');
      await openRequest(_helperId);
      await openRequest(_otherHelperId);
      expect(await seenBy(_authorId), containsAll([_helperId, _otherHelperId]));

      await setNextStep(_authorId, 'Bring the ladder on Saturday');

      expect(await seenBy(_authorId), isEmpty);
    });

    test('a newer update starts the list over; opening again lists the '
        'member for the new update', () async {
      await setNextStep(_authorId, 'Find a ladder');
      await openRequest(_helperId);
      expect(await seenBy(_authorId), [_helperId]);

      await setNextStep(_stewardId, 'Bring the ladder on Saturday');
      expect(await seenBy(_authorId), isNot(contains(_helperId)));

      await openRequest(_helperId);
      expect(await seenBy(_authorId), contains(_helperId));
    });

    test('someone outside the Request who opens it is not listed', () async {
      await setNextStep(_authorId, 'Bring the ladder on Saturday');
      await openRequest(_helperId);

      try {
        await openRequest(_outsiderId);
      } on Object {
        // Refusing a non-member is fine; recording them is not.
      }

      final readers = await seenBy(_authorId);
      expect(readers, contains(_helperId));
      expect(readers, isNot(contains(_outsiderId)));
    });

    test('the Request author, the steward and the update author can read '
        'the list', () async {
      // A helper sets the next step, so the update's author is neither the
      // Request author nor a steward.
      await setNextStep(_helperId, 'I will bring the ladder on Saturday');
      await openRequest(_otherHelperId);

      expect(await seenBy(_helperId), contains(_otherHelperId));
      expect(await seenBy(_authorId), contains(_otherHelperId));
      expect(await seenBy(_stewardId), contains(_otherHelperId));
    });

    test('another member who wrote neither the Request nor the update cannot '
        'read the list', () async {
      await setNextStep(_authorId, 'Bring the ladder on Saturday');
      await openRequest(_helperId);
      await openRequest(_otherHelperId);
      // The list exists and is readable by its owner…
      expect(await seenBy(_authorId), containsAll([_helperId, _otherHelperId]));

      // …but a plain member, and someone outside the Request, see no one.
      expect(await seenByOrNothing(_otherHelperId), isEmpty);
      expect(await seenByOrNothing(_outsiderId), isEmpty);
    });

    test('erasing an account removes that reader from the list', () async {
      await setNextStep(_authorId, 'Bring the ladder on Saturday');
      await openRequest(_helperId);
      await openRequest(_otherHelperId);
      expect(await seenBy(_authorId), containsAll([_helperId, _otherHelperId]));

      final deleted = await run(_helperId, _userDelete);
      expect(deleted['userDelete'], isTrue);

      final readers = await seenBy(_authorId);
      expect(readers, isNot(contains(_helperId)));
      expect(readers, contains(_otherHelperId));
    });
  }, skip: skipReason);
}
