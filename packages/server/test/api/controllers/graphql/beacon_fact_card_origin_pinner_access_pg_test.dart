@Tags(['pg', 'multi-connection'])
@Timeout(Duration(minutes: 3))
library;

// Where a copied fact came from, over the V2 GraphQL endpoint: the real
// request path from HTTP through the resolver, use case and repository to
// Postgres.
import 'dart:convert';

import 'package:injectable/injectable.dart' show Environment;
import 'package:postgres/postgres.dart';
import 'package:shelf_plus/shelf_plus.dart';
import 'package:test/test.dart';

import 'package:tentura_server/api/controllers/graphql_controller.dart';
import 'package:tentura_server/app/di.dart';
import 'package:tentura_server/consts/beacon_fact_card_consts.dart';
import 'package:tentura_server/data/database/main_db_pool.dart';
import 'package:tentura_server/data/database/tentura_db.dart'
    hide isNotNull, isNull;
import 'package:tentura_server/domain/entity/jwt_entity.dart';
import 'package:tentura_server/domain/exception_codes.dart';
import 'package:tentura_server/env.dart';

import '../../../support/disposable_pg_target.dart';
import '../../../support/pg_test_public_keys.dart';
import '../../../support/session_database_di_harness.dart';

const _owner = 'Ufpin0000001'; // author of the source Request
const _pinner = 'Ufpin0000002'; // pinned the source fact, left the room
const _contentReader = 'Ufpin0000003'; // reads A's content, not in its room
const _admitted = 'Ufpin0000004'; // admitted participant of A and B
const _stranger = 'Ufpin0000005'; // reads B, never A
const _leaver = 'Ufpin0000006'; // pinned a fact in A, left, still reads A
const _blocked = 'Ufpin0000007'; // pinned a fact in A, blocked by the owner

const _a = 'Bfpin00000A'; // source Request, not discoverable
// Destination, read only by the forward-edge recipients (pinner, content
// reader, stranger, leaver, blocked) and admitted participants.
const _b = 'Bfpin00000B';
const _d = 'Bfpin00000D'; // destination of a copy of a copy
const _gone = 'Bfpin0000G0'; // source Request that is deleted later

const _srcPinned = 'Ffpin0000001'; // in A, pinned by _pinner
const _srcPinnedRemoved = 'Ffpin0000002'; // in A, pinned by _pinner, removed
const _srcPinnedGone = 'Ffpin0000003'; // in _gone, pinned by _pinner
const _srcOwner = 'Ffpin0000004'; // in A, pinned by _owner
const _srcLeaver = 'Ffpin0000005'; // in A, pinned by _leaver
const _srcBlocked = 'Ffpin0000006'; // in A, pinned by _blocked
const _copyPinned = 'Ffpin0000101';
const _copyPinnedRemoved = 'Ffpin0000102';
const _copyPinnedGone = 'Ffpin0000103';
const _copyOwner = 'Ffpin0000104';
const _copyLeaver = 'Ffpin0000105';
const _copyBlocked = 'Ffpin0000106';
const _copyOfCopy = 'Ffpin0000201'; // in D, copy of _copyOwner

const _originQuery = r'''
query ($beaconId: String!, $factCardId: String!) {
  BeaconFactCardOrigin(beaconId: $beaconId, factCardId: $factCardId) {
    available beaconId factCardId beaconKind changedSinceCopy
    canSeeCopiedRevision copiedRevisionSeq
  }
}
''';

const _destinationsQuery = r'''
query ($source: String!) {
  BeaconFactCopyDestinations(sourceFactCardId: $source) { id }
}
''';

final _unavailableCode = const BeaconExceptionCodes(
  BeaconExceptionCode.factCopySourceUnavailable,
).codeNumber;

final _t0 = DateTime.utc(2026, 11, 1, 12);

const _nothing = <String, Object?>{
  'available': false,
  'beaconId': null,
  'factCardId': null,
  'beaconKind': null,
  'changedSinceCopy': null,
  'canSeeCopiedRevision': null,
  'copiedRevisionSeq': null,
};

Future<void> main() async {
  final target = DisposablePgTarget.fromNamedEnvironment(
    envVarName: 'TENTURA_FACT_ORIGIN_PINNER_TEST_DB',
    defaultNamePrefix: 'tentura_test_fact_origin_pinner',
  );
  final unavailable = await pgSkipReason(target);
  if (unavailable != null) {
    test('fact origin pinner access tests require reachable Postgres', () {
      fail(unavailable);
    });
    return;
  }

  group('BeaconFactCardOrigin access for the people around a copied fact', () {
    late DisposablePgWriterSession session;
    late Connection writer;
    late Handler graphql;
    var caller = _admitted;

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
          context: {kContextJwtKey: JwtEntity(sub: caller)},
        ),
      );
    });

    tearDownAll(() async {
      getIt.skipDoubleRegistration = false;
      await getIt.reset();
      await tearDownDisposablePgWriter(session: session);
    });

    Future<Map<String, dynamic>> post(
      String query,
      Map<String, Object?> variables, {
      String as = _admitted,
    }) async {
      caller = as;
      final response = await graphql(
        Request(
          'POST',
          Uri.parse('http://localhost/api/v2/graphql'),
          headers: {'content-type': 'application/json'},
          body: jsonEncode({'query': query, 'variables': variables}),
        ),
      );
      expect(response.statusCode, 200);
      return jsonDecode(await response.readAsString()) as Map<String, dynamic>;
    }

    Future<Map<String, dynamic>> origin(
      String beaconId,
      String factId, {
      String as = _admitted,
    }) async {
      final body = await post(_originQuery, {
        'beaconId': beaconId,
        'factCardId': factId,
      }, as: as);
      expect(body['errors'], isNull, reason: jsonEncode(body));
      final data = body['data'] as Map<String, dynamic>?;
      expect(
        data?['BeaconFactCardOrigin'],
        isA<Map<String, dynamic>>(),
        reason: jsonEncode(body),
      );
      return data!['BeaconFactCardOrigin'] as Map<String, dynamic>;
    }

    test('the user who pinned the source fact, no longer in its room and '
        'unable to read the source Request, still gets the origin', () async {
      expect(await origin(_b, _copyPinned, as: _pinner), {
        'available': true,
        'beaconId': _a,
        'factCardId': _srcPinned,
        'beaconKind': 0,
        'changedSinceCopy': false,
        'canSeeCopiedRevision': false,
        'copiedRevisionSeq': null,
      });
    });

    test('the user who pinned the source fact, left its room but still reads '
        'the source Request, gets the origin', () async {
      expect(await origin(_b, _copyLeaver, as: _leaver), {
        'available': true,
        'beaconId': _a,
        'factCardId': _srcLeaver,
        'beaconKind': 0,
        'changedSinceCopy': false,
        'canSeeCopiedRevision': false,
        'copiedRevisionSeq': null,
      });
    });

    test('a pinner blocked by the Request author gets no origin, the same '
        'unavailable error as copy destinations', () async {
      for (final query in [
        (_originQuery, {'beaconId': _b, 'factCardId': _copyBlocked}),
        (_destinationsQuery, {'source': _srcBlocked}),
      ]) {
        final body = await post(query.$1, query.$2, as: _blocked);
        final errors = body['errors'] as List<dynamic>?;
        expect(errors, isNotNull, reason: jsonEncode(body));
        expect(
          (errors!.first as Map<String, dynamic>)['extensions'],
          containsPair('code', '$_unavailableCode'),
          reason: jsonEncode(body),
        );
      }
    });

    test('a viewer who reads the source Request but is not in its room gets '
        'the origin without the copied revision', () async {
      expect(await origin(_b, _copyOwner, as: _contentReader), {
        'available': true,
        'beaconId': _a,
        'factCardId': _srcOwner,
        'beaconKind': 0,
        'changedSinceCopy': true,
        'canSeeCopiedRevision': false,
        'copiedRevisionSeq': null,
      });
    });

    test('an admitted participant of the source Request gets the origin '
        'with the copied revision', () async {
      expect(await origin(_b, _copyOwner), {
        'available': true,
        'beaconId': _a,
        'factCardId': _srcOwner,
        'beaconKind': 0,
        'changedSinceCopy': true,
        'canSeeCopiedRevision': true,
        'copiedRevisionSeq': 2,
      });
    });

    test(
      'a stranger to the source Request gets the bare unavailable body',
      () async {
        expect(await origin(_b, _copyOwner, as: _stranger), _nothing);
        expect(await origin(_b, _copyPinned, as: _stranger), _nothing);
      },
    );

    test('the origin of a copy of a copy is the middle copy', () async {
      expect(await origin(_d, _copyOfCopy), {
        'available': true,
        'beaconId': _b,
        'factCardId': _copyOwner,
        'beaconKind': 0,
        'changedSinceCopy': false,
        'canSeeCopiedRevision': true,
        'copiedRevisionSeq': 1,
      });
    });

    test('the origin is available exactly when copy destinations for the same '
        'source fact do not fail as unavailable', () async {
      for (final (viewer, copyId, sourceId) in [
        (_pinner, _copyPinned, _srcPinned),
        (_contentReader, _copyOwner, _srcOwner),
        (_admitted, _copyOwner, _srcOwner),
        (_stranger, _copyOwner, _srcOwner),
        (_stranger, _copyPinned, _srcPinned),
        (_pinner, _copyPinnedRemoved, _srcPinnedRemoved),
        (_pinner, _copyPinnedGone, _srcPinnedGone),
      ]) {
        final available =
            (await origin(_b, copyId, as: viewer))['available'] as bool;
        final body = await post(_destinationsQuery, {
          'source': sourceId,
        }, as: viewer);
        final errors = body['errors'] as List<dynamic>?;
        if (errors != null) {
          expect(
            (errors.first as Map<String, dynamic>)['extensions'],
            containsPair('code', '$_unavailableCode'),
            reason: jsonEncode(body),
          );
        }
        expect(
          available,
          errors == null,
          reason: '$viewer $sourceId: ${jsonEncode(body)}',
        );
      }
    });

    test('the pinner gets the bare unavailable body when the source fact is '
        'removed or the source Request is deleted', () async {
      expect(await origin(_b, _copyPinnedRemoved, as: _pinner), _nothing);
      expect(await origin(_b, _copyPinnedGone, as: _pinner), _nothing);
    });
  });
}

Future<void> _seed(Connection w) async {
  Future<void> run(String sql, [Map<String, Object?>? p]) async {
    await w.execute(Sql.named(sql), parameters: p ?? {});
  }

  for (final (i, u) in [
    _owner,
    _pinner,
    _contentReader,
    _admitted,
    _stranger,
    _leaver,
    _blocked,
  ].indexed) {
    await run(
      'INSERT INTO public."user" (id, display_name, public_key) '
      'VALUES (@id, @n, @k)',
      {'id': u, 'n': 'User$i', 'k': pgTestPublicKey('fpin', i + 1)},
    );
  }
  for (final id in [_a, _b, _d, _gone]) {
    await run(
      '''
INSERT INTO public.beacon
  (id, user_id, title, description, status, kind, published_at,
   is_discoverable)
VALUES (@id, @o, @id, 'd', 0, 0, @t0, false)
''',
      {'id': id, 'o': _owner, 't0': _t0},
    );
  }
  var p = 0;
  Future<void> participant(String beaconId, String user, int access) => run(
    '''
INSERT INTO public.beacon_participant
  (id, beacon_id, user_id, role, status, room_access)
VALUES (@id, @b, @u, 0, 0, @acc)
''',
    {'id': 'Pfpin${p++}', 'b': beaconId, 'u': user, 'acc': access},
  );
  for (final beaconId in [_a, _b, _d]) {
    await participant(beaconId, _admitted, 3);
  }
  // The pinners were in A's room once and left it.
  await participant(_a, _pinner, 0);
  await participant(_gone, _pinner, 0);
  await participant(_a, _leaver, 0);
  await participant(_a, _blocked, 0);

  // Forward edges give Request read access. The pinner reads B only.
  for (final (beaconId, user) in [
    (_b, _pinner),
    (_b, _contentReader),
    (_b, _stranger),
    (_d, _stranger),
    (_a, _contentReader),
    (_a, _leaver),
    (_b, _leaver),
    (_a, _blocked),
    (_b, _blocked),
  ]) {
    await run(
      'INSERT INTO public.beacon_forward_edge '
      '(beacon_id, sender_id, recipient_id) VALUES (@b, @o, @r)',
      {'b': beaconId, 'o': _owner, 'r': user},
    );
  }

  Future<void> fact(
    String id,
    String beaconId,
    String pinnedBy, {
    int status = 0,
    int head = 1,
    int originSeq = 1,
    String? originId,
  }) async {
    await run(
      '''
INSERT INTO public.beacon_fact_card
  (id, beacon_id, fact_text, visibility, pinned_by, status, created_at,
   updated_at, revision_seq, origin_fact_card_id, origin_revision_seq,
   origin_beacon_kind)
VALUES (@id, @b, 'text of ' || @id, @vis, @o, @status, @t0, @t0, @head,
        @oid::text, @oseq::integer, @okind::smallint)
''',
      {
        'id': id,
        'b': beaconId,
        'vis': BeaconFactCardVisibilityBits.public,
        'o': pinnedBy,
        'status': status,
        'head': head,
        't0': _t0,
        'oid': originId,
        'oseq': originId == null ? null : originSeq,
        'okind': originId == null ? null : 0,
      },
    );
    for (var seq = 1; seq <= head; seq++) {
      await run(
        '''
INSERT INTO public.beacon_fact_card_revision
  (fact_card_id, seq, fact_text, actor_id, kind, created_at, attachments_json)
VALUES (@id, @seq, 'text of ' || @id, @o, @kind, @t0, '[]'::jsonb)
''',
        {
          'id': id,
          'seq': seq,
          'o': pinnedBy,
          'kind': originId != null
              ? BeaconFactCardRevisionKindBits.copied
              : BeaconFactCardRevisionKindBits.created,
          't0': _t0,
        },
      );
    }
  }

  await fact(_srcPinned, _a, _pinner);
  await fact(
    _srcPinnedRemoved,
    _a,
    _pinner,
    status: BeaconFactCardStatusBits.removed,
  );
  await fact(_srcPinnedGone, _gone, _pinner);
  // Edited twice since the copy below was taken at revision 2.
  await fact(_srcOwner, _a, _owner, head: 3);
  await fact(_srcLeaver, _a, _leaver);
  await fact(_srcBlocked, _a, _blocked);
  await fact(_copyLeaver, _b, _owner, originId: _srcLeaver);
  await fact(_copyBlocked, _b, _owner, originId: _srcBlocked);
  await fact(_copyPinned, _b, _owner, originId: _srcPinned);
  await fact(_copyPinnedRemoved, _b, _owner, originId: _srcPinnedRemoved);
  await fact(_copyPinnedGone, _b, _owner, originId: _srcPinnedGone);
  await fact(_copyOwner, _b, _owner, originId: _srcOwner, originSeq: 2);
  await fact(_copyOfCopy, _d, _owner, originId: _copyOwner);

  // The owner blocked one of the pinners.
  await run(
    'INSERT INTO public.user_block (blocker_id, blocked_id, origin_id) '
    'VALUES (@o, @u, @u)',
    {'o': _owner, 'u': _blocked},
  );

  // The source Request is deleted (status 2) after its copy was made.
  await run('UPDATE public.beacon SET status = 2 WHERE id = @g', {'g': _gone});
}
