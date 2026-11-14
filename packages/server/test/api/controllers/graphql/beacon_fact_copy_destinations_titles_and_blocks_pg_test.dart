@Tags(['pg', 'multi-connection'])
@Timeout(Duration(minutes: 3))
library;

// Fact copy destinations over the V2 GraphQL endpoint: a published Post is
// titled by its root message excerpt, and a destination whose author the
// caller shares a block with is never offered.
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
import 'package:tentura_server/env.dart';

import '../../../support/disposable_pg_target.dart';
import '../../../support/pg_test_public_keys.dart';
import '../../../support/session_database_di_harness.dart';

const _caller = 'Ufdtb0000001'; // asks for destinations
const _author = 'Ufdtb0000002'; // authors the foreign Requests and Posts

const _source = 'Bfdtb000000S'; // source Request, caller admitted
const _post = 'Bfdtb0000POS'; // caller's published Post, short root text
const _longPost = 'Bfdtb00POSL'; // caller's published Post, 200-char text
const _request = 'Bfdtb0000REQ'; // caller's published Request
const _draftPost = 'Bfdtb00DRPO'; // caller's draft Post
const _control = 'Bfdtb00CTRL'; // caller admitted, no block
const _blockedByAuthor =
    'Bfdtb00BBA1'; // caller admitted, author blocked caller
const _blockedByCaller =
    'Bfdtb00BBC1'; // caller admitted, caller blocked author
const _blockedSteward = 'Bfdtb00BST1'; // caller steward, author blocked caller
const _stewardControl = 'Bfdtb00SCTL'; // caller steward, no block
const _blockedPost =
    'Bfdtb00BPO1'; // Post caller admitted, author blocked caller

const _factSource = 'Ffdtb0000001';

const _shortText = 'Garden tools to lend';
final _longText = List.generate(
  200,
  (i) => String.fromCharCode(97 + i % 26),
).join();

const _query = r'''
query ($source: String!) {
  BeaconFactCopyDestinations(sourceFactCardId: $source) {
    id kind title isDraft
  }
}
''';

final _t0 = DateTime.utc(2026, 11, 1, 12);

Future<void> main() async {
  final target = DisposablePgTarget.fromNamedEnvironment(
    envVarName: 'TENTURA_FACT_COPY_DESTINATIONS_TITLES_TEST_DB',
    defaultNamePrefix: 'tentura_test_fact_copy_dest_titles',
  );
  final unavailable = await pgSkipReason(target);
  if (unavailable != null) {
    test('fact copy destination titles tests require reachable Postgres', () {
      fail(unavailable);
    });
    return;
  }

  group('BeaconFactCopyDestinations titles and block rule', () {
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
          context: {kContextJwtKey: const JwtEntity(sub: _caller)},
        ),
      );
    });

    tearDownAll(() async {
      getIt.skipDoubleRegistration = false;
      await getIt.reset();
      await tearDownDisposablePgWriter(session: session);
    });

    Future<Map<String, Map<String, dynamic>>> byId() async {
      final response = await graphql(
        Request(
          'POST',
          Uri.parse('http://localhost/api/v2/graphql'),
          headers: {'content-type': 'application/json'},
          body: jsonEncode({
            'query': _query,
            'variables': {'source': _factSource},
          }),
        ),
      );
      expect(response.statusCode, 200);
      final body =
          jsonDecode(await response.readAsString()) as Map<String, dynamic>;
      expect(body['errors'], isNull, reason: jsonEncode(body));
      return {
        for (final r
            in (body['data']
                    as Map<String, dynamic>)['BeaconFactCopyDestinations']
                as List<dynamic>)
          (r as Map<String, dynamic>)['id'] as String: r,
      };
    }

    test('a published Post is titled by its root message text', () async {
      final rows = await byId();
      expect(rows[_post], isNotNull);
      expect(rows[_post]!['isDraft'], false);
      expect(rows[_post]!['title'], _shortText);
    });

    test('a long root message is cut to its first 120 characters', () async {
      final rows = await byId();
      expect(rows[_longPost]?['title'], _longText.substring(0, 120));
    });

    test('a published Request keeps its title and a draft Post keeps its '
        'description excerpt', () async {
      final rows = await byId();
      expect(rows[_request]?['title'], 'Need a ladder');
      expect(rows[_draftPost]?['title'], 'Draft text');
      expect(rows[_draftPost]?['isDraft'], true);
    });

    test(
      'an admitted participant without any block sees the Request',
      () async {
        expect((await byId()).keys, contains(_control));
      },
    );

    test('a Request whose author blocked the caller is not offered', () async {
      final ids = (await byId()).keys;
      expect(ids, contains(_control));
      expect(ids, isNot(contains(_blockedByAuthor)));
    });

    test('a Request whose author the caller blocked is not offered', () async {
      final ids = (await byId()).keys;
      expect(ids, contains(_control));
      expect(ids, isNot(contains(_blockedByCaller)));
    });

    test('a Request the caller stewards is offered without a block and not '
        'offered when its author blocked the caller', () async {
      final ids = (await byId()).keys;
      expect(ids, contains(_stewardControl));
      expect(ids, isNot(contains(_blockedSteward)));
    });

    test('a Post the caller is admitted to is not offered when its author '
        'blocked the caller', () async {
      final ids = (await byId()).keys;
      expect(ids, contains(_control));
      expect(ids, isNot(contains(_blockedPost)));
    });
  });
}

Future<void> _seed(Connection w) async {
  Future<void> run(String sql, [Map<String, Object?>? p]) async {
    await w.execute(Sql.named(sql), parameters: p ?? {});
  }

  for (final (i, u) in [_caller, _author].indexed) {
    await run(
      'INSERT INTO public."user" (id, display_name, public_key) '
      'VALUES (@id, @n, @k)',
      {'id': u, 'n': 'User$i', 'k': pgTestPublicKey('fdtb', i + 1)},
    );
  }

  var n = 0;
  Future<void> beacon(
    String id,
    String owner, {
    int kind = 0,
    int status = 0,
    bool published = true,
    String title = '',
    String description = '',
    String? rootText,
  }) async {
    n++;
    await run(
      '''
INSERT INTO public.beacon
  (id, user_id, title, description, status, kind, published_at,
   is_discoverable, last_activity_at, expires_at)
VALUES (@id, @o, @title, @desc, @status::integer, @kind::integer, @pub, false, @act,
        CASE WHEN @kind::integer = 1 THEN @exp::timestamptz END)
''',
      {
        'id': id,
        'o': owner,
        'title': title,
        'desc': description,
        'status': status,
        'kind': kind,
        'pub': published ? _t0 : null,
        'act': _t0.subtract(Duration(minutes: n)),
        'exp': DateTime.utc(2099),
      },
    );
    if (rootText != null) {
      final msg = 'Rfdtb${id.substring(6)}';
      await run(
        'INSERT INTO public.beacon_room_message (id, beacon_id, author_id, body) '
        'VALUES (@m, @b, @o, @t)',
        {'m': msg, 'b': id, 'o': owner, 't': rootText},
      );
      await run(
        'UPDATE public.beacon SET post_root_message_id = @m WHERE id = @b',
        {'m': msg, 'b': id},
      );
    }
  }

  Future<void> participant(String beaconId, String user, int access) async {
    await run(
      '''
INSERT INTO public.beacon_participant
  (id, beacon_id, user_id, role, status, room_access)
VALUES (@id, @b, @u, 0, 0, @access)
''',
      {
        'id': 'Pft${beaconId.substring(1)}',
        'b': beaconId,
        'u': user,
        'access': access,
      },
    );
  }

  Future<void> block(String blocker, String blocked) => run(
    'INSERT INTO public.user_block (blocker_id, blocked_id, origin_id) '
    'VALUES (@a, @b, @a)',
    {'a': blocker, 'b': blocked},
  );

  await beacon(_source, _author, title: 'Source');
  await participant(_source, _caller, 3);

  await beacon(_post, _caller, kind: 1, rootText: _shortText);
  await beacon(_longPost, _caller, kind: 1, rootText: _longText);
  await beacon(_request, _caller, title: 'Need a ladder', description: 'd');
  await beacon(
    _draftPost,
    _caller,
    kind: 1,
    published: false,
    description: 'Draft text',
  );

  await beacon(_control, _author, title: 'Control');
  await participant(_control, _caller, 3);

  await beacon(_blockedByAuthor, _author, title: 'Blocked by author');
  await participant(_blockedByAuthor, _caller, 3);
  await beacon(_blockedByCaller, _author, title: 'Blocked by caller');
  await participant(_blockedByCaller, _caller, 3);
  await beacon(_blockedSteward, _author, title: 'Blocked steward');
  await run(
    'INSERT INTO public.beacon_steward (beacon_id, user_id) VALUES (@b, @u)',
    {'b': _blockedSteward, 'u': _caller},
  );
  await beacon(_stewardControl, _author, title: 'Steward control');
  await run(
    'INSERT INTO public.beacon_steward (beacon_id, user_id) VALUES (@b, @u)',
    {'b': _stewardControl, 'u': _caller},
  );
  await beacon(_blockedPost, _author, kind: 1, rootText: 'Blocked post text');
  await participant(_blockedPost, _caller, 3);

  // Blocks are per author, so one pair would hide every Request of that
  // author: use a second author for the caller-blocked and Post cases.
  await run(
    'INSERT INTO public."user" (id, display_name, public_key) '
    'VALUES (@id, @n, @k)',
    {'id': 'Ufdtb0000003', 'n': 'User3', 'k': pgTestPublicKey('fdtb', 3)},
  );
  await run(
    'INSERT INTO public."user" (id, display_name, public_key) '
    'VALUES (@id, @n, @k)',
    {'id': 'Ufdtb0000004', 'n': 'User4', 'k': pgTestPublicKey('fdtb', 4)},
  );
  await run(
    'INSERT INTO public."user" (id, display_name, public_key) '
    'VALUES (@id, @n, @k)',
    {'id': 'Ufdtb0000005', 'n': 'User5', 'k': pgTestPublicKey('fdtb', 5)},
  );
  await run(
    'INSERT INTO public."user" (id, display_name, public_key) '
    'VALUES (@id, @n, @k)',
    {'id': 'Ufdtb0000006', 'n': 'User6', 'k': pgTestPublicKey('fdtb', 6)},
  );
  for (final (id, owner) in [
    (_blockedByAuthor, 'Ufdtb0000003'),
    (_blockedByCaller, 'Ufdtb0000004'),
    (_blockedSteward, 'Ufdtb0000005'),
    (_blockedPost, 'Ufdtb0000006'),
  ]) {
    await run('UPDATE public.beacon SET user_id = @o WHERE id = @b', {
      'o': owner,
      'b': id,
    });
  }
  await block('Ufdtb0000003', _caller);
  await block(_caller, 'Ufdtb0000004');
  await block('Ufdtb0000005', _caller);
  await block('Ufdtb0000006', _caller);

  await run(
    '''
INSERT INTO public.beacon_fact_card
  (id, beacon_id, fact_text, visibility, pinned_by, status, created_at,
   updated_at, revision_seq)
VALUES (@id, @b, 'text', @vis, @o, 0, @t0, @t0, 1)
''',
    {
      'id': _factSource,
      'b': _source,
      'vis': BeaconFactCardVisibilityBits.public,
      'o': _author,
      't0': _t0,
    },
  );
  await run(
    '''
INSERT INTO public.beacon_fact_card_revision
  (fact_card_id, seq, fact_text, actor_id, kind, created_at, attachments_json)
VALUES (@id, 1, 'text', @o, @kind, @t0, '[]'::jsonb)
''',
    {
      'id': _factSource,
      'o': _author,
      'kind': BeaconFactCardRevisionKindBits.created,
      't0': _t0,
    },
  );
}
