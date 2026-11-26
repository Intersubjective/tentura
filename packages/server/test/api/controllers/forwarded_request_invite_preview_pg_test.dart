@Tags(['pg'])
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
import 'package:tentura_server/env.dart';
import 'package:tentura_server/utils/id.dart';

import '../../support/disposable_pg_target.dart';
import '../../support/pg_test_public_keys.dart';
import '../../support/session_database_di_harness.dart';

const _origin = 'http://127.0.0.1:2080';
const _sender = 'Uforwardprev01';
const _otherUser = 'Uforwardprev02';
const _inviterName = 'Morgan';
const _title = 'Help with the garden';
const _description = 'We need an extra pair of hands on Saturday.';
const _postBody = 'The garden is open on Sunday.';

Future<void> main() async {
  final target = DisposablePgTarget.fromNamedEnvironment(
    envVarName: 'TENTURA_FORWARDED_REQUEST_INVITE_PREVIEW_TEST_DB',
    defaultNamePrefix: 'tentura_test_forwarded_invite_preview',
  );
  final skip = await pgSkipReason(target);

  group('Request excerpts in invites for people not on Tentura yet', () {
    late _Fixtures fixtures;
    late Handler handler;
    late String person;
    late String code;
    late String requestId;

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
          maxConnectionCount: 1,
          workersCount: 1,
          printEnv: false,
          isDebugModeOn: false,
        ),
      );
      handler = (await getIt.getAsync<RootRouter>()).routeHandler();
    });

    setUp(() async {
      await fixtures.reset();
      person = await fixtures.person('Avery');
      code = await fixtures.invite(person: person);
      requestId = await fixtures.beacon();
    });

    Future<Map<String, Object?>> preview({
      String? inviteCode,
      String? requestContext,
    }) async {
      final url = Uri.parse(
        '$_origin/api/v2/invite/${inviteCode ?? code}/preview',
      );
      final response = await handler(
        Request(
          'GET',
          requestContext == null
              ? url
              : url.replace(queryParameters: {'r': requestContext}),
        ),
      );
      final body = await response.readAsString();
      expect(response.statusCode, 200, reason: body);
      return jsonDecode(body) as Map<String, Object?>;
    }

    test(
      'only the link with Request context includes the pending excerpt',
      () async {
        await fixtures.forward(person, requestId);

        final plain = await preview();
        expect(plain, containsPair('codeStatus', 'available'));
        expect(plain, containsPair('callerStatus', 'anonymous'));
        expect(
          plain,
          containsPair('inviter', containsPair('displayName', _inviterName)),
        );
        expect(plain, containsPair('phantomInvite', true));
        expect(plain, isNot(contains('beacon')));

        expect(
          await preview(requestContext: requestId),
          _requestPreview(requestId),
        );
      },
    );

    test(
      'a different or unknown Request leaves the original preview intact',
      () async {
        await fixtures.forward(person, requestId);
        final unrelated = await fixtures.beacon(title: 'Unrelated Request');
        final plain = await preview();
        expect(plain, isNot(contains('beacon')));

        expect(await preview(requestContext: unrelated), plain);
        expect(await preview(requestContext: generateId('B')), plain);
        expect(
          await preview(requestContext: requestId),
          _requestPreview(requestId),
        );
      },
    );

    for (final state in ['lapsed', 'claimed', 'delivered', 'offered']) {
      test('a $state forward has no Request excerpt', () async {
        final changedRequest = await fixtures.beacon(title: 'Help at the fair');
        await fixtures.forward(person, changedRequest, state: state);
        await fixtures.forward(person, requestId);

        final plain = await preview();
        expect(plain, isNot(contains('beacon')));
        expect(await preview(requestContext: changedRequest), plain);
        expect(
          await preview(requestContext: requestId),
          _requestPreview(requestId),
        );
      });
    }

    test(
      'a pending forward for someone else grants no Request excerpt',
      () async {
        final otherPerson = await fixtures.person('Riley');
        final otherCode = await fixtures.invite(
          person: otherPerson,
          name: 'Riley',
        );
        await fixtures.forward(otherPerson, requestId);

        final plain = await preview();
        expect(plain, isNot(contains('beacon')));
        expect(await preview(requestContext: requestId), plain);
        expect(
          await preview(inviteCode: otherCode, requestContext: requestId),
          _requestPreview(requestId),
        );
      },
    );

    test('the Request excerpt disappears when the Request closes', () async {
      await fixtures.forward(person, requestId);
      final open = await preview(requestContext: requestId);
      await fixtures.closeRequest(requestId);
      await fixtures.expectPending(person, requestId);

      final plain = await preview();
      expect(plain, isNot(contains('beacon')));
      expect(await preview(requestContext: requestId), plain);
      expect(open, _requestPreview(requestId));
    });

    test(
      'the Request excerpt disappears when the sender loses access',
      () async {
        final shared = await fixtures.beacon(author: _otherUser);
        // Stewardship grants content access without an inbound forward.
        await fixtures.addSteward(shared);
        await fixtures.forward(person, shared);
        expect(await fixtures.senderCanRead(shared), isTrue);
        final readable = await preview(requestContext: shared);

        await fixtures.removeSteward(shared);
        expect(await fixtures.senderCanRead(shared), isFalse);
        await fixtures.expectPending(person, shared);
        final plain = await preview();
        expect(plain, isNot(contains('beacon')));
        expect(await preview(requestContext: shared), plain);
        expect(readable, _requestPreview(shared));
      },
    );

    test(
      'the Request excerpt disappears after the invite is consumed',
      () async {
        await fixtures.forward(person, requestId);
        final available = await preview(requestContext: requestId);
        await fixtures.consume(code);
        await fixtures.expectPending(person, requestId);

        final plain = await preview();
        expect(plain, containsPair('codeStatus', 'consumed'));
        expect(plain, isNot(contains('beacon')));
        expect(await preview(requestContext: requestId), plain);
        expect(available, _requestPreview(requestId));
      },
    );

    for (final (kind, label) in [
      (BeaconKind.request, 'Request'),
      (BeaconKind.post, 'Post'),
    ]) {
      test(
        'an ordinary $label invite keeps its own excerpt when given Request context',
        () async {
          await fixtures.forward(person, requestId);
          final ownBeacon = await fixtures.beacon(
            kind: kind,
            title: 'Garden news',
          );
          final ordinaryCode = await fixtures.invite(beaconId: ownBeacon);

          final ordinary = await preview(inviteCode: ordinaryCode);
          expect(
            ordinary,
            containsPair(
              'beacon',
              allOf(
                containsPair('id', ownBeacon),
                containsPair('kind', kind.name),
                containsPair(
                  'description',
                  kind == BeaconKind.post ? _postBody : _description,
                ),
              ),
            ),
          );
          expect(
            await preview(inviteCode: ordinaryCode, requestContext: requestId),
            ordinary,
          );
          expect(
            await preview(requestContext: requestId),
            _requestPreview(requestId),
          );
        },
      );
    }
  }, skip: skip);
}

Matcher _requestPreview(String id) => containsPair(
  'beacon',
  allOf(
    containsPair('id', id),
    containsPair('kind', 'request'),
    containsPair('title', _title),
    containsPair('description', _description),
  ),
);

final class _Fixtures {
  const _Fixtures(this.writer);

  final Connection writer;

  Future<void> reset() async {
    await writer.execute('TRUNCATE TABLE public."user" CASCADE');
    for (final (index, id) in [_sender, _otherUser].indexed) {
      await writer.execute(
        Sql.named('''
INSERT INTO public."user" (id, display_name, public_key)
VALUES (@id, @name, @key)
'''),
        parameters: {
          'id': id,
          'name': id == _sender ? _inviterName : 'Casey',
          'key': pgTestPublicKey('forwarded-preview', index + 1),
        },
      );
    }
  }

  Future<String> person(String name) async {
    final id = generateId('PH');
    await writer.executeWithOwnerScopes(
      [_sender],
      Sql.named('''
INSERT INTO public.phantom (id, owner_id, display_name)
VALUES (@id, @sender, @name)
'''),
      parameters: {'id': id, 'sender': _sender, 'name': name},
    );
    return id;
  }

  Future<String> invite({
    String? person,
    String? beaconId,
    String name = 'Avery',
  }) async {
    final rows = await writer.executeWithOwnerScopes(
      [_sender],
      Sql.named('''
INSERT INTO public.invitation (user_id, phantom_id, addressee_name, beacon_id)
VALUES (@sender, @person, @name, @beacon) RETURNING id
'''),
      parameters: {
        'sender': _sender,
        'person': person,
        'name': person == null ? null : name,
        'beacon': beaconId,
      },
    );
    return rows.single.single! as String;
  }

  Future<String> beacon({
    String author = _sender,
    String title = _title,
    BeaconKind kind = BeaconKind.request,
  }) async {
    final rows = await writer.execute(
      Sql.named('''
INSERT INTO public.beacon
  (user_id, title, description, kind, status, forward_policy, is_discoverable, published_at)
VALUES (@author, @title, @description, @kind, @status, @policy, false, now())
RETURNING id
'''),
      parameters: {
        'author': author,
        'title': kind == BeaconKind.post ? '' : title,
        'description': kind == BeaconKind.post ? '' : _description,
        'kind': kind.value,
        'status': BeaconStatus.open.smallintValue,
        'policy': BeaconForwardPolicyValue.open.value,
      },
    );
    final id = rows.single.single! as String;
    if (kind == BeaconKind.post) {
      final root = generateId('M');
      await writer.execute(
        Sql.named('''
INSERT INTO public.beacon_room_message (id, beacon_id, author_id, body)
VALUES (@root, @id, @author, @body)
'''),
        parameters: {
          'root': root,
          'id': id,
          'author': author,
          'body': _postBody,
        },
      );
      await writer.execute(
        Sql.named(
          'UPDATE public.beacon SET post_root_message_id = @root WHERE id = @id',
        ),
        parameters: {'root': root, 'id': id},
      );
    }
    return id;
  }

  Future<void> forward(
    String person,
    String request, {
    String state = 'pending',
  }) => writer.executeWithOwnerScopes(
    [_sender],
    Sql.named('''
INSERT INTO public.phantom_pending_forward
  (id, phantom_id, sender_id, beacon_id, note, state)
VALUES (@id, @person, @sender, @request, 'For Saturday', @state)
'''),
    parameters: {
      'id': generateId('PF'),
      'person': person,
      'sender': _sender,
      'request': request,
      'state': state,
    },
  );

  Future<void> expectPending(String person, String request) async {
    final rows = await writer.execute(
      Sql.named('''
SELECT state FROM public.phantom_pending_forward
WHERE phantom_id = @person AND beacon_id = @request
'''),
      parameters: {'person': person, 'request': request},
    );
    expect(rows.single.single, 'pending');
  }

  Future<void> closeRequest(String request) => writer.execute(
    Sql.named('UPDATE public.beacon SET status = @status WHERE id = @request'),
    parameters: {
      'status': BeaconStatus.closed.smallintValue,
      'request': request,
    },
  );

  Future<void> addSteward(String request) => writer.execute(
    Sql.named('''
INSERT INTO public.beacon_steward (beacon_id, user_id)
VALUES (@request, @sender)
'''),
    parameters: {'request': request, 'sender': _sender},
  );

  Future<bool> senderCanRead(String request) async {
    final rows = await writer.execute(
      Sql.named('SELECT public.beacon_can_read_content(@request, @sender)'),
      parameters: {'request': request, 'sender': _sender},
    );
    return rows.single.single! as bool;
  }

  Future<void> removeSteward(String request) => writer.execute(
    Sql.named(
      'DELETE FROM public.beacon_steward WHERE beacon_id = @request AND user_id = @sender',
    ),
    parameters: {'request': request, 'sender': _sender},
  );

  Future<void> consume(String code) async {
    final rows = await writer.executeWithOwnerScopes(
      [_sender],
      Sql.named('''
UPDATE public.invitation
SET invited_id = @joiner, accepted_at = now(), invite_origin = 'existing_account'
WHERE id = @code RETURNING id
'''),
      parameters: {'joiner': _otherUser, 'code': code},
    );
    expect(rows.single.single, code);
  }
}
