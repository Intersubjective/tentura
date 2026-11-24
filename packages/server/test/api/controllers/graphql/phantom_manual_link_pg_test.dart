@Tags(['pg', 'multi-connection'])
library;

import 'dart:convert';

import 'package:drift/drift.dart' show driftRuntimeOptions;
import 'package:injectable/injectable.dart' show Environment;
import 'package:postgres/postgres.dart';
import 'package:shelf_plus/shelf_plus.dart' show Handler, Request;
import 'package:test/test.dart';

import 'package:tentura_server/api/root_router.dart';
import 'package:tentura_server/app/di.dart';
import 'package:tentura_server/domain/use_case/auth_case.dart';
import 'package:tentura_server/env.dart';

import '../../../support/disposable_pg_target.dart';
import '../../../support/pg_test_public_keys.dart';
import '../../../support/session_database_di_harness.dart';

const _owner = 'U1a117e000021';
const _contact = 'U1a117e000022';
const _other = 'U1a117e000023';
const _person = 'PH000000000021';
const _name = 'Anna K.';
const _origin = 'http://127.0.0.1:2080';

Future<void> main() async {
  final target = DisposablePgTarget.fromNamedEnvironment(
    envVarName: 'TENTURA_PHANTOM_MANUAL_LINK_TEST_DB',
    defaultNamePrefix: 'tentura_test_phantom_manual_link',
  );
  final skip = await pgSkipReason(target);

  group('Linking a private map entry to an existing account', () {
    late _Fixtures fixtures;
    late _LinkApi api;

    setUpAll(() async {
      final previousWarning =
          driftRuntimeOptions.dontWarnAboutMultipleDatabases;
      driftRuntimeOptions.dontWarnAboutMultipleDatabases = true;
      addTearDown(() {
        driftRuntimeOptions.dontWarnAboutMultipleDatabases = previousWarning;
      });
      final session = await setUpDisposablePgWriter(
        target: target,
        createPgmer2Extension: true,
      );
      addTearDown(() => tearDownDisposablePgWriter(session: session));
      addTearDown(() async {
        getIt.skipDoubleRegistration = false;
        await getIt.reset();
      });

      fixtures = _Fixtures(session.writer);
      final db = target.databaseEnv;
      await configureSessionDatabaseTestGraph(
        Env(
          environment: Environment.dev,
          serverUri: Uri.parse(_origin),
          publicOrigin: _origin,
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
        ),
      );
      api = _LinkApi((await getIt.getAsync<RootRouter>()).routeHandler());
    });

    setUp(() => fixtures.reset());

    test(
      'records the manual merge and moves the pin under owner scope',
      () async {
        expect(await api.fieldPeerIds(), contains(_contact));
        expect(await fixtures.ownerScopeEnforcement(), 'on');
        await fixtures.seedPin();

        _expectLinked(await api.link(_contact));

        final person = (await fixtures.rows('phantom')).single;
        expect(person['merged_user_id'], _contact);
        expect(person['merge_origin'], 3);
        expect(person['merged_at'], isA<DateTime>());
        expect(await fixtures.rows('phantom_merge'), [
          allOf(
            containsPair('phantom_id', _person),
            containsPair('owner_id', _owner),
            containsPair('user_id', _contact),
            containsPair('origin', 3),
          ),
        ]);
        expect(await fixtures.rows('constellation_anchor'), [
          allOf(
            containsPair('viewer_id', _owner),
            containsPair('target_kind', 'PERSON'),
            containsPair('target_id', _contact),
            containsPair('x_units', 1.25),
            containsPair('y_units', 2.5),
          ),
        ]);
      },
    );

    test(
      'links immediately without changing trust or queuing a merge',
      () async {
        final votes = await fixtures.rows(
          'vote_user',
          orderBy: 'subject, object',
        );
        expect(votes, [
          allOf(
            containsPair('subject', _owner),
            containsPair('object', _contact),
          ),
        ]);
        expect(await fixtures.rows('phantom_merge_job'), isEmpty);

        _expectLinked(await api.link(_contact));

        expect(
          (await fixtures.rows('phantom')).single['merged_user_id'],
          _contact,
        );
        expect(
          await fixtures.rows('vote_user', orderBy: 'subject, object'),
          votes,
        );
        expect(await fixtures.rows('phantom_merge_job'), isEmpty);
      },
    );

    test(
      'removes the live invite and rejects acceptance of its code',
      () async {
        final code = await fixtures.seedInvite();
        expect(await api.previewStatus(code), 'available');

        _expectLinked(await api.link(_contact));

        expect(await fixtures.rows('invitation'), isEmpty);
        expect(await api.previewStatus(code), 'invalid');
        final reply = await api.acceptInvite(code);
        expect(reply['errors'], [
          containsPair('extensions', containsPair('code', '1002')),
        ], reason: jsonEncode(reply));
      },
    );

    test(
      'refuses an account outside the Field and preserves the invite and pin',
      () async {
        expect(
          await api.fieldPeerIds(),
          allOf(contains(_contact), isNot(contains(_other))),
        );
        await fixtures.seedInvite();
        await fixtures.seedPin();
        final before = await fixtures.snapshot();
        expect(before['phantom']!.single['merged_user_id'], isNull);
        expect(before['phantom_merge'], isEmpty);

        final reply = await api.link(_other);

        expect(await fixtures.snapshot(), before);
        _expectLinkRefused(reply);
      },
    );

    test(
      'reports that the invitee is joining and preserves the queued merge',
      () async {
        final code = await fixtures.seedInvite(claimedBy: _other);
        await fixtures.queueMerge(code);
        final before = await fixtures.snapshot();
        expect(before['invitation']!.single['invited_id'], _other);
        expect(before['phantom_merge_job']!.single['state'], 'queued');

        final reply = await api.link(_contact);

        expect(await fixtures.snapshot(), before);
        _expectLinkRefused(reply);
        final errors = reply['errors']! as List<Object?>;
        expect(
          errors.single,
          containsPair(
            'message',
            matches(
              RegExp('joining[ _-]*right[ _-]*now', caseSensitive: false),
            ),
          ),
        );
      },
    );

    test(
      'returns not-found to another account even when it can see the contact',
      () async {
        await fixtures.trustContact(_other);
        expect(await api.fieldPeerIds(actor: _other), contains(_contact));
        await fixtures.seedInvite();
        final before = await fixtures.snapshot();

        final reply = await api.link(_contact, actor: _other);

        expect(await fixtures.snapshot(), before);
        _expectLinkRefused(reply, code: '1002');
      },
    );

    test(
      'refuses to link an already merged entry and preserves its merge history',
      () async {
        await fixtures.seedPreviousMerge();
        final before = await fixtures.snapshot();
        expect(before['phantom']!.single['merged_user_id'], _other);
        expect(before['phantom_merge'], hasLength(1));

        final reply = await api.link(_contact);

        expect(await fixtures.snapshot(), before);
        _expectLinkRefused(reply);
      },
    );

    test('refuses to link a removed entry without creating a merge', () async {
      await fixtures.removePerson();
      final before = await fixtures.snapshot();
      expect(before['phantom'], isEmpty);
      expect(before['phantom_merge'], isEmpty);

      final reply = await api.link(_contact);

      expect(await fixtures.snapshot(), before);
      _expectLinkRefused(reply);
    });

    test(
      'refuses to link the entry to its owner and leaves it unmerged',
      () async {
        final before = await fixtures.snapshot();
        expect(before['phantom']!.single['merged_user_id'], isNull);

        final reply = await api.link(_owner);

        expect(await fixtures.snapshot(), before);
        _expectLinkRefused(reply);
      },
    );
  }, skip: skip);
}

void _expectLinked(Map<String, Object?> reply) {
  expect(reply['errors'], isNull, reason: jsonEncode(reply));
  expect(reply['data'], {'phantomLink': true});
}

void _expectLinkRefused(Map<String, Object?> reply, {String? code}) {
  // An undefined mutation or an internal error cannot stand in for a refusal.
  expect(reply['errors'], [
    containsPair(
      'extensions',
      containsPair('code', code ?? allOf(isA<String>(), isNot('1000'))),
    ),
  ], reason: jsonEncode(reply));
  expect((reply['data'] as Map<String, Object?>?)?['phantomLink'], isNull);
}

final class _LinkApi {
  const _LinkApi(this._handler);

  final Handler _handler;

  Future<Map<String, Object?>> link(String userId, {String actor = _owner}) =>
      _graphql(
        r'mutation Link($phantomId: String!, $userId: String!) {'
        r' phantomLink(phantomId: $phantomId, userId: $userId) }',
        {'phantomId': _person, 'userId': userId},
        actor: actor,
      );

  Future<Map<String, Object?>> acceptInvite(String code) => _graphql(
    r'mutation Accept($id: String!) { invitationAccept(id: $id) }',
    {'id': code},
    actor: _other,
  );

  Future<Iterable<Object?>> fieldPeerIds({String actor = _owner}) async {
    final reply = await _graphql(
      '{ constellationField { peers { id } } }',
      const {},
      actor: actor,
    );
    expect(reply['errors'], isNull, reason: jsonEncode(reply));
    final data = reply['data']! as Map<String, Object?>;
    final field = data['constellationField']! as Map<String, Object?>;
    return (field['peers']! as List<Object?>).cast<Map<String, Object?>>().map(
      (peer) => peer['id'],
    );
  }

  Future<Object?> previewStatus(String code) async {
    final response = await _handler(
      Request('GET', Uri.parse('$_origin/api/v2/invite/$code/preview')),
    );
    final body = await response.readAsString();
    expect(response.statusCode, 200, reason: body);
    return (jsonDecode(body) as Map<String, Object?>)['codeStatus'];
  }

  Future<Map<String, Object?>> _graphql(
    String query,
    Map<String, Object?> variables, {
    required String actor,
  }) async {
    final token = getIt<AuthCase>().issueAccessToken(actor).rawToken;
    final response = await _handler(
      Request(
        'POST',
        Uri.parse('$_origin/api/v2/graphql'),
        headers: {
          'content-type': 'application/json',
          'authorization': 'Bearer $token',
        },
        body: jsonEncode({'query': query, 'variables': variables}),
      ),
    );
    final body = await response.readAsString();
    expect(response.statusCode, 200, reason: body);
    return jsonDecode(body) as Map<String, Object?>;
  }
}

final class _Fixtures {
  const _Fixtures(this._writer);

  final Connection _writer;

  Future<void> reset() async {
    await _writer.execute('TRUNCATE TABLE public."user" CASCADE');
    for (final (index, id) in [_owner, _contact, _other].indexed) {
      await _writer.execute(
        Sql.named('''
INSERT INTO public."user" (id, display_name, public_key)
VALUES (@id, @id, @key)
'''),
        parameters: {
          'id': id,
          'key': pgTestPublicKey('manual-link', index + 1),
        },
      );
    }
    await _scoped(
      '''
INSERT INTO public.phantom (id, owner_id, display_name)
VALUES (@person, @owner, @name)
''',
      {'person': _person, 'owner': _owner, 'name': _name},
    );
    await trustContact(_owner);
  }

  Future<void> trustContact(String viewer) async {
    await _writer.execute(
      Sql.named('''
INSERT INTO public.vote_user (subject, object, amount)
VALUES (@viewer, @contact, 1)
'''),
      parameters: {'viewer': viewer, 'contact': _contact},
    );
  }

  Future<Object?> ownerScopeEnforcement() async =>
      (await _writer.execute('SHOW tentura.owner_scope_enforce')).single.single;

  Future<void> seedPin() async {
    await _scoped(
      '''
INSERT INTO public.constellation_anchor_cursor (viewer_id) VALUES (@owner)
''',
      {'owner': _owner},
    );
    await _scoped(
      '''
INSERT INTO public.constellation_anchor
  (id, viewer_id, phantom_id, x_units, y_units, coordinate_space_version, revision, placed_at)
VALUES ('CA000000000021', @owner, @person, 1.25, 2.5, 1, 0, 'epoch')
''',
      {'owner': _owner, 'person': _person},
    );
  }

  Future<String> seedInvite({String? claimedBy}) async {
    final result = await _scoped(
      '''
INSERT INTO public.invitation
  (user_id, phantom_id, addressee_name, invited_id, accepted_at, invite_origin)
VALUES (@owner, @person, @name, @claimant::text,
        CASE WHEN @claimant IS NOT NULL THEN now() END,
        CASE WHEN @claimant IS NOT NULL THEN 'existing_account' END)
RETURNING id
''',
      {
        'owner': _owner,
        'person': _person,
        'name': _name,
        'claimant': claimedBy,
      },
    );
    return result.single.single! as String;
  }

  Future<void> queueMerge(String code) async {
    await _writer.execute(
      Sql.named('''
INSERT INTO public.phantom_merge_job
  (id, phantom_id, owner_id, user_id, origin, invitation_id, state)
VALUES ('PJ000000000021', @person, @owner, @user, 2, @code, 'queued')
'''),
      parameters: {
        'person': _person,
        'owner': _owner,
        'user': _other,
        'code': code,
      },
    );
  }

  Future<void> seedPreviousMerge() async {
    const merge = 'PM000000000021';
    await _scoped(
      '''
INSERT INTO public.phantom_merge (id, phantom_id, owner_id, user_id, origin, undo)
VALUES (@merge, @person, @owner, @user, 2, '{}'::jsonb)
''',
      {'merge': merge, 'person': _person, 'owner': _owner, 'user': _other},
    );
    await _scoped(
      '''
UPDATE public.phantom
SET merged_user_id = @user, merged_at = now(), merge_origin = 2, current_merge_id = @merge
WHERE id = @person
''',
      {'merge': merge, 'person': _person, 'user': _other},
    );
  }

  Future<void> removePerson() async {
    await _scoped('DELETE FROM public.phantom WHERE id = @person', {
      'person': _person,
    });
  }

  Future<Result> _scoped(String sql, Map<String, Object?> parameters) => _writer
      .executeWithOwnerScopes([_owner], Sql.named(sql), parameters: parameters);

  Future<List<Map<String, Object?>>> rows(
    String table, {
    String orderBy = 'id',
  }) async => [
    for (final row in await _writer.execute(
      'SELECT * FROM public.$table ORDER BY $orderBy',
    ))
      row.toColumnMap(),
  ];

  Future<Map<String, List<Map<String, Object?>>>> snapshot() async => {
    for (final table in [
      'phantom',
      'invitation',
      'constellation_anchor',
      'phantom_merge',
      'phantom_merge_job',
    ])
      table: await rows(table),
    'vote_user': await rows('vote_user', orderBy: 'subject, object'),
  };
}
