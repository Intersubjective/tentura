@Tags(['pg', 'multi-connection'])
@Timeout(Duration(minutes: 2))
library;

import 'dart:convert';

import 'package:drift/drift.dart' show driftRuntimeOptions;
import 'package:injectable/injectable.dart' show Environment;
import 'package:postgres/postgres.dart';
import 'package:shelf_plus/shelf_plus.dart' show Handler, Request;
import 'package:test/test.dart';

import 'package:tentura_root/domain/entity/beacon_status.dart';
import 'package:tentura_server/api/root_router.dart';
import 'package:tentura_server/app/di.dart';
import 'package:tentura_server/domain/entity/beacon_kind.dart';
import 'package:tentura_server/domain/policy/beacon_forward_policy.dart';
import 'package:tentura_server/domain/port/beacon_repository_port.dart';
import 'package:tentura_server/domain/use_case/auth_case.dart';
import 'package:tentura_server/env.dart';
import 'package:tentura_server/utils/id.dart';

import '../../../support/disposable_pg_target.dart';
import '../../../support/pg_test_public_keys.dart';
import '../../../support/session_database_di_harness.dart';

const _owner = 'U8f3100000001';
const _author = 'U8f3100000002';
const _joiner = 'U8f3100000003';
const _origin = 'http://127.0.0.1:2080';
const _note = 'for you';
const _unauthorized = '1102';
const _forwardField = 'beaconForwardToPhantom';

Future<void> main() async {
  final target = DisposablePgTarget.fromNamedEnvironment(
    envVarName: 'TENTURA_REQUEST_FORWARD_PERSON_INVITE_TEST_DB',
    defaultNamePrefix: 'tentura_test_forward_person_invite',
  );
  final skip = await pgSkipReason(target);

  group('Forwarding a Request to someone not on Tentura yet', () {
    late _Fixtures fixtures;
    late _RequestApi api;
    late String person;

    setUpAll(() async {
      final previousWarning =
          driftRuntimeOptions.dontWarnAboutMultipleDatabases;
      driftRuntimeOptions.dontWarnAboutMultipleDatabases = true;
      addTearDown(() {
        driftRuntimeOptions.dontWarnAboutMultipleDatabases = previousWarning;
      });
      final session = await setUpDisposablePgWriter(target: target);
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
      api = _RequestApi((await getIt.getAsync<RootRouter>()).routeHandler());
    });

    setUp(() async {
      await fixtures.reset();
      final reply = await api.post('mutation { phantomCreate(name: "Avery") }');
      person = _field(reply, 'phantomCreate')! as String;
    });

    Future<void> expectRefused(
      String request, {
      String actor = _owner,
      String? code,
    }) async {
      final invitesBefore = await fixtures.invitations();
      final reply = await api.forward(request, person, actor: actor);

      expect(await fixtures.pendingForwards(), isEmpty);
      expect(await fixtures.invitations(), invitesBefore);
      expect((reply['data'] as Map<String, Object?>?)?[_forwardField], isNull);
      // Require a coded domain refusal.
      expect(reply['errors'], [
        containsPair(
          'extensions',
          containsPair(
            'code',
            code ?? allOf(isA<String>(), isNot('1000')),
          ),
        ),
      ], reason: jsonEncode(reply));
    }

    test(
      'an author gets an invite link and records their note as pending',
      () async {
        final request = await fixtures.request();
        expect(await fixtures.canRead(request), isTrue);

        final link = _field(await api.forward(request, person), _forwardField);

        final code = await fixtures.onlyLiveInviteCode(person);
        expect(link, _link(code, request));
        expect(await fixtures.pendingForwards(), [
          [_owner, person, request, _note, 'pending', null],
        ]);
      },
    );

    test(
      'two different Requests share the newly created live invite',
      () async {
        final firstRequest = await fixtures.request();
        final secondRequest = await fixtures.request();
        expect(await fixtures.invitations(), isEmpty);

        final first = _field(
          await api.forward(firstRequest, person),
          _forwardField,
        );
        final code = await fixtures.onlyLiveInviteCode(person);
        expect(first, _link(code, firstRequest));

        final second = _field(
          await api.forward(secondRequest, person),
          _forwardField,
        );

        expect(second, _link(code, secondRequest));
        expect(await fixtures.onlyLiveInviteCode(person), code);
        expect(
          await fixtures.pendingForwards(),
          unorderedEquals([
            [_owner, person, firstRequest, _note, 'pending', null],
            [_owner, person, secondRequest, _note, 'pending', null],
          ]),
        );
      },
    );

    test(
      'an existing live invite keeps its code and gains no duplicate',
      () async {
        final request = await fixtures.request();
        final code = await api.ensureInvite(person);
        final invitesBefore = await fixtures.invitations();

        final link = _field(await api.forward(request, person), _forwardField);

        expect(link, _link(code, request));
        expect(await fixtures.invitations(), invitesBefore);
        expect(await fixtures.onlyLiveInviteCode(person), code);
        expect(await fixtures.pendingForwards(), [
          [_owner, person, request, _note, 'pending', null],
        ]);
      },
    );

    test(
      'retrying a pending forward returns the same link and keeps one row',
      () async {
        final request = await fixtures.request();

        final first = _field(await api.forward(request, person), _forwardField);
        final recorded = await fixtures.forwardIds();
        expect(recorded, hasLength(1));
        final second = _field(
          await api.forward(request, person),
          _forwardField,
        );

        final code = await fixtures.onlyLiveInviteCode(person);
        expect(first, _link(code, request));
        expect(second, first);
        expect(await fixtures.forwardIds(), recorded);
        expect(await fixtures.pendingForwards(), [
          [_owner, person, request, _note, 'pending', null],
        ]);
      },
    );

    test(
      'forwarding a received Request records the active inbound edge',
      () async {
        final request = await fixtures.request(author: _author);
        final inbound = await fixtures.edge(request, _author, _owner);
        expect(await fixtures.canRead(request), isTrue);

        final link = _field(await api.forward(request, person), _forwardField);

        final code = await fixtures.onlyLiveInviteCode(person);
        expect(link, _link(code, request));
        expect(await fixtures.pendingForwards(), [
          [_owner, person, request, _note, 'pending', inbound],
        ]);
      },
    );

    test(
      'an author can forward their Request after an inbound forward and records no parent',
      () async {
        final request = await fixtures.request();
        final outbound = await fixtures.edge(request, _owner, _author);
        await fixtures.edge(request, _author, _owner, parent: outbound);

        final link = _field(await api.forward(request, person), _forwardField);

        final code = await fixtures.onlyLiveInviteCode(person);
        expect(link, _link(code, request));
        expect(await fixtures.pendingForwards(), [
          [_owner, person, request, _note, 'pending', null],
        ]);
      },
    );

    test('an unreadable Request cannot be forwarded', () async {
      final request = await fixtures.request(author: _author);
      expect(await fixtures.canRead(request), isFalse);

      await expectRefused(request, code: _unauthorized);
    });

    test('a closed Request cannot be forwarded even by its author', () async {
      final request = await fixtures.request(status: BeaconStatus.closed);
      expect(await fixtures.canRead(request), isTrue);

      await expectRefused(request);
    });

    test(
      'a non-author cannot forward a readable open Request with author-only forwarding',
      () async {
        final request = await fixtures.requestWithAuthorOnlyForwarding(
          author: _author,
        );
        await fixtures.edge(request, _author, _owner);
        expect(await fixtures.canRead(request), isTrue);
        expect(await fixtures.invitations(), isEmpty);
        final beacon = await getIt<BeaconRepositoryPort>().getBeaconById(
          beaconId: request,
        );
        expect(beacon.kind, BeaconKind.request);
        expect(beacon.status, BeaconStatus.open);
        expect(
          BeaconForwardPolicy.canForward(beacon: beacon, senderId: _author),
          isTrue,
        );
        expect(
          BeaconForwardPolicy.canForward(beacon: beacon, senderId: _owner),
          isFalse,
        );

        await expectRefused(request, code: _unauthorized);
      },
    );

    test(
      'an author can forward their open Request with author-only forwarding',
      () async {
        final request = await fixtures.requestWithAuthorOnlyForwarding(
          author: _owner,
        );
        expect(await fixtures.canRead(request), isTrue);

        final link = _field(await api.forward(request, person), _forwardField);

        final code = await fixtures.onlyLiveInviteCode(person);
        expect(link, _link(code, request));
        expect(await fixtures.pendingForwards(), [
          [_owner, person, request, _note, 'pending', null],
        ]);
      },
    );

    for (final (description, blocker, blocked) in [
      ('the owner blocks the author', _owner, _author),
      ('the author blocks the owner', _author, _owner),
    ]) {
      test(
        'a received Request cannot be forwarded when $description',
        () async {
          final request = await fixtures.request(author: _author);
          await fixtures.edge(request, _author, _owner);
          expect(await fixtures.canRead(request), isTrue);
          await fixtures.block(blocker, blocked);
          expect(await fixtures.canRead(request), isFalse);

          await expectRefused(request);
        },
      );
    }

    test(
      'another account cannot forward to a person on the owner’s map',
      () async {
        final request = await fixtures.request(author: _author);
        expect(await fixtures.canRead(request, viewer: _author), isTrue);

        await expectRefused(request, actor: _author);
      },
    );

    test('a removed person cannot receive a pending forward', () async {
      final request = await fixtures.request();
      final reply = await api.post(
        r'mutation RemovePerson($id: String!) { phantomDelete(id: $id) }',
        variables: {'id': person},
      );
      expect(_field(reply, 'phantomDelete'), isTrue);

      await expectRefused(request);
    });

    test(
      'a person already linked to an account cannot receive a pending forward',
      () async {
        final request = await fixtures.request();
        await fixtures.markMerged(person);

        await expectRefused(request);
      },
    );

    test(
      'a person waiting for an account link cannot receive a pending forward',
      () async {
        final request = await fixtures.request();
        final code = await api.ensureInvite(person);
        await fixtures.queueMerge(person, code);

        await expectRefused(request);
      },
    );
  }, skip: skip);
}

String _link(String code, String request) => '/invite/$code?r=$request';

Object? _field(Map<String, Object?> reply, String field) {
  expect(reply['errors'], isNull, reason: jsonEncode(reply));
  return (reply['data']! as Map<String, Object?>)[field];
}

final class _RequestApi {
  const _RequestApi(this._handler);

  final Handler _handler;

  Future<Map<String, Object?>> forward(
    String request,
    String person, {
    String actor = _owner,
  }) => post(
    r'mutation ForwardToPerson($beaconId: String!, $phantomId: String!, $note: String!) { '
    '$_forwardField(beaconId: \$beaconId, phantomId: \$phantomId, note: \$note) }',
    variables: {'beaconId': request, 'phantomId': person, 'note': _note},
    actor: actor,
  );

  Future<String> ensureInvite(String person) async =>
      _field(
            await post(
              r'mutation EnsureInvite($id: String!) { phantomInviteEnsure(id: $id) }',
              variables: {'id': person},
            ),
            'phantomInviteEnsure',
          )!
          as String;

  Future<Map<String, Object?>> post(
    String query, {
    Map<String, Object?> variables = const {},
    String actor = _owner,
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

  Future<Result> sql(
    String statement, [
    Map<String, Object?> parameters = const {},
  ]) => _writer.execute(Sql.named(statement), parameters: parameters);

  Future<void> reset() async {
    await sql('TRUNCATE TABLE public."user" CASCADE');
    for (final (index, user) in [_owner, _author, _joiner].indexed) {
      await sql(
        '''
INSERT INTO public."user" (id, display_name, public_key)
VALUES (@user, @user, @key)
''',
        {'user': user, 'key': pgTestPublicKey('forward-person', index + 1)},
      );
    }
  }

  Future<String> request({
    String author = _owner,
    BeaconStatus status = BeaconStatus.open,
    BeaconForwardPolicyValue forwardPolicy = BeaconForwardPolicyValue.open,
  }) async {
    final rows = await sql(
      '''
INSERT INTO public.beacon
  (user_id, title, description, status, forward_policy, is_discoverable, published_at)
VALUES (@author, 'Help with the garden', '', @status, @policy, false, now())
RETURNING id
''',
      {
        'author': author,
        'status': status.smallintValue,
        'policy': forwardPolicy.value,
      },
    );
    return rows.single.single! as String;
  }

  Future<String> requestWithAuthorOnlyForwarding({
    required String author,
  }) async {
    const constraint = 'beacon_forward_policy_ck';
    const table = 'public.beacon';
    final definition =
        (await sql('''
SELECT pg_get_constraintdef(oid) FROM pg_constraint
WHERE conrelid = '$table'::regclass AND conname = '$constraint'
''')).single.single!
            as String;
    // PostgreSQL reserves author-only forwarding for Posts. Relax the check
    // in this disposable database so the real Request path sees that policy.
    await sql('ALTER TABLE $table DROP CONSTRAINT $constraint');
    String? requestId;
    addTearDown(() async {
      if (requestId != null) {
        await sql('DELETE FROM $table WHERE id = @id', {'id': requestId});
      }
      await sql('ALTER TABLE $table ADD CONSTRAINT $constraint $definition');
    });
    // The closed enum value still permits the author to forward an open item.
    final id = await request(
      author: author,
      forwardPolicy: BeaconForwardPolicyValue.closed,
    );
    requestId = id;
    return id;
  }

  Future<bool> canRead(String request, {String viewer = _owner}) async {
    final rows = await sql(
      'SELECT public.beacon_can_read_content(@request, @viewer)',
      {'request': request, 'viewer': viewer},
    );
    return rows.single.single! as bool;
  }

  Future<String> edge(
    String request,
    String sender,
    String recipient, {
    String? parent,
  }) async {
    final rows = await sql(
      '''
INSERT INTO public.beacon_forward_edge
  (beacon_id, sender_id, recipient_id, parent_edge_id)
VALUES (@request, @sender, @recipient, @parent) RETURNING id
''',
      {
        'request': request,
        'sender': sender,
        'recipient': recipient,
        'parent': parent,
      },
    );
    return rows.single.single! as String;
  }

  Future<void> block(String blocker, String blocked) => sql(
    '''
INSERT INTO public.user_block (blocker_id, blocked_id, origin_id)
VALUES (@blocker, @blocked, @blocked)
''',
    {'blocker': blocker, 'blocked': blocked},
  );

  Future<void> markMerged(String person) async {
    final merge = generateId('PM');
    final parameters = {
      'person': person,
      'owner': _owner,
      'joiner': _joiner,
      'merge': merge,
    };
    await _writer.executeWithOwnerScopes(
      [_owner],
      Sql.named('''
INSERT INTO public.phantom_merge (id, phantom_id, owner_id, user_id, origin, undo)
VALUES (@merge, @person, @owner, @joiner, 2, '{}'::jsonb)
'''),
      parameters: parameters,
    );
    await _writer.executeWithOwnerScopes(
      [_owner],
      Sql.named('''
UPDATE public.phantom
SET merged_at = now(), merged_user_id = @joiner, merge_origin = 2, current_merge_id = @merge
WHERE id = @person AND owner_id = @owner
'''),
      parameters: parameters,
    );
  }

  Future<void> queueMerge(String person, String code) async {
    final claimed = await sql(
      '''
UPDATE public.invitation
SET invited_id = @joiner, accepted_at = now(), invite_origin = 'existing_account'
WHERE id = @code AND phantom_id = @person AND invited_id IS NULL
RETURNING id
''',
      {'code': code, 'person': person, 'joiner': _joiner},
    );
    expect(claimed.single.single, code);
    await sql(
      '''
INSERT INTO public.phantom_merge_job
  (id, phantom_id, owner_id, user_id, origin, invitation_id, state)
VALUES (@job, @person, @owner, @joiner, 2, @code, 'queued')
''',
      {
        'job': generateId('PM'),
        'person': person,
        'owner': _owner,
        'joiner': _joiner,
        'code': code,
      },
    );
  }

  Future<List<List<Object?>>> pendingForwards() async => [
    for (final row in await sql('''
SELECT sender_id, phantom_id, beacon_id, note, state, parent_forward_edge_id
FROM public.phantom_pending_forward
'''))
      row.toList(),
  ];

  Future<List<Map<String, Object?>>> invitations() async => [
    for (final row in await sql('SELECT * FROM public.invitation ORDER BY id'))
      row.toColumnMap(),
  ];

  Future<List<String>> forwardIds() async => [
    for (final row in await sql(
      'SELECT id FROM public.phantom_pending_forward',
    ))
      row.single! as String,
  ];

  Future<String> onlyLiveInviteCode(String person) async {
    final live = (await invitations()).where(
      (row) => row['phantom_id'] == person && row['invited_id'] == null,
    );
    expect(live, hasLength(1));
    expect(live.single['user_id'], _owner);
    return live.single['id']! as String;
  }
}
