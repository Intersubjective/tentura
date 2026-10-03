@Tags(['pg', 'mr'])
library;

import 'package:graphql_server2/graphql_server2.dart' show GraphQL;
import 'package:injectable/injectable.dart' show Environment;
import 'package:postgres/postgres.dart';
import 'package:test/test.dart';

import 'package:tentura_server/api/controllers/graphql/input/_input_types.dart';
import 'package:tentura_server/api/controllers/graphql/schema.dart';
import 'package:tentura_server/app/di.dart';
import 'package:tentura_server/domain/entity/jwt_entity.dart';
import 'package:tentura_server/domain/exception.dart';
import 'package:tentura_server/env.dart';

import '../../../support/disposable_pg_target.dart';

const _requestId = 'Bmemberwebs01';
const _authorId = 'Umwauthor0001';
const _helperId = 'Umwhelper0001';
const _hiddenHelperId = 'Umwhelper0002';
const _recipientId = 'Umwrecipient1';
const _otherRecipientId = 'Umwrecipient2';
const _readerId = 'Umwreader0001';
const _outsiderId = 'Umwoutsider01';

const _memberWebs = r'''
query BeaconMemberWebs($id: String!) {
  beaconMemberWebs(id: $id) {
    beaconId
    personId
    state
  }
}
''';

/// `beaconMemberWebs(id)` over the real V2 GraphQL schema (real DI, disposable
/// Postgres): the member web of a Request for a viewer who can read its
/// content. Admitted helpers are visible to every content reader; recipients of
/// an active forward edge only to viewers who can read involvement. People
/// outside the viewer's visible peer set are never listed.
Future<void> main() async {
  final target = DisposablePgTarget.fromNamedEnvironment(
    envVarName: 'TENTURA_BEACON_MEMBER_WEBS_PG_TEST_DB',
    defaultNamePrefix: 'tentura_test_beacon_member_webs',
  );
  final skip = await pgSkipReason(target);
  if (skip != null) {
    test('Postgres unavailable', () {}, skip: skip);
    return;
  }

  group('beaconMemberWebs query', () {
    late DisposablePgWriterSession session;
    late Connection writer;
    late GraphQL schema;

    setUpAll(() async {
      session = await setUpDisposablePgWriter(
        target: target,
        createPgmer2Extension: true,
      );
      writer = session.writer;
      // Real (dev) repositories against the disposable database; the test
      // environment registers mocks for most ports.
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

    Future<void> reciprocalTrust(String a, String b) => writer.execute(
      Sql.named('''
INSERT INTO public.vote_user (subject, object, amount, created_at, updated_at)
VALUES (@a, @b, 1, now(), now()), (@b, @a, 1, now(), now())
ON CONFLICT (subject, object) DO UPDATE SET amount = EXCLUDED.amount
'''),
      parameters: {'a': a, 'b': b},
    );

    Future<void> admitHelper(String userId) => writer.execute(
      Sql.named('''
INSERT INTO public.beacon_participant
  (beacon_id, user_id, role, status, room_access)
VALUES (@b, @u, 2, 0, 3)
'''),
      parameters: {'b': _requestId, 'u': userId},
    );

    Future<void> forwardTo(String recipientId) => writer.execute(
      Sql.named('''
INSERT INTO public.beacon_forward_edge (id, beacon_id, sender_id, recipient_id)
VALUES (@id, @b, @sender, @r)
'''),
      parameters: {
        'id': 'Fmw$recipientId',
        'b': _requestId,
        'sender': _authorId,
        'r': recipientId,
      },
    );

    setUp(() async {
      await writer.execute('''
TRUNCATE TABLE
  public.beacon_forward_edge,
  public.beacon_participant,
  public.vote_user,
  public.beacon,
  public."user"
CASCADE
''');
      for (final id in [
        _authorId,
        _helperId,
        _hiddenHelperId,
        _recipientId,
        _otherRecipientId,
        _readerId,
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
      // A discoverable, published Request: any peer mutually visible with the
      // author can read its content without being involved in it.
      await writer.execute(
        Sql.named('''
INSERT INTO public.beacon
  (id, user_id, title, description, status, kind, is_discoverable,
   published_at)
VALUES (@b, @author, 'Request', 'Needs help', 0, 0, true, now())
'''),
        parameters: {'b': _requestId, 'author': _authorId},
      );
      // The viewers trust the author, the helper and the second recipient, so
      // those are in their visible peer sets; the hidden helper is not.
      for (final viewer in [_readerId, _recipientId, _authorId]) {
        for (final peer in [
          _authorId,
          _helperId,
          _recipientId,
          _otherRecipientId,
        ]) {
          if (viewer != peer) await reciprocalTrust(viewer, peer);
        }
      }
      await admitHelper(_helperId);
      await admitHelper(_hiddenHelperId);
      await forwardTo(_recipientId);
      await forwardTo(_otherRecipientId);
    });

    Future<List<Map<String, dynamic>>> webs(
      String viewerId, {
      String id = _requestId,
    }) async {
      final data =
          await schema.parseAndExecute(
                _memberWebs,
                variableValues: {'id': id},
                globalVariables: {
                  kGlobalInputQueryJwt: JwtEntity(sub: viewerId),
                },
              )
              as Map<String, dynamic>;
      return (data['beaconMemberWebs'] as List).cast<Map<String, dynamic>>();
    }

    /// person id → state for everyone except the viewer and the author.
    Future<Map<String, String>> statesSeenBy(String viewerId) async => {
      for (final web in await webs(viewerId))
        if (web['personId'] != viewerId && web['personId'] != _authorId)
          web['personId']! as String: web['state']! as String,
    };

    test('content reader without involvement sees admitted helpers only',
        () async {
      expect(await statesSeenBy(_readerId), {_helperId: 'INSIDE'});
    });

    test('every row names the requested Request', () async {
      final rows = await webs(_readerId);

      expect(rows, isNotEmpty);
      expect(rows.map((row) => row['beaconId']).toSet(), {_requestId});
    });

    test('viewer on an active forward edge also sees forward recipients',
        () async {
      expect(await statesSeenBy(_recipientId), {
        _helperId: 'INSIDE',
        _otherRecipientId: 'FORWARDED',
      });
    });

    test('author sees admitted helpers and forward recipients', () async {
      expect(await statesSeenBy(_authorId), {
        _helperId: 'INSIDE',
        _recipientId: 'FORWARDED',
        _otherRecipientId: 'FORWARDED',
      });
    });

    test('people outside the viewer peer set are not listed', () async {
      final seenByAuthor = await statesSeenBy(_authorId);

      expect(seenByAuthor, isNot(contains(_hiddenHelperId)));
      expect(await statesSeenBy(_readerId), isNot(contains(_hiddenHelperId)));
    });

    test('forward recipient who is also an admitted helper is listed once as '
        'inside', () async {
      await admitHelper(_otherRecipientId);

      final rows = (await webs(_recipientId))
          .where((row) => row['personId'] == _otherRecipientId)
          .toList();

      expect(rows, hasLength(1));
      expect(rows.single['state'], 'INSIDE');
    });

    test('cancelled forward edge no longer lists the recipient', () async {
      await writer.execute(
        Sql.named(
          'UPDATE public.beacon_forward_edge SET cancelled_at = now() '
          'WHERE id = @id',
        ),
        parameters: {'id': 'Fmw$_otherRecipientId'},
      );

      expect(await statesSeenBy(_authorId), {
        _helperId: 'INSIDE',
        _recipientId: 'FORWARDED',
      });
    });

    test('viewer who cannot read the Request content is rejected', () async {
      await expectLater(
        webs(_outsiderId),
        throwsA(isA<UnauthorizedException>()),
      );
    });
  });
}
