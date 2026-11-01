// Produces a real Field response for the client regression. Keeping the query
// live means adding sender data to the API needs no invented client fixture.
import 'dart:convert';
import 'dart:io';

import 'package:postgres/postgres.dart';

import 'package:injectable/injectable.dart' show Environment;
import 'package:logging/logging.dart';
import 'package:mockito/mockito.dart';
import 'package:tentura_server/api/controllers/graphql/custom_types.dart';
import 'package:tentura_server/api/controllers/graphql/input/_input_types.dart';
import 'package:tentura_server/api/controllers/graphql/query/query_constellation_field.dart';
import 'package:tentura_server/api/controllers/graphql/schema.dart';
import 'package:tentura_server/data/database/tentura_db.dart';
import 'package:tentura_server/data/repository/constellation_field_repository.dart';
import 'package:tentura_server/domain/entity/constellation_field.dart';
import 'package:tentura_server/domain/entity/jwt_entity.dart';
import 'package:tentura_server/domain/port/user_profile_batch_lookup_port.dart';
import 'package:tentura_server/domain/use_case/constellation_field_case.dart';
import 'package:tentura_server/env.dart';

import 'disposable_pg_target.dart';

const _viewer = 'Uviewer000001';
const _bob = 'Uforwardbob01';
const _alice = 'Uauthoralice1';
const _request = 'Bforwarded001';

Future<void> main() async {
  final fixture = await readForwardedRequestFieldResponse();
  if (fixture == null) {
    exitCode = 77;
    return;
  }
  stdout.writeln('FIELD_RESPONSE:${jsonEncode(fixture.response)}');
}

typedef ForwardedRequestFieldScenario = ({
  Map<String, dynamic> response,
  List<(String, String)> trustEdges,
  List<String> ordinaryVisiblePeerIds,
  List<(String, String)> forwards,
  ({String id, String displayName}) forwarder,
});

Future<ForwardedRequestFieldScenario?>
readForwardedRequestFieldResponse() async {
  final target = DisposablePgTarget.fromNamedEnvironment(
    envVarName: 'TENTURA_FORWARDED_REQUEST_FIELD_TEST_DB',
    defaultNamePrefix: 'tentura_test_forwarded_field',
  );
  final unavailable = await pgSkipReason(target);
  if (unavailable != null) {
    stderr.writeln(unavailable);
    return null;
  }
  final session = await setUpDisposablePgWriter(
    target: target,
    createPgmer2Extension: true,
  );
  final db = openDisposablePgDatabase(target);
  try {
    for (final person in {
      _viewer: 'Zed',
      _bob: 'Bob',
      _alice: 'Alice',
    }.entries) {
      await db.customStatement('''
INSERT INTO public."user" (id, display_name, public_key)
VALUES ('${person.key}', '${person.value}', 'pk-${person.key}')
''');
    }
    // Zed's only contact is Bob. Alice is two trust hops away, without
    // MeritRank edges granting visibility, and sends her Request to Bob.
    await db.customStatement('''
INSERT INTO public.vote_user (subject, object, amount) VALUES
('$_viewer', '$_bob', 1), ('$_bob', '$_viewer', 1),
('$_bob', '$_alice', 1), ('$_alice', '$_bob', 1)
''');
    await db.customStatement('''
INSERT INTO public.beacon
  (id, user_id, title, description, status, kind, is_discoverable,
   published_at, created_at, status_changed_at)
VALUES ('$_request', '$_alice', 'Move the piano', 'Help moving a piano',
  0, 0, true, now(), now(), now())
''');
    await db.customStatement('''
INSERT INTO public.beacon_forward_edge (beacon_id, sender_id, recipient_id)
VALUES ('$_request', '$_alice', '$_bob'),
       ('$_request', '$_bob', '$_viewer')
''');

    final query = QueryConstellationField(
      constellationFieldCase: ConstellationFieldCase(
        ConstellationFieldRepository(db, _Profiles(db)),
        env: Env(environment: Environment.test),
        logger: Logger('ForwardedRequestFieldResponse'),
      ),
    );
    final graphQL = TenturaGraphQL(
      GraphQLSchema(
        queryType: GraphQLObjectType('query_root', null)
          ..fields.addAll(query.all),
      ),
      customTypes: customTypes,
    );
    final document = [
      File(
        '../client/lib/features/constellation/data/gql/'
        'constellation_field_fetch.graphql',
      ).readAsStringSync(),
      File('../client/lib/data/gql/image_model_v2.graphql').readAsStringSync(),
    ].join('\n');
    // Ferry adds __typename to selection sets. These documents have no
    // object-valued argument literals, so each brace starts a selection set.
    final response = await graphQL.parseAndExecute(
      document.replaceAll('{', '{ __typename '),
      globalVariables: {kGlobalInputQueryJwt: const JwtEntity(sub: _viewer)},
    );
    // Verify edges using the same explicit-trust predicate the Field reader
    // uses; effective MeritRank score edges are a different population.
    final trustEdges = await session.writer.execute('''
SELECT subject, object FROM public.vote_user
WHERE amount > 0
  AND public.person_reciprocal_explicit_trust(subject, object)
ORDER BY subject, object
''');
    final visiblePeers = await session.writer.execute(
      Sql.named(
        "SELECT peer_id FROM public.person_visible_peers_symmetric(@viewer, '')",
      ),
      parameters: {'viewer': _viewer},
    );
    final forwards = await session.writer.execute('''
SELECT sender_id, recipient_id FROM public.beacon_forward_edge
WHERE beacon_id = '$_request' AND cancelled_at IS NULL
ORDER BY sender_id, recipient_id
''');
    final receivedForward = await session.writer.execute(
      Sql.named('''
SELECT e.sender_id, sender.display_name
FROM public.beacon_forward_edge e
JOIN public."user" sender ON sender.id = e.sender_id
WHERE e.beacon_id = @beacon AND e.recipient_id = @viewer
  AND e.cancelled_at IS NULL
'''),
      parameters: {'beacon': _request, 'viewer': _viewer},
    );
    final sender = receivedForward.single;
    return (
      response: (response as Map).cast<String, dynamic>(),
      trustEdges: [
        for (final row in trustEdges) (row[0]! as String, row[1]! as String),
      ],
      ordinaryVisiblePeerIds: [
        for (final row in visiblePeers) row[0]! as String,
      ],
      forwards: [
        for (final row in forwards) (row[0]! as String, row[1]! as String),
      ],
      forwarder: (id: sender[0]! as String, displayName: sender[1]! as String),
    );
  } finally {
    await tearDownDisposablePgWriter(session: session, drift: db);
  }
}

// Profile identity comes from the same real database, without GetIt's
// unrelated presence services.
final class _Profiles extends Fake implements UserProfileBatchLookup {
  _Profiles(this.db);
  final TenturaDb db;

  @override
  Future<Map<String, ConstellationPeerRecord>> constellationProfilesByIds(
    Iterable<String> ids,
  ) async {
    final users = await db.managers.users
        .filter((user) => user.id.isIn(ids.toList()))
        .get();
    return {
      for (final user in users)
        user.id: ConstellationPeerRecord(
          id: user.id,
          displayName: user.displayName,
        ),
    };
  }
}
