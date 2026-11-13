@Tags(['pg', 'multi-connection'])
@Timeout(Duration(minutes: 3))
library;

// Copying a fact over the V2 GraphQL endpoint: the real request path from
// HTTP through the resolver, use case and repository to Postgres.
import 'dart:convert';

import 'package:injectable/injectable.dart' show Environment;
import 'package:postgres/postgres.dart';
import 'package:shelf_plus/shelf_plus.dart';
import 'package:test/test.dart';

import 'package:tentura_server/api/controllers/graphql_controller.dart';
import 'package:tentura_server/app/di.dart';
import 'package:tentura_server/consts/beacon_activity_event_consts.dart';
import 'package:tentura_server/consts/beacon_fact_card_consts.dart';
import 'package:tentura_server/consts/beacon_room_consts.dart';
import 'package:tentura_server/data/database/main_db_pool.dart';
import 'package:tentura_server/data/database/tentura_db.dart'
    hide isNotNull, isNull;
import 'package:tentura_server/domain/entity/jwt_entity.dart';
import 'package:tentura_server/env.dart';

import '../../../support/disposable_pg_target.dart';
import '../../../support/pg_test_public_keys.dart';
import '../../../support/session_database_di_harness.dart';

const _author = 'Ufcopyhttp01';
const _copier = 'Ufcopyhttp02';
const _a = 'Bfcopyhttp0A';
const _b = 'Bfcopyhttp0B';
const _fact = 'Ffcopyhttp01';
const _removedFact = 'Ffcopyhttp02';
const _missingFact = 'Ffcopyhttp99';

const _copyMutation = r'''
mutation ($source: String!, $destination: String!) {
  BeaconFactCardCopy(
    sourceFactCardId: $source, destinationBeaconId: $destination
  ) { factCardId outcome }
}
''';

final _t0 = DateTime.utc(2026, 11, 1, 12);

Future<void> main() async {
  final target = DisposablePgTarget.fromNamedEnvironment(
    envVarName: 'TENTURA_FACT_COPY_ENDPOINT_TEST_DB',
    defaultNamePrefix: 'tentura_test_fact_copy_endpoint',
  );
  final unavailable = await pgSkipReason(target);
  if (unavailable != null) {
    test('fact copy endpoint tests require reachable Postgres', () {
      fail(unavailable);
    });
    return;
  }

  group('BeaconFactCardCopy over the V2 GraphQL endpoint', () {
    late DisposablePgWriterSession session;
    late Connection writer;
    late Handler graphql;

    setUpAll(() async {
      session = await setUpDisposablePgWriter(target: target);
      writer = session.writer;
      await _seed(writer);
      final db = target.databaseEnv;
      final env = Env(
        environment: Environment.dev,
        serverUri: Uri.parse('http://127.0.0.1:2080'),
        publicOrigin: 'http://127.0.0.1:2080',
        publicKey: Env.kJwtPublicKey,
        privateKey: Env.kJwtPrivateKey,
        pgHost: db.pgHost,
        pgPort: db.pgPort,
        pgDatabase: db.pgDatabase,
        pgUsername: db.pgUsername,
        pgPassword: db.pgPassword,
        maxConnectionCount: 8,
        workersCount: 1,
        printEnv: false,
        isDebugModeOn: false,
      );
      getIt
        ..skipDoubleRegistration = true
        ..registerFactory<TenturaDb>(
          () => TenturaDb.scoped(getIt<MainDbPool>()),
        );
      await configureSessionDatabaseTestGraph(env);
      final controller = GraphqlController(env);
      graphql = (request) => controller.handler(
        request.change(
          context: {kContextJwtKey: const JwtEntity(sub: _copier)},
        ),
      );
    });

    tearDownAll(() async {
      getIt.skipDoubleRegistration = false;
      await getIt.reset();
      await tearDownDisposablePgWriter(session: session);
    });

    Future<Map<String, dynamic>> run(String source, String destination) async {
      final response = await graphql(
        Request(
          'POST',
          Uri.parse('http://localhost/api/v2/graphql'),
          headers: {'content-type': 'application/json'},
          body: jsonEncode({
            'query': _copyMutation,
            'variables': {'source': source, 'destination': destination},
          }),
        ),
      );
      expect(response.statusCode, 200);
      return jsonDecode(await response.readAsString()) as Map<String, dynamic>;
    }

    Future<List<Map<String, Object?>>> rows(
      String sql, [
      Map<String, Object?> parameters = const {},
    ]) async {
      final result = await writer.execute(
        Sql.named(sql),
        parameters: parameters,
      );
      return [for (final r in result) r.toColumnMap()];
    }

    Future<List<Map<String, Object?>>> factsBroughtLines(String beaconId) =>
        rows(
          '''
SELECT id, author_id, system_payload
FROM public.beacon_room_message
WHERE beacon_id = @b AND semantic_marker = @marker
ORDER BY created_at, id
''',
          {'b': beaconId, 'marker': BeaconRoomSemanticMarker.factsBrought},
        );

    Future<List<Map<String, Object?>>> factPinnedEvents(String beaconId) =>
        rows(
          '''
SELECT id, diff::text AS diff
FROM public.beacon_activity_event
WHERE beacon_id = @b AND type = @type
''',
          {'b': beaconId, 'type': BeaconActivityEventTypeBits.factPinned},
        );

    /// Everything about A that a copy must leave alone.
    Future<Map<String, Object?>> sourceSnapshot() async => {
      'messages': await rows(
        'SELECT id FROM public.beacon_room_message WHERE beacon_id = @a '
        'ORDER BY id',
        {'a': _a},
      ),
      'events': await rows(
        'SELECT id FROM public.beacon_activity_event WHERE beacon_id = @a '
        'ORDER BY id',
        {'a': _a},
      ),
      'fact': await rows(
        'SELECT fact_text, status::integer AS status, revision_seq, '
        'visibility::integer AS visibility, updated_at '
        'FROM public.beacon_fact_card WHERE id = @f',
        {'f': _fact},
      ),
      'revisions': await rows(
        'SELECT seq, kind::integer AS kind, actor_id, fact_text '
        'FROM public.beacon_fact_card_revision WHERE fact_card_id = @f '
        'ORDER BY seq',
        {'f': _fact},
      ),
    };

    test('a member of both Requests copies a fact: created, origin recorded, '
        'one «facts brought» line and factPinned event in the destination, '
        'nothing new in the source', () async {
      final sourceBefore = await sourceSnapshot();

      final body = await run(_fact, _b);
      expect(body['errors'], isNull, reason: jsonEncode(body));
      expect(
        (body['data'] as Map<String, dynamic>?)?['BeaconFactCardCopy'],
        isA<Map<String, dynamic>>(),
        reason: 'the copy answer: ${jsonEncode(body)}',
      );
      final result =
          (body['data'] as Map<String, dynamic>)['BeaconFactCardCopy']
              as Map<String, dynamic>;
      expect(result['outcome'], 'created');
      final copyId = result['factCardId'] as String;
      expect(copyId, isNot(_fact));

      final copy = (await rows(
        '''
SELECT beacon_id, fact_text, visibility::integer AS visibility, pinned_by,
       origin_fact_card_id, origin_revision_seq,
       origin_beacon_kind::integer AS origin_beacon_kind
FROM public.beacon_fact_card WHERE id = @id
''',
        {'id': copyId},
      )).single;
      expect(copy['beacon_id'], _b);
      expect(copy['fact_text'], 'The bridge opens at nine');
      expect(copy['visibility'], BeaconFactCardVisibilityBits.room);
      expect(copy['pinned_by'], _copier);
      expect(copy['origin_fact_card_id'], _fact);
      expect(copy['origin_revision_seq'], 2);
      expect(copy['origin_beacon_kind'], 0);

      final revisions = await rows(
        'SELECT seq, kind::integer AS kind, actor_id '
        'FROM public.beacon_fact_card_revision WHERE fact_card_id = @id',
        {'id': copyId},
      );
      expect(revisions, [
        {
          'seq': 1,
          'kind': BeaconFactCardRevisionKindBits.copied,
          'actor_id': _copier,
        },
      ]);

      final lines = await factsBroughtLines(_b);
      expect(lines, hasLength(1));
      expect(lines.single['author_id'], _copier);
      final raw = lines.single['system_payload'];
      final payload = Map<String, Object?>.from(
        (raw is String ? jsonDecode(raw) : raw)! as Map,
      );
      expect(payload['factCardIds'], [copyId]);
      expect(payload['count'], 1);
      expect(payload['originBeaconKind'], 0);

      final events = await factPinnedEvents(_b);
      expect(events, hasLength(1));
      expect(events.single['diff'], contains(copyId));

      expect(await sourceSnapshot(), sourceBefore, reason: 'source unchanged');

      // Asking again adds nothing to the destination.
      final again = await run(_fact, _b);
      expect(again['errors'], isNull, reason: jsonEncode(again));
      final second =
          (again['data'] as Map<String, dynamic>)['BeaconFactCardCopy']
              as Map<String, dynamic>;
      expect(second['outcome'], 'alreadyThere');
      expect(second['factCardId'], copyId);
      expect(await factsBroughtLines(_b), hasLength(1));
      expect(await factPinnedEvents(_b), hasLength(1));
    });

    test('a removed or missing source answers the same error with code 1352',
        () async {
      final removed = await run(_removedFact, _b);
      final missing = await run(_missingFact, _b);

      Map<String, dynamic> errorOf(Map<String, dynamic> body) {
        final errors = body['errors'] as List<dynamic>?;
        expect(errors, isNotNull, reason: jsonEncode(body));
        return errors!.single as Map<String, dynamic>;
      }

      final removedError = errorOf(removed);
      final missingError = errorOf(missing);
      expect(
        removedError['extensions'],
        containsPair('code', '1352'),
        reason: jsonEncode(removed),
      );
      expect(
        missingError['extensions'],
        containsPair('code', '1352'),
        reason: jsonEncode(missing),
      );
      expect(removedError['message'], missingError['message']);
    });
  });
}

Future<void> _seed(Connection writer) async {
  await writer.execute(
    Sql.named('''
INSERT INTO public."user" (id, display_name, public_key)
VALUES (@author, 'Author', @k1), (@copier, 'Copier', @k2)
'''),
    parameters: {
      'author': _author,
      'copier': _copier,
      'k1': pgTestPublicKey('fcopyhttp', 1),
      'k2': pgTestPublicKey('fcopyhttp', 2),
    },
  );
  await writer.execute(
    Sql.named('''
INSERT INTO public.beacon
  (id, user_id, title, description, status, kind, published_at,
   is_discoverable)
VALUES (@a, @author, 'Source', 'd', 0, 0, @t0, false),
       (@b, @author, 'Destination', 'd', 0, 0, @t0, false)
'''),
    parameters: {'a': _a, 'b': _b, 'author': _author, 't0': _t0},
  );
  for (final (i, beaconId) in [_a, _b].indexed) {
    await writer.execute(
      Sql.named('''
INSERT INTO public.beacon_participant
  (id, beacon_id, user_id, role, status, room_access)
VALUES (@id, @beacon, @copier, 0, 0, 3)
'''),
      parameters: {'id': 'Pfcopyhttp$i', 'beacon': beaconId, 'copier': _copier},
    );
  }
  for (final (id, status, texts) in [
    (_fact, BeaconFactCardStatusBits.corrected, [
      'The bridge opens at eight',
      'The bridge opens at nine',
    ]),
    (_removedFact, BeaconFactCardStatusBits.removed, ['Gone fact']),
  ]) {
    await writer.execute(
      Sql.named('''
INSERT INTO public.beacon_fact_card
  (id, beacon_id, fact_text, visibility, pinned_by, status, created_at,
   updated_at, revision_seq)
VALUES (@id, @a, @text, ${BeaconFactCardVisibilityBits.public}, @author,
        @status, @t0, @t0, @head)
'''),
      parameters: {
        'id': id,
        'a': _a,
        'text': texts.last,
        'author': _author,
        'status': status,
        't0': _t0,
        'head': texts.length,
      },
    );
    for (final (i, text) in texts.indexed) {
      await writer.execute(
        Sql.named('''
INSERT INTO public.beacon_fact_card_revision
  (fact_card_id, seq, fact_text, actor_id, kind, created_at, attachments_json)
VALUES (@id, @seq, @text, @author, @kind, @t0, '[]'::jsonb)
'''),
        parameters: {
          'id': id,
          'seq': i + 1,
          'text': text,
          'author': _author,
          'kind': i == 0
              ? BeaconFactCardRevisionKindBits.created
              : BeaconFactCardRevisionKindBits.edited,
          't0': _t0,
        },
      );
    }
  }
}
