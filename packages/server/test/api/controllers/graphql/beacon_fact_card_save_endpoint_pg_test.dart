@Tags(['pg', 'multi-connection'])
@Timeout(Duration(minutes: 3))
library;

// Saved facts over the V2 GraphQL endpoint: Save / Unsave and `savedByMe` in
// the fact list, on the real request path from HTTP through the resolver,
// use case and repository to Postgres. Also the `user_saved_fact` table the
// migration creates. Server only: input devices, locale and viewport are n/a.
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

const _owner = 'Ufsave000001'; // author of every Request
const _member = 'Ufsave000002'; // uses the rooms of B and G
const _reader = 'Ufsave000003'; // reads B as a Request (forwarded), no room
const _other = 'Ufsave000004'; // another room member of B
const _leaver = 'Ufsave000005'; // member of B whose account is deleted
const _hoarder = 'Ufsave000006'; // member of B who reaches the cap

const _b = 'Bfsave0000B'; // published Request
const _c = 'Bfsave0000C'; // private Request: the reader cannot see it
const _g = 'Bfsave0000G'; // Request deleted after a fact of it was saved
const _h = 'Bfsave0000H'; // private Request the member later leaves

const _fShown = 'Ffsave000001'; // saved by the member, then listed
const _fControl = 'Ffsave000002'; // never saved by anyone
const _fTwice = 'Ffsave000003';
const _fUnsave = 'Ffsave000004';
const _fReader = 'Ffsave000005'; // request-visible fact the reader saves
const _fRoomOnly = 'Ffsave000006'; // discussion-only fact
const _fRemoved = 'Ffsave000007';
const _fPrivate = 'Ffsave000008'; // lives in C
const _fInG = 'Ffsave000009'; // lives in G
const _fLaterRemoved = 'Ffsave000013'; // removed after it was saved
const _fInH = 'Ffsave000014'; // lives in H
const _fLeaver = 'Ffsave000010';
const _fCapA = 'Ffsave000011';
const _fCapB = 'Ffsave000012';

const _saveCap = 200;

const _listQuery = r'''
query ($beaconId: String!) {
  BeaconFactCardList(beaconId: $beaconId) { id savedByMe }
}
''';

const _mutationShapeQuery = '''
{
  __type(name: "Mutation") {
    fields {
      name
      args { name type { kind name ofType { kind name } } }
      type { kind name ofType { kind name } }
    }
  }
}
''';

final _t0 = DateTime.utc(2026, 11, 1, 12);

final _unavailableCode = const BeaconExceptionCodes(
  BeaconExceptionCode.factCopySourceUnavailable,
).codeNumber;

/// The saved-fact cap error is the next Beacon code after
/// factCopySourceUnavailable (1352).
const _savedFactLimitCode = 1353;

Future<void> main() async {
  final target = DisposablePgTarget.fromNamedEnvironment(
    envVarName: 'TENTURA_FACT_SAVE_ENDPOINT_TEST_DB',
    defaultNamePrefix: 'tentura_test_fact_save_endpoint',
  );
  final unavailable = await pgSkipReason(target);
  if (unavailable != null) {
    test('saved fact endpoint tests require reachable Postgres', () {
      fail(unavailable);
    });
    return;
  }

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
      request.change(context: {kContextJwtKey: JwtEntity(sub: caller)}),
    );
  });

  tearDownAll(() async {
    getIt.skipDoubleRegistration = false;
    await getIt.reset();
    await tearDownDisposablePgWriter(session: session);
  });

  Future<List<Map<String, Object?>>> rows(
    String sql, [
    Map<String, Object?> p = const {},
  ]) async {
    final result = await writer.execute(Sql.named(sql), parameters: p);
    return [for (final r in result) r.toColumnMap()];
  }

  Future<int> savedRows({String? userId, String? factId}) async =>
      (await rows(
            'SELECT count(*)::integer AS n FROM public.user_saved_fact '
            'WHERE (@u::text IS NULL OR user_id = @u::text) '
            'AND (@f::text IS NULL OR fact_card_id = @f::text)',
            {'u': userId, 'f': factId},
          )).single['n']!
          as int;

  Future<Map<String, dynamic>> post(
    String query,
    Map<String, Object?> variables, {
    required String as,
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

  Map<String, dynamic>? mutationShapes;

  /// The Mutation root fields by name, read by introspection.
  Future<Map<String, dynamic>> mutationFields() async {
    if (mutationShapes case final cached?) return cached;
    final body = await post(_mutationShapeQuery, const {}, as: _member);
    expect(body['errors'], isNull, reason: jsonEncode(body));
    final fields =
        ((body['data'] as Map<String, dynamic>)['__type']
                as Map<String, dynamic>)['fields']
            as List<dynamic>;
    return mutationShapes = {
      for (final f in fields.cast<Map<String, dynamic>>())
        f['name']! as String: f,
    };
  }

  /// `{ __typename }` when [mutation] answers an object, nothing for a
  /// scalar: the criteria leave the answer type to the implementation.
  Future<String> selectionOf(String mutation) async {
    final field = (await mutationFields())[mutation] as Map<String, dynamic>?;
    expect(field, isNotNull, reason: 'the V2 mutation $mutation must exist');
    var type = field!['type'] as Map<String, dynamic>;
    if (type['kind'] == 'NON_NULL') {
      type = type['ofType'] as Map<String, dynamic>;
    }
    return type['kind'] == 'OBJECT' ? '{ __typename }' : '';
  }

  Future<Map<String, dynamic>> save(
    String beaconId,
    String factId, {
    required String as,
  }) async => post(
    r'mutation ($beaconId: String!, $factCardId: String!) { '
    r'BeaconFactCardSave(beaconId: $beaconId, factCardId: $factCardId) '
    '${await selectionOf('BeaconFactCardSave')} }',
    {'beaconId': beaconId, 'factCardId': factId},
    as: as,
  );

  Future<Map<String, dynamic>> unsave(
    String factId, {
    required String as,
  }) async => post(
    r'mutation ($factCardId: String!) { '
    r'BeaconFactCardUnsave(factCardId: $factCardId) '
    '${await selectionOf('BeaconFactCardUnsave')} }',
    {'factCardId': factId},
    as: as,
  );

  void expectOk(Map<String, dynamic> body) =>
      expect(body['errors'], isNull, reason: jsonEncode(body));

  void expectErrorCode(Map<String, dynamic> body, int code) {
    final errors = body['errors'] as List<dynamic>?;
    expect(errors, isNotNull, reason: jsonEncode(body));
    expect(errors, isNotEmpty, reason: jsonEncode(body));
    expect(
      (errors!.first as Map<String, dynamic>)['extensions'],
      containsPair('code', '$code'),
      reason: jsonEncode(body),
    );
  }

  /// `savedByMe` per fact id, as [viewer] sees the fact list of [beaconId].
  Future<Map<String, Object?>> savedByMe(
    String beaconId, {
    required String viewer,
  }) async {
    final body = await post(_listQuery, {'beaconId': beaconId}, as: viewer);
    expectOk(body);
    final list =
        (body['data'] as Map<String, dynamic>)['BeaconFactCardList']
            as List<dynamic>;
    return {
      for (final row in list.cast<Map<String, dynamic>>())
        row['id']! as String: row['savedByMe'],
    };
  }

  group('the user_saved_fact table', () {
    test(
      'has the user, fact and time columns, a per-user primary key, '
      'a cascading user foreign key and the per-user recency index',
      () async {
        final columns = await rows('''
SELECT column_name, data_type, is_nullable, column_default
FROM information_schema.columns
WHERE table_schema = 'public' AND table_name = 'user_saved_fact'
ORDER BY ordinal_position
''');
        expect(
          {
            for (final c in columns)
              c['column_name']: (c['data_type'], c['is_nullable']),
          },
          {
            'user_id': ('text', 'NO'),
            'fact_card_id': ('text', 'NO'),
            'created_at': ('timestamp with time zone', 'NO'),
          },
        );
        final createdAt = columns.singleWhere(
          (c) => c['column_name'] == 'created_at',
        );
        expect('${createdAt['column_default']}', contains('now()'));

        final primaryKey = await rows('''
SELECT pg_get_constraintdef(c.oid) AS def
FROM pg_constraint c
WHERE c.conrelid = 'public.user_saved_fact'::regclass AND c.contype = 'p'
''');
        expect(primaryKey.single['def'], 'PRIMARY KEY (user_id, fact_card_id)');

        final foreignKeys = await rows('''
SELECT pg_get_constraintdef(c.oid) AS def
FROM pg_constraint c
WHERE c.conrelid = 'public.user_saved_fact'::regclass AND c.contype = 'f'
''');
        expect(
          foreignKeys,
          hasLength(1),
          reason: 'only user_id is a foreign key',
        );
        final fk = foreignKeys.single['def']! as String;
        expect(fk, startsWith('FOREIGN KEY (user_id) REFERENCES "user"(id)'));
        expect(fk, contains('ON UPDATE CASCADE'));
        expect(fk, contains('ON DELETE CASCADE'));

        final index = await rows('''
SELECT indexdef FROM pg_indexes
WHERE schemaname = 'public' AND tablename = 'user_saved_fact'
  AND indexname = 'user_saved_fact_user_idx'
''');
        expect(
          index.single['indexdef'],
          contains('(user_id, created_at DESC)'),
        );
      },
    );

    test('accepts a row whose fact id matches no fact', () async {
      await writer.execute(
        Sql.named(
          'INSERT INTO public.user_saved_fact (user_id, fact_card_id) '
          "VALUES (@u, 'Ffsave_nowhere')",
        ),
        parameters: {'u': _other},
      );
      expect(await savedRows(userId: _other, factId: 'Ffsave_nowhere'), 1);
      await writer.execute(
        Sql.named(
          'DELETE FROM public.user_saved_fact WHERE user_id = @u',
        ),
        parameters: {'u': _other},
      );
    });
  });

  group('Save and Unsave over the V2 GraphQL endpoint', () {
    test(
      'the server exposes BeaconFactCardSave(beaconId, factCardId) and '
      'BeaconFactCardUnsave(factCardId), all arguments non-null strings',
      () async {
        final fields = await mutationFields();
        Map<String, String> argsOf(String name) {
          final field = fields[name] as Map<String, dynamic>?;
          expect(field, isNotNull, reason: 'the V2 mutation $name must exist');
          return {
            for (final a
                in (field!['args'] as List<dynamic>)
                    .cast<Map<String, dynamic>>())
              a['name']! as String: () {
                final type = a['type'] as Map<String, dynamic>;
                final inner = type['ofType'] as Map<String, dynamic>?;
                return type['kind'] == 'NON_NULL'
                    ? '${inner?['name']}!'
                    : '${type['name']}';
              }(),
          };
        }

        expect(argsOf('BeaconFactCardSave'), {
          'beaconId': 'String!',
          'factCardId': 'String!',
        });
        expect(argsOf('BeaconFactCardUnsave'), {'factCardId': 'String!'});
      },
    );

    test('a saved fact is listed with savedByMe true for the saver and '
        'false for everyone else', () async {
      expectOk(await save(_b, _fShown, as: _member));

      final mine = await savedByMe(_b, viewer: _member);
      expect(mine[_fShown], true);
      expect(mine[_fControl], false);

      for (final viewer in [_other, _reader]) {
        final theirs = await savedByMe(_b, viewer: viewer);
        expect(theirs[_fShown], false, reason: 'viewer $viewer');
        expect(theirs[_fControl], false, reason: 'viewer $viewer');
      }
    });

    test('saving the same fact twice keeps one row', () async {
      expectOk(await save(_b, _fTwice, as: _member));
      expectOk(await save(_b, _fTwice, as: _member));
      expect(await savedRows(userId: _member, factId: _fTwice), 1);
      expect((await savedByMe(_b, viewer: _member))[_fTwice], true);
    });

    test('unsaving deletes the row, the list says not saved, and unsaving '
        'again is not an error', () async {
      expectOk(await save(_b, _fUnsave, as: _member));
      expect(await savedRows(userId: _member, factId: _fUnsave), 1);

      expectOk(await unsave(_fUnsave, as: _member));
      expect(await savedRows(userId: _member, factId: _fUnsave), 0);
      expect((await savedByMe(_b, viewer: _member))[_fUnsave], false);

      expectOk(await unsave(_fUnsave, as: _member));
      expect(await savedRows(userId: _member, factId: _fUnsave), 0);
    });

    test('unsaving a fact never saved, or a fact id that matches nothing, '
        'succeeds and changes no rows', () async {
      expectOk(await save(_b, _fShown, as: _other));
      final before = await savedRows();
      expectOk(await unsave(_fControl, as: _other));
      expectOk(await unsave('Ffsave_dangling', as: _other));
      expect(await savedRows(), before);
      expect(await savedRows(userId: _other, factId: _fShown), 1);
    });

    test('a saved fact that was later removed, or whose Request the user can '
        'no longer read, can still be unsaved', () async {
      expectOk(await save(_b, _fLaterRemoved, as: _member));
      expectOk(await save(_h, _fInH, as: _member));
      expect(await savedRows(userId: _member, factId: _fLaterRemoved), 1);
      expect(await savedRows(userId: _member, factId: _fInH), 1);

      await writer.execute(
        Sql.named(
          'UPDATE public.beacon_fact_card SET status = @removed WHERE id = @f',
        ),
        parameters: {
          'removed': BeaconFactCardStatusBits.removed,
          'f': _fLaterRemoved,
        },
      );
      await writer.execute(
        Sql.named(
          'DELETE FROM public.beacon_participant '
          'WHERE beacon_id = @h AND user_id = @u',
        ),
        parameters: {'h': _h, 'u': _member},
      );
      // Now unavailable: saving it again is refused ...
      expectErrorCode(
        await save(_b, _fLaterRemoved, as: _member),
        _unavailableCode,
      );
      expectErrorCode(await save(_h, _fInH, as: _member), _unavailableCode);

      // ... but the user can still remove their own rows.
      expectOk(await unsave(_fLaterRemoved, as: _member));
      expectOk(await unsave(_fInH, as: _member));
      expect(await savedRows(userId: _member, factId: _fLaterRemoved), 0);
      expect(await savedRows(userId: _member, factId: _fInH), 0);
    });

    test('a Request reader without the room saves a request-visible fact but '
        'not a discussion-only one', () async {
      expect((await savedByMe(_b, viewer: _reader))[_fReader], false);
      expectOk(await save(_b, _fReader, as: _reader));
      expect(await savedRows(userId: _reader, factId: _fReader), 1);
      expect((await savedByMe(_b, viewer: _reader))[_fReader], true);

      expectErrorCode(
        await save(_b, _fRoomOnly, as: _reader),
        _unavailableCode,
      );
      expect(await savedRows(userId: _reader, factId: _fRoomOnly), 0);
    });

    test('saving an unreadable, removed or wrong-Request fact is the '
        'factCopySourceUnavailable error and writes nothing', () async {
      expect(_unavailableCode, 1352);
      for (final (beaconId, factId, viewer) in [
        (_c, _fPrivate, _reader), // Request the reader cannot see
        (_b, _fRemoved, _member), // removed fact
        (_c, _fControl, _member), // fact lives in B, not C
        (_b, 'Ffsave_missing', _member), // no such fact
      ]) {
        final body = await save(beaconId, factId, as: viewer);
        expectErrorCode(body, _unavailableCode);
        expect(
          await savedRows(userId: viewer, factId: factId),
          0,
          reason: '$viewer saving $factId in $beaconId',
        );
      }
    });

    test('the 200th save succeeds; the 201st is the saved-fact limit error; '
        're-saving at the cap is not an error', () async {
      await writer.execute(
        Sql.named('''
INSERT INTO public.user_saved_fact (user_id, fact_card_id)
SELECT @u, 'Ffsave_pad' || s FROM generate_series(1, @n) AS s
'''),
        parameters: {'u': _hoarder, 'n': _saveCap - 1},
      );
      expect(await savedRows(userId: _hoarder), _saveCap - 1);

      expectOk(await save(_b, _fCapA, as: _hoarder));
      expect(await savedRows(userId: _hoarder), _saveCap);

      final over = await save(_b, _fCapB, as: _hoarder);
      expectErrorCode(over, _savedFactLimitCode);
      expect(await savedRows(userId: _hoarder), _saveCap);
      expect(await savedRows(userId: _hoarder, factId: _fCapB), 0);

      expectOk(await save(_b, _fCapA, as: _hoarder));
      expect(await savedRows(userId: _hoarder), _saveCap);
    });

    test('deleting a user removes their saved rows', () async {
      expectOk(await save(_b, _fLeaver, as: _leaver));
      expect(await savedRows(userId: _leaver), 1);

      await writer.execute(
        Sql.named('DELETE FROM public.beacon_participant WHERE user_id = @u'),
        parameters: {'u': _leaver},
      );
      await writer.execute(
        Sql.named('DELETE FROM public."user" WHERE id = @u'),
        parameters: {'u': _leaver},
      );
      expect(await savedRows(userId: _leaver), 0);
    });

    test("deleting the fact's Request leaves the saved row in place", () async {
      expectOk(await save(_g, _fInG, as: _member));
      expect(await savedRows(userId: _member, factId: _fInG), 1);

      await writer.execute(
        Sql.named('DELETE FROM public.beacon WHERE id = @g'),
        parameters: {'g': _g},
      );
      expect(
        await rows(
          'SELECT 1 FROM public.beacon_fact_card WHERE id = @f',
          {'f': _fInG},
        ),
        isEmpty,
      );
      expect(await savedRows(userId: _member, factId: _fInG), 1);
    });
  });
}

Future<void> _seed(Connection w) async {
  Future<void> run(String sql, [Map<String, Object?>? p]) async {
    await w.execute(Sql.named(sql), parameters: p ?? {});
  }

  for (final (i, u) in [
    _owner,
    _member,
    _reader,
    _other,
    _leaver,
    _hoarder,
  ].indexed) {
    await run(
      'INSERT INTO public."user" (id, display_name, public_key) '
      'VALUES (@id, @n, @k)',
      {'id': u, 'n': 'User$i', 'k': pgTestPublicKey('fsave', i + 1)},
    );
  }
  for (final (id, discoverable) in [
    (_b, true),
    (_c, false),
    (_g, true),
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
  for (final (beaconId, userId) in [
    (_b, _member),
    (_b, _other),
    (_b, _leaver),
    (_b, _hoarder),
    (_c, _member),
    (_g, _member),
    (_h, _member),
  ]) {
    await run(
      '''
INSERT INTO public.beacon_participant
  (id, beacon_id, user_id, role, status, room_access)
VALUES (@id, @b, @u, 0, 0, 3)
''',
      {'id': 'Pfsave${p++}', 'b': beaconId, 'u': userId},
    );
  }
  // The reader sees B as a Request (forwarded) but is in no room.
  await run(
    'INSERT INTO public.beacon_forward_edge '
    '(beacon_id, sender_id, recipient_id) VALUES (@b, @o, @r)',
    {'b': _b, 'o': _owner, 'r': _reader},
  );

  Future<void> fact(
    String id,
    String beaconId, {
    int status = BeaconFactCardStatusBits.active,
    int visibility = BeaconFactCardVisibilityBits.public,
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
        'vis': visibility,
        'o': _owner,
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
        'o': _owner,
        'kind': BeaconFactCardRevisionKindBits.created,
        't0': _t0,
      },
    );
  }

  for (final id in [
    _fShown,
    _fControl,
    _fTwice,
    _fUnsave,
    _fReader,
    _fLeaver,
    _fCapA,
    _fCapB,
  ]) {
    await fact(id, _b);
  }
  await fact(_fRoomOnly, _b, visibility: BeaconFactCardVisibilityBits.room);
  await fact(_fRemoved, _b, status: BeaconFactCardStatusBits.removed);
  await fact(_fPrivate, _c);
  await fact(_fInG, _g);
  await fact(_fLaterRemoved, _b);
  await fact(_fInH, _h);
}
