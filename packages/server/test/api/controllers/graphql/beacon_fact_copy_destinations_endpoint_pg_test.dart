@Tags(['pg', 'multi-connection'])
@Timeout(Duration(minutes: 3))
library;

// Where a fact can be copied to, over the V2 GraphQL endpoint: the real
// request path from HTTP through the resolver, use case and repository to
// Postgres.
import 'dart:convert';

import 'package:injectable/injectable.dart' show Environment;
import 'package:postgres/postgres.dart';
import 'package:shelf_plus/shelf_plus.dart';
import 'package:test/test.dart';

import 'package:tentura_server/api/controllers/graphql_controller.dart';
import 'package:tentura_root/domain/entity/beacon_status.dart';
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

const _caller = 'Ufdest000001';
const _other = 'Ufdest000002'; // authors the source and the foreign Requests
const _many = 'Ufdest000003'; // has 101 eligible destinations
const _lonely = 'Ufdest000004'; // authors only the source Request
const _expiring = 'Ufdest000005'; // has a Request with a stored expiry
const _selfAuthor = 'Ufdest000007'; // authors the open source Request
const _closer = 'Ufdest000006'; // owns the Request the closing test closes

const _s = 'Bfdest0000S'; // source Request, caller is admitted
const _a = 'Bfdest0000A'; // caller authors
const _b = 'Bfdest0000B'; // caller stewards
const _c = 'Bfdest0000C'; // caller admitted (room_access 3)
const _closed = 'Bfdest00CLO'; // caller authors, closed
const _cancelled = 'Bfdest00CAN'; // caller authors, cancelled
const _deleted = 'Bfdest00DEL'; // caller authors, deleted
const _admittedClosed = 'Bfdest00ACL'; // caller admitted, closed
const _admittedCancelled = 'Bfdest00ACA'; // caller admitted, cancelled
const _left = 'Bfdest00LEF'; // room_access 5
const _requested = 'Bfdest00REQ'; // room_access 1
const _invited = 'Bfdest00INV'; // room_access 2
const _draft =
    'Bfdest00DRA'; // caller authors, draft status, but published_at set
const _post = 'Bfdest00POS'; // caller authors, published Post
const _readOnly = 'Bfdest00RDO'; // caller can read, no role
const _hidden = 'Bfdest00HID'; // source Request the caller cannot read
const _mS = 'Bfdestm000S'; // source Request of _many
const _selfS = 'Bfdestself0S'; // source Request the caller authors
const _selfT = 'Bfdestself0T'; // the only other eligible Request
const _lS = 'Bfdestl000S'; // source Request of _lonely
const _eS = 'Bfdeste000S'; // source Request of _expiring
const _eT = 'Bfdeste000T'; // open Request with a stored expiry
const _cS = 'Bfdestc000S'; // source Request of _closer
const _cT = 'Bfdestc000T'; // open Request that the closing test closes

const _factS = 'Ffdest000001'; // readable source fact
const _factRemoved = 'Ffdest000002';
const _factHidden = 'Ffdest000003';
const _factMany = 'Ffdest000004';
const _factSelf = 'Ffdest000008';
const _factLonely = 'Ffdest000005';
const _factExpiring = 'Ffdest000006';
const _factCloser = 'Ffdest000007';

const _query = r'''
query ($source: String!) {
  BeaconFactCopyDestinations(sourceFactCardId: $source) {
    id kind title isDraft expiresAt
  }
}
''';

final _t0 = DateTime.utc(2026, 11, 1, 12);
final _expiry = DateTime.utc(2099, 1, 2, 3, 4, 5);

final _unavailableCode = const BeaconExceptionCodes(
  BeaconExceptionCode.factCopySourceUnavailable,
).codeNumber;

String _manyId(int i) => 'Bfdestm${i.toString().padLeft(4, '0')}';

Future<void> main() async {
  final target = DisposablePgTarget.fromNamedEnvironment(
    envVarName: 'TENTURA_FACT_COPY_DESTINATIONS_TEST_DB',
    defaultNamePrefix: 'tentura_test_fact_copy_destinations',
  );
  final unavailable = await pgSkipReason(target);
  if (unavailable != null) {
    test('fact copy destinations tests require reachable Postgres', () {
      fail(unavailable);
    });
    return;
  }

  group('BeaconFactCopyDestinations over the V2 GraphQL endpoint', () {
    late DisposablePgWriterSession session;
    late Connection writer;
    late Handler graphql;
    var caller = _caller;

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
      String source, {
      String as = _caller,
    }) async {
      caller = as;
      final response = await graphql(
        Request(
          'POST',
          Uri.parse('http://localhost/api/v2/graphql'),
          headers: {'content-type': 'application/json'},
          body: jsonEncode({
            'query': _query,
            'variables': {'source': source},
          }),
        ),
      );
      expect(response.statusCode, 200);
      return jsonDecode(await response.readAsString()) as Map<String, dynamic>;
    }

    Future<List<Map<String, dynamic>>> destinations(
      String source, {
      String as = _caller,
    }) async {
      final body = await post(source, as: as);
      expect(body['errors'], isNull, reason: jsonEncode(body));
      final data = body['data'] as Map<String, dynamic>?;
      expect(
        data?['BeaconFactCopyDestinations'],
        isA<List<dynamic>>(),
        reason: jsonEncode(body),
      );
      return [
        for (final r in data!['BeaconFactCopyDestinations'] as List<dynamic>)
          r as Map<String, dynamic>,
      ];
    }

    Future<void> sql(String statement, [Map<String, Object?>? p]) async {
      await writer.execute(Sql.named(statement), parameters: p ?? {});
    }

    test('lists the Requests the caller authors, stewards or is admitted '
        'to, most recently active first, with id, kind, title, isDraft and '
        'expiresAt', () async {
      final rows = [
        for (final r in await destinations(_factS))
          if (r['isDraft'] == false) r,
      ];
      expect([for (final r in rows) r['id']], [_b, _c, _a]);
      expect(rows, [
        for (final id in [_b, _c, _a])
          {
            'id': id,
            'kind': 0,
            'title': 'Title $id',
            'isDraft': false,
            'expiresAt': null,
          },
      ]);
    });

    test('never lists the source Request itself', () async {
      final ids = [for (final r in await destinations(_factS)) r['id']];
      expect(ids, isNot(contains(_s)));
    });

    test(
      'leaves out read-only Requests: closed, cancelled and deleted',
      () async {
        final ids = [for (final r in await destinations(_factS)) r['id']];
        for (final id in [
          _closed,
          _cancelled,
          _deleted,
          _admittedClosed,
          _admittedCancelled,
        ]) {
          expect(ids, isNot(contains(id)), reason: id);
        }
        expect(ids, isNotEmpty);
      },
    );

    test('leaves out Requests where the caller left, only asked or was '
        'only invited', () async {
      final ids = [for (final r in await destinations(_factS)) r['id']];
      for (final id in [_left, _requested, _invited]) {
        expect(ids, isNot(contains(id)), reason: id);
      }
      expect(ids, isNotEmpty);
    });

    test(
      'lists the caller\'s own drafts as drafts, and leaves out Requests '
      'the caller only reads',
      () async {
        // The caller really can read the Request they have no role in.
        final readable = await writer.execute(
          Sql.named('SELECT public.beacon_can_read_content(@b, @u)'),
          parameters: {'b': _readOnly, 'u': _caller},
        );
        expect(readable.single.single, true);
        final rows = await destinations(_factS);
        final ids = [for (final r in rows) r['id']];
        expect(ids, isNot(contains(_readOnly)));
        for (final id in [_draft, _post]) {
          expect(ids, contains(id), reason: id);
          expect(rows.firstWhere((r) => r['id'] == id)['isDraft'], isTrue);
        }
      },
    );

    test('an unreadable source, a removed source and an unknown source are '
        'the factCopySourceUnavailable error with no data', () async {
      expect(_unavailableCode, 1352);
      for (final source in [_factHidden, _factRemoved, 'Ffdest999999']) {
        final body = await post(source);
        final errors = body['errors'] as List<dynamic>?;
        expect(errors, isNotNull, reason: '$source ${jsonEncode(body)}');
        expect(
          (errors!.first as Map<String, dynamic>)['extensions'],
          containsPair('code', '$_unavailableCode'),
          reason: jsonEncode(body),
        );
        final data = body['data'];
        expect(
          data == null ||
              (data is Map<String, dynamic> &&
                  data.containsKey('BeaconFactCopyDestinations') &&
                  data['BeaconFactCopyDestinations'] == null),
          true,
          reason: jsonEncode(body),
        );
      }
    });

    test('returns at most 100 rows: the 100 most recently active, newest '
        'first', () async {
      final rows = await destinations(_factMany, as: _many);
      expect(rows, hasLength(100));
      expect(
        [for (final r in rows) r['id']],
        [for (var i = 0; i < 100; i++) _manyId(i)],
      );
      expect(
        [for (final r in rows) r['id']],
        isNot(contains(_manyId(100))),
      );
    });

    test('is an empty list, not an error, when the only candidate is the '
        'source Request', () async {
      expect(await destinations(_factLonely, as: _lonely), isEmpty);
    });

    test('a Request leaves the list once it is closed', () async {
      expect(
        [for (final r in await destinations(_factCloser, as: _closer)) r['id']],
        [_cT],
      );
      await sql(
        'UPDATE public.beacon SET status = @s WHERE id = @b',
        {'s': BeaconStatus.closed.smallintValue, 'b': _cT},
      );
      expect(await destinations(_factCloser, as: _closer), isEmpty);
    });

    test("expiresAt is the Request's stored expiry", () async {
      final rows = await destinations(_factExpiring, as: _expiring);
      expect(rows, hasLength(1));
      expect(rows.single['id'], _eT);
      expect(
        DateTime.parse(rows.single['expiresAt'] as String).toUtc(),
        _expiry,
      );
    });
  });
}

Future<void> _seed(Connection w) async {
  Future<void> run(String sql, [Map<String, Object?>? p]) async {
    await w.execute(Sql.named(sql), parameters: p ?? {});
  }

  for (final (i, u) in [
    _caller,
    _other,
    _many,
    _lonely,
    _expiring,
    _closer,
    _selfAuthor,
  ].indexed) {
    await run(
      'INSERT INTO public."user" (id, display_name, public_key) '
      'VALUES (@id, @n, @k)',
      {'id': u, 'n': 'User$i', 'k': pgTestPublicKey('fdest', i + 1)},
    );
  }

  Future<void> beacon(
    String id,
    String owner, {
    int status = 0,
    int kind = 0,
    bool published = true,
    bool discoverable = false,
    Duration age = Duration.zero,
  }) async {
    await run(
      '''
INSERT INTO public.beacon
  (id, user_id, title, description, status, kind, published_at,
   is_discoverable, last_activity_at, expires_at)
VALUES (@id, @o, CASE WHEN @kind::integer = 1 THEN '' ELSE 'Title ' || @id END,
        CASE WHEN @kind::integer = 1 THEN '' ELSE 'd' END, @status::integer, @kind::integer,
        @pub, @disc, @act,
        CASE WHEN @kind::integer = 1 THEN @exp::timestamptz END)
''',
      {
        'id': id,
        'o': owner,
        'status': status,
        'kind': kind,
        'pub': published ? _t0 : null,
        'disc': discoverable,
        'act': _t0.subtract(age),
        'exp': DateTime.utc(2099),
      },
    );
  }

  Future<void> participant(String beaconId, String user, int access) async {
    await run(
      '''
INSERT INTO public.beacon_participant
  (id, beacon_id, user_id, role, status, room_access)
VALUES (@id, @b, @u, 0, 0, @access)
''',
      {
        'id': 'Pfd${beaconId.substring(1)}${user.substring(10)}',
        'b': beaconId,
        'u': user,
        'access': access,
      },
    );
  }

  // Source Request: the caller is admitted, so its facts are readable.
  await beacon(_s, _other, age: const Duration(minutes: 1));
  await participant(_s, _caller, 3);

  await beacon(_a, _caller, age: const Duration(hours: 3));
  await beacon(_b, _other, age: const Duration(hours: 1));
  await run(
    'INSERT INTO public.beacon_steward (beacon_id, user_id) VALUES (@b, @u)',
    {'b': _b, 'u': _caller},
  );
  await beacon(_c, _other, age: const Duration(hours: 2));
  await participant(_c, _caller, 3);

  await beacon(
    _closed,
    _caller,
    status: BeaconStatus.closed.smallintValue,
    age: const Duration(minutes: 5),
  );
  await beacon(
    _cancelled,
    _caller,
    status: BeaconStatus.cancelled.smallintValue,
    age: const Duration(minutes: 5),
  );
  await beacon(
    _deleted,
    _caller,
    status: BeaconStatus.deleted.smallintValue,
    age: const Duration(minutes: 5),
  );
  await beacon(
    _admittedClosed,
    _other,
    status: BeaconStatus.closed.smallintValue,
    age: const Duration(minutes: 5),
  );
  await participant(_admittedClosed, _caller, 3);
  await beacon(
    _admittedCancelled,
    _other,
    status: BeaconStatus.cancelled.smallintValue,
    age: const Duration(minutes: 5),
  );
  await participant(_admittedCancelled, _caller, 3);
  for (final (id, access) in [(_left, 5), (_requested, 1), (_invited, 2)]) {
    await beacon(id, _other, age: const Duration(minutes: 5));
    await participant(id, _caller, access);
  }
  await beacon(_draft, _caller, status: BeaconStatus.draft.smallintValue);
  await beacon(_post, _caller, kind: 1, age: const Duration(minutes: 5));
  await beacon(_readOnly, _other, discoverable: true);
  // Forwarded to the caller, who therefore reads it without any room role.
  await run(
    'INSERT INTO public.beacon_forward_edge '
    '(beacon_id, sender_id, recipient_id) VALUES (@b, @o, @r)',
    {'b': _readOnly, 'o': _other, 'r': _caller},
  );
  await beacon(_hidden, _other);

  // _many: the source plus 101 open Requests, index 0 the newest.
  await beacon(_mS, _many, age: const Duration(days: 30));
  for (var i = 0; i <= 100; i++) {
    await beacon(_manyId(i), _many, age: Duration(minutes: 10 + i));
  }
  await beacon(_lS, _lonely);
  await beacon(_selfS, _selfAuthor);
  await beacon(_selfT, _selfAuthor, age: const Duration(hours: 1));

  // A Request with a stored expiry: the shipped check constraint only allows
  // that for Posts, so lift it in this disposable database to see that the
  // endpoint passes the stored value through.
  await run(
    'ALTER TABLE public.beacon DROP CONSTRAINT beacon_post_expires_at_ck',
  );
  await beacon(_eS, _expiring);
  await beacon(_eT, _expiring, age: const Duration(hours: 1));
  await run(
    'UPDATE public.beacon SET expires_at = @e WHERE id = @b',
    {'e': _expiry, 'b': _eT},
  );
  await beacon(_cS, _closer);
  await beacon(_cT, _closer, age: const Duration(hours: 1));

  Future<void> fact(
    String id,
    String beaconId,
    String owner, {
    int status = 0,
  }) async {
    await run(
      '''
INSERT INTO public.beacon_fact_card
  (id, beacon_id, fact_text, visibility, pinned_by, status, created_at,
   updated_at, revision_seq)
VALUES (@id, @b, 'text of ' || @id, @vis, @o, @status, @t0, @t0, 1)
''',
      {
        'id': id,
        'b': beaconId,
        'vis': BeaconFactCardVisibilityBits.public,
        'o': owner,
        'status': status,
        't0': _t0,
      },
    );
    await run(
      '''
INSERT INTO public.beacon_fact_card_revision
  (fact_card_id, seq, fact_text, actor_id, kind, created_at, attachments_json)
VALUES (@id, 1, 'text of ' || @id, @o, @kind, @t0, '[]'::jsonb)
''',
      {
        'id': id,
        'o': owner,
        'kind': BeaconFactCardRevisionKindBits.created,
        't0': _t0,
      },
    );
  }

  await fact(_factS, _s, _other);
  await fact(
    _factRemoved,
    _s,
    _other,
    status: BeaconFactCardStatusBits.removed,
  );
  await fact(_factHidden, _hidden, _other);
  await fact(_factMany, _mS, _many);
  await fact(_factLonely, _lS, _lonely);
  await fact(_factSelf, _selfS, _selfAuthor);
  await fact(_factExpiring, _eS, _expiring);
  await fact(_factCloser, _cS, _closer);
}
