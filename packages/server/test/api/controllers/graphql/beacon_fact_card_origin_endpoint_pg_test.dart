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
import 'package:tentura_server/consts/beacon_activity_event_consts.dart';
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

const _owner = 'Uforigin0001';
const _member = 'Uforigin0002'; // uses the room of A and of the destinations
const _reader = 'Uforigin0003'; // reads Requests only, no room
const _a = 'Bforigin00A'; // source Request, discoverable
const _b = 'Bforigin00B'; // destination, discoverable
const _c = 'Bforigin00C'; // private source, reader cannot see it
const _d = 'Bforigin00D'; // source Request that is deleted later
const _e = 'Bforigin00E'; // destination of a copy of a copy
const _h = 'Bforigin00H'; // destination for a copy made through the endpoint

const _src = 'Fforigin0001';
const _srcEdited = 'Fforigin0002';
const _srcRemoved = 'Fforigin0003';
const _srcDeleted = 'Fforigin0004';
const _srcPrivate = 'Fforigin0005';
const _srcAtTwo = 'Fforigin0006';
const _srcForHistory = 'Fforigin0007';
const _srcLive = 'Fforigin0009';
const _ordinary = 'Fforigin0008';
const _copy = 'Fforigin0101';
const _copyEdited = 'Fforigin0102';
const _copyRemoved = 'Fforigin0103';
const _copyDeleted = 'Fforigin0104';
const _copyDangling = 'Fforigin0105';
const _copyPrivate = 'Fforigin0106';
const _copyAtTwo = 'Fforigin0107';
const _copyOfCopy = 'Fforigin0201';

const _originQuery = r'''
query ($beaconId: String!, $factCardId: String!) {
  BeaconFactCardOrigin(beaconId: $beaconId, factCardId: $factCardId) {
    available beaconId factCardId beaconKind changedSinceCopy
    canSeeCopiedRevision copiedRevisionSeq
  }
}
''';

const _listQuery = r'''
query ($beaconId: String!) {
  BeaconFactCardList(beaconId: $beaconId) { id originBeaconKind }
}
''';

const _historyQuery = r'''
query ($beaconId: String!, $factCardId: String!) {
  BeaconFactCardRevisions(beaconId: $beaconId, factCardId: $factCardId) {
    entries { entry kind seq }
  }
}
''';

const _copyMutation = r'''
mutation ($source: String!, $destination: String!) {
  BeaconFactCardCopy(
    sourceFactCardId: $source, destinationBeaconId: $destination
  ) { factCardId outcome }
}
''';

final _t0 = DateTime.utc(2026, 11, 1, 12);

final _unavailableCode = const BeaconExceptionCodes(
  BeaconExceptionCode.factCopySourceUnavailable,
).codeNumber;

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
    envVarName: 'TENTURA_FACT_ORIGIN_ENDPOINT_TEST_DB',
    defaultNamePrefix: 'tentura_test_fact_origin_endpoint',
  );
  final unavailable = await pgSkipReason(target);
  if (unavailable != null) {
    test('fact origin endpoint tests require reachable Postgres', () {
      fail(unavailable);
    });
    return;
  }

  group('BeaconFactCardOrigin over the V2 GraphQL endpoint', () {
    late DisposablePgWriterSession session;
    late Connection writer;
    late Handler graphql;
    var caller = _member;

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
      String as = _member,
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
      String as = _member,
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

    Future<void> sql(String statement, [Map<String, Object?>? p]) async {
      await writer.execute(Sql.named(statement), parameters: p ?? {});
    }

    test('a room member gets the source Request, fact and kind, the seq read '
        'at copy time, and no change until the source is edited', () async {
      expect(await origin(_b, _copy), {
        'available': true,
        'beaconId': _a,
        'factCardId': _src,
        'beaconKind': 0,
        'changedSinceCopy': false,
        'canSeeCopiedRevision': true,
        'copiedRevisionSeq': 1,
      });
    });

    test('after the source is edited the copy is flagged changed while the '
        'copied seq stays', () async {
      expect(
        (await origin(_b, _copyEdited))['changedSinceCopy'],
        false,
      );
      await sql(
        'UPDATE public.beacon_fact_card SET revision_seq = 3 WHERE id = @f',
        {'f': _srcEdited},
      );
      final body = await origin(_b, _copyEdited);
      expect(body['changedSinceCopy'], true);
      expect(body['copiedRevisionSeq'], 2);
      expect(body['available'], true);
    });

    test(
      'a source copied at revision 2 reports seq 2 and not changed',
      () async {
        final body = await origin(_b, _copyAtTwo);
        expect(body['copiedRevisionSeq'], 2);
        expect(body['changedSinceCopy'], false);
      },
    );

    test(
      'editing the copy itself does not mark it changed since copy',
      () async {
        await sql(
          'UPDATE public.beacon_fact_card SET revision_seq = 2, '
          "fact_text = 'copy edited locally' WHERE id = @f",
          {'f': _copyAtTwo},
        );
        expect((await origin(_b, _copyAtTwo))['changedSinceCopy'], false);
      },
    );

    test('copying a source edited to revision 2 records seq 2; a later edit '
        'of the source flags the change and keeps the copied seq', () async {
      await sql(
        'INSERT INTO public.beacon_fact_card_revision '
        '(fact_card_id, seq, fact_text, actor_id, kind, created_at, '
        "attachments_json) VALUES (@f, 2, 'live edit', @o, @kind, @t0, "
        "'[]'::jsonb)",
        {
          'f': _srcLive,
          'o': _owner,
          'kind': BeaconFactCardRevisionKindBits.edited,
          't0': _t0,
        },
      );
      await sql(
        'UPDATE public.beacon_fact_card SET revision_seq = 2, '
        "fact_text = 'live edit' WHERE id = @f",
        {'f': _srcLive},
      );
      final copied = await post(_copyMutation, {
        'source': _srcLive,
        'destination': _h,
      });
      expect(copied['errors'], isNull, reason: jsonEncode(copied));
      final copyId =
          ((copied['data'] as Map<String, dynamic>)['BeaconFactCardCopy']
                  as Map<String, dynamic>)['factCardId']
              as String;

      final first = await origin(_h, copyId);
      expect(first['available'], true);
      expect(first['factCardId'], _srcLive);
      expect(first['copiedRevisionSeq'], 2);
      expect(first['changedSinceCopy'], false);

      await sql(
        'UPDATE public.beacon_fact_card SET revision_seq = 3 WHERE id = @f',
        {'f': _srcLive},
      );
      final second = await origin(_h, copyId);
      expect(second['changedSinceCopy'], true);
      expect(second['copiedRevisionSeq'], 2);
    });

    test('a reader who sees the source only through Request visibility gets '
        'the source identity but no copied seq and no room claim', () async {
      expect(await origin(_b, _copy, as: _reader), {
        'available': true,
        'beaconId': _a,
        'factCardId': _src,
        'beaconKind': 0,
        'changedSinceCopy': false,
        'canSeeCopiedRevision': false,
        'copiedRevisionSeq': null,
      });
    });

    test(
      'a removed source, a deleted source Request, a dangling id and an '
      'unreadable source all answer the same bare unavailable body',
      () async {
        expect(await origin(_b, _copyRemoved), _nothing);
        expect(await origin(_b, _copyDeleted), _nothing);
        expect(await origin(_b, _copyDangling), _nothing);
        expect(await origin(_b, _copyPrivate, as: _reader), _nothing);
      },
    );

    test(
      'an ordinary fact has no origin: bare unavailable body, no error',
      () async {
        expect(await origin(_b, _ordinary), _nothing);
      },
    );

    test('a fact of another Request, or one the caller cannot read, is the '
        'factCopySourceUnavailable error with no data', () async {
      expect(_unavailableCode, 1352);
      for (final (beaconId, factId, viewer) in [
        (_a, _copy, _member), // the copy lives in B, not A
        (_b, _src, _member), // readable fact, but it lives in A not B
        (_b, _src, _reader), // same, for a Request-only reader
        (_e, _copy, _member), // readable fact in B, asked under E
        (_c, _srcPrivate, _reader), // unreadable Request
      ]) {
        final body = await post(_originQuery, {
          'beaconId': beaconId,
          'factCardId': factId,
        }, as: viewer);
        final errors = body['errors'] as List<dynamic>?;
        expect(errors, isNotNull, reason: jsonEncode(body));
        expect(
          (errors!.first as Map<String, dynamic>)['extensions'],
          containsPair('code', '$_unavailableCode'),
          reason: jsonEncode(body),
        );
        expect(
          (body['data'] as Map<String, dynamic>?)?['BeaconFactCardOrigin'],
          isNull,
        );
      }
    });

    test('the origin of a copy of a copy is only the direct origin', () async {
      expect(await origin(_e, _copyOfCopy), {
        'available': true,
        'beaconId': _b,
        'factCardId': _copy,
        'beaconKind': 0,
        'changedSinceCopy': false,
        'canSeeCopiedRevision': true,
        'copiedRevisionSeq': 1,
      });
    });

    test('the fact list carries originBeaconKind for copies, null for '
        'ordinary facts, and never the origin fact id', () async {
      final body = await post(_listQuery, {'beaconId': _b});
      expect(body['errors'], isNull, reason: jsonEncode(body));
      final rows = {
        for (final r
            in (body['data'] as Map<String, dynamic>)['BeaconFactCardList']
                as List<dynamic>)
          (r as Map<String, dynamic>)['id']: r['originBeaconKind'],
      };
      expect(rows[_copy], 0);
      expect(rows[_ordinary], isNull);
      expect(rows.containsKey(_ordinary), true);

      // No origin fact id anywhere in the payload, under any name.
      final raw = jsonEncode(body);
      for (final originId in [
        _src,
        _srcEdited,
        _srcRemoved,
        _srcDeleted,
        _srcPrivate,
        _srcAtTwo,
        'Fforigin9999',
      ]) {
        expect(raw, isNot(contains(originId)));
      }
    });

    test('the history of a copy made through the endpoint has the copied '
        'revision and no factPinned event; an ordinary fact keeps its '
        'factPinned event', () async {
      final copied = await post(_copyMutation, {
        'source': _srcForHistory,
        'destination': _h,
      });
      expect(copied['errors'], isNull, reason: jsonEncode(copied));
      final copyId =
          ((copied['data'] as Map<String, dynamic>)['BeaconFactCardCopy']
                  as Map<String, dynamic>)['factCardId']
              as String;

      Future<List<Map<String, dynamic>>> entries(
        String beaconId,
        String id,
      ) async {
        final body = await post(_historyQuery, {
          'beaconId': beaconId,
          'factCardId': id,
        });
        expect(body['errors'], isNull, reason: jsonEncode(body));
        return [
          for (final e
              in ((body['data']
                          as Map<String, dynamic>)['BeaconFactCardRevisions']
                      as Map<String, dynamic>)['entries']
                  as List<dynamic>)
            e as Map<String, dynamic>,
        ];
      }

      final copyEntries = await entries(_h, copyId);
      expect(
        [
          for (final e in copyEntries)
            if (e['entry'] == 'revision') e['kind'],
        ],
        [BeaconFactCardRevisionKindBits.copied],
      );
      expect(
        copyEntries.where(
          (e) =>
              e['entry'] == 'event' &&
              e['kind'] == BeaconActivityEventTypeBits.factPinned,
        ),
        isEmpty,
      );

      final ordinaryEntries = await entries(_b, _ordinary);
      expect(
        ordinaryEntries.where(
          (e) =>
              e['entry'] == 'event' &&
              e['kind'] == BeaconActivityEventTypeBits.factPinned,
        ),
        hasLength(1),
      );
    });
  });
}

Future<void> _seed(Connection w) async {
  Future<void> run(String sql, [Map<String, Object?>? p]) async {
    await w.execute(Sql.named(sql), parameters: p ?? {});
  }

  for (final (i, u) in [_owner, _member, _reader].indexed) {
    await run(
      'INSERT INTO public."user" (id, display_name, public_key) '
      'VALUES (@id, @n, @k)',
      {'id': u, 'n': 'User$i', 'k': pgTestPublicKey('forigin', i + 1)},
    );
  }
  for (final (id, discoverable) in [
    (_a, true),
    (_b, true),
    (_c, false),
    (_d, true),
    (_e, true),
    (_h, false),
  ]) {
    await run(
      '''
INSERT INTO public.beacon
  (id, user_id, title, description, status, kind, published_at,
   is_discoverable)
VALUES (@id, @o, @id, 'd', 0, 0, @t0, @disc)
''',
      {'id': id, 'o': _owner, 't0': _t0, 'disc': discoverable},
    );
  }
  var p = 0;
  for (final beaconId in [_a, _b, _c, _d, _e, _h]) {
    await run(
      '''
INSERT INTO public.beacon_participant
  (id, beacon_id, user_id, role, status, room_access)
VALUES (@id, @b, @u, 0, 0, 3)
''',
      {'id': 'Pforigin${p++}', 'b': beaconId, 'u': _member},
    );
  }

  Future<void> fact(
    String id,
    String beaconId, {
    int status = 0,
    int head = 1,
    int visibility = BeaconFactCardVisibilityBits.public,
    String? originId,
    int? originSeq,
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
        'vis': visibility,
        'o': _owner,
        'status': status,
        't0': _t0,
        'head': head,
        'oid': originId,
        'oseq': originSeq,
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
          'o': _owner,
          'kind': originId != null
              ? BeaconFactCardRevisionKindBits.copied
              : seq == 1
              ? BeaconFactCardRevisionKindBits.created
              : BeaconFactCardRevisionKindBits.edited,
          't0': _t0,
        },
      );
    }
  }

  await fact(_src, _a);
  await fact(_srcEdited, _a, head: 2);
  await fact(_srcRemoved, _a, status: BeaconFactCardStatusBits.removed);
  await fact(_srcDeleted, _d);
  await fact(_srcPrivate, _c);
  await fact(_srcAtTwo, _a, head: 2);
  await fact(_srcForHistory, _a);
  await fact(_srcLive, _a);
  await fact(_ordinary, _b);
  await fact(_copy, _b, originId: _src, originSeq: 1);
  await fact(_copyEdited, _b, originId: _srcEdited, originSeq: 2);
  await fact(_copyRemoved, _b, originId: _srcRemoved, originSeq: 1);
  await fact(_copyDeleted, _b, originId: _srcDeleted, originSeq: 1);
  await fact(_copyDangling, _b, originId: 'Fforigin9999', originSeq: 1);
  await fact(_copyPrivate, _b, originId: _srcPrivate, originSeq: 1);
  await fact(_copyAtTwo, _b, originId: _srcAtTwo, originSeq: 2);
  await fact(_copyOfCopy, _e, originId: _copy, originSeq: 1);

  // The reader sees A and B as Requests (forwarded) but is in no room.
  for (final beaconId in [_a, _b]) {
    await run(
      'INSERT INTO public.beacon_forward_edge '
      '(beacon_id, sender_id, recipient_id) VALUES (@b, @o, @r)',
      {'b': beaconId, 'o': _owner, 'r': _reader},
    );
  }

  // The ordinary fact was pinned from a message: it has a factPinned event.
  await run(
    '''
INSERT INTO public.beacon_activity_event
  (id, beacon_id, visibility, type, actor_id, diff, fact_card_id)
VALUES ('Vforigin0001', @b, @vis::smallint, @type::smallint, @o,
        jsonb_build_object('factCardId', @f::text, 'factText', 'x'), @f::text)
''',
    {
      'b': _b,
      'vis': BeaconActivityEventVisibilityBits.room,
      'type': BeaconActivityEventTypeBits.factPinned,
      'o': _owner,
      'f': _ordinary,
    },
  );

  // The deleted source Request goes away after its copy was made.
  await run('DELETE FROM public.beacon WHERE id = @d', {'d': _d});
}
