@Tags(['pg'])
library;

import 'dart:convert';
import 'dart:io';

import 'package:http/http.dart' as http;
import 'package:logging/logging.dart';
import 'package:postgres/postgres.dart';
import 'package:test/test.dart';
import 'package:tentura_server/domain/port/invitation_repository_port.dart';
import 'package:tentura_server/domain/port/user_repository_port.dart';
import 'package:tentura_server/domain/use_case/auth_case.dart';
import 'package:tentura_server/env.dart';

import '../support/disposable_pg_target.dart';
import '../support/hasura_pg_jwt_keys.dart';
import '../support/isolated_hasura_session.dart';

/// Through a real Hasura, role `user` can still reject a Request in their
/// inbox, but cannot change the inbox row of a Post: leaving a Post goes
/// through `postLeave`, which also declines the contact edge and sets room
/// access. A rejected update changes nothing.
/// See `docs/plans/post-and-constellation-composer-plan.md` §4.8.
const _author = 'Uhinboxauthor01';
const _member = 'Uhinboxmember01';

const _post = 'Bhinboxpost0001';
const _request = 'Bhinboxreq00001';

const _inboxNeedsMe = 0;
const _inboxRejected = 2;

Future<void> main() async {
  final target = DisposablePgTarget.fromNamedEnvironment(
    envVarName: 'TENTURA_POST_INBOX_HASURA_PG_TEST_DB',
    defaultNamePrefix: 'tentura_test_post_inbox_hasura',
  );

  final pgSkip = await pgSkipReason(target);
  if (pgSkip != null) {
    test('Postgres unavailable', () {}, skip: pgSkip);
    return;
  }
  final dockerReachable = await IsolatedHasuraSession.isDockerAvailable();
  if (!dockerReachable) {
    if (isPgTestsRequired()) {
      test('Docker is available for isolated Hasura', () {
        fail(
          'Docker required ($pgTestsRequiredEnvVar=1) but not available',
        );
      });
    } else {
      test('Docker unavailable', () {}, skip: 'Docker not available');
    }
    return;
  }

  group('Inbox status update through Hasura', () {
    late DisposablePgWriterSession session;
    late Connection writer;
    late AuthCase authCase;
    late IsolatedHasuraSession hasura;

    setUpAll(() async {
      session = await setUpDisposablePgWriter(target: target);
      writer = session.writer;
      for (final id in [_author, _member]) {
        await writer.execute('''
INSERT INTO public."user" (id, display_name, public_key)
VALUES ('$id', '$id', 'pk-$id')
''');
      }
      await writer.execute('''
INSERT INTO public.beacon
  (id, user_id, title, description, status, kind, forward_policy,
   is_discoverable, published_at)
VALUES ('$_post', '$_author', '', '', 0, 1, 1, false, now())
''');
      await writer.execute('''
INSERT INTO public.beacon
  (id, user_id, title, description, status, published_at)
VALUES ('$_request', '$_author', 'Request', '', 0, now())
''');

      final jwtKeys = loadJwtKeysForHasuraPgTests();
      authCase = AuthCase(
        _NoopUserRepository(),
        _NoopInvitationRepository(),
        env: _authEnv(target.databaseEnv, jwtKeys),
        logger: Logger('PostInboxHasuraPgTest'),
      );
      hasura = await IsolatedHasuraSession.start(
        databaseEnv: target.databaseEnv,
        jwtPublicPem: jwtKeys.publicKey,
      );
      await hasura.applyRepoMetadata();
    });

    setUp(() async {
      await writer.execute('TRUNCATE TABLE public.inbox_item');
      await writer.execute('''
INSERT INTO public.inbox_item (user_id, beacon_id, status)
VALUES
  ('$_member', '$_post', $_inboxNeedsMe),
  ('$_member', '$_request', $_inboxNeedsMe)
''');
    });

    tearDownAll(() async {
      try {
        await hasura.stop();
      } finally {
        await tearDownDisposablePgWriter(session: session);
      }
    });

    Future<int> storedStatus(String beaconId) async =>
        (await writer.execute('''
SELECT status FROM public.inbox_item
WHERE user_id = '$_member' AND beacon_id = '$beaconId'
''')).single.single!
            as int;

    /// Rows the mutation reports as updated, or `0` when Hasura refuses it.
    Future<int> rejectAsMember(String beaconId) async {
      final response = await _graphql(
        hasura,
        authCase.issueAccessToken(_member).rawToken,
        '''
mutation {
  update_inbox_item(
    where: {user_id: {_eq: "$_member"}, beacon_id: {_eq: "$beaconId"}},
    _set: {status: $_inboxRejected}
  ) { affected_rows }
}
''',
      );
      if (response['errors'] != null) return 0;
      final data = response['data']! as Map<String, dynamic>;
      return (data['update_inbox_item']!
              as Map<String, dynamic>)['affected_rows']!
          as int;
    }

    test('Hasura accepts the repository metadata without dropping objects', () {
      return hasura.assertMetadataConsistent();
    });

    test('the member cannot change the inbox status of a Post', () async {
      expect(await rejectAsMember(_post), 0);
      expect(await storedStatus(_post), _inboxNeedsMe);
    });

    test('the member can still reject a Request', () async {
      expect(await rejectAsMember(_request), 1);
      expect(await storedStatus(_request), _inboxRejected);
    });

    test(
      'dismiss note is owner-only; cannot-help note reaches the sender',
      () async {
        // A real forward edge makes the sender's role and visibility meaningful.
        await writer.execute(
          "UPDATE public.inbox_item SET status = 1, "
          "rejection_message = '' WHERE user_id = '$_member' "
          "AND beacon_id = '$_request'",
        );
        await writer.execute("""
INSERT INTO public.beacon_forward_edge (beacon_id, sender_id, recipient_id)
VALUES ('$_request', '$_author', '$_member')
""");
        final memberToken = authCase.issueAccessToken(_member).rawToken;
        final senderToken = authCase.issueAccessToken(_author).rawToken;
        final dismissed = await _graphql(
          hasura,
          memberToken,
          File(
            '../client/lib/features/inbox/data/gql/inbox_dismiss.graphql',
          ).readAsStringSync(),
          variables: {
            'beaconId': _request,
            'privateNote': 'My private dismiss note',
          },
        );
        expect(dismissed['errors'], isNull);
        expect((dismissed['data'] as Map)['update_inbox_item'], {
          'affected_rows': 1,
        });

        const noteQuery =
            '''
query {
  inbox_item(where: {user_id: {_eq: "$_member"}, beacon_id: {_eq: "$_request"}}) {
    private_note
  }
  beacon_forward_edge(where: {beacon_id: {_eq: "$_request"}}) {
    recipient_rejected
    recipient_rejection_message
  }
}
''';
        final owner = await _graphql(hasura, memberToken, noteQuery);
        expect(owner['errors'], isNull);
        expect((owner['data'] as Map)['inbox_item'], [
          {'private_note': 'My private dismiss note'},
        ]);
        final sender = await _graphql(hasura, senderToken, noteQuery);
        expect(sender['errors'], isNull);
        expect((sender['data'] as Map)['inbox_item'], isEmpty);
        expect((sender['data'] as Map)['beacon_forward_edge'], [
          {'recipient_rejected': true, 'recipient_rejection_message': ''},
        ]);
        final forged = await _graphql(hasura, senderToken, '''
mutation {
  update_inbox_item(where: {user_id: {_eq: "$_member"}, beacon_id: {_eq: "$_request"}},
    _set: {private_note: "forged"}) { affected_rows }
}
''');
        expect(forged['errors'], isNull);
        expect((forged['data'] as Map)['update_inbox_item'], {
          'affected_rows': 0,
        });

        // This is the existing Can't help path. It must still communicate a note.
        final rejected = await _graphql(
          hasura,
          memberToken,
          File(
            '../client/lib/features/inbox/data/gql/inbox_set_status.graphql',
          ).readAsStringSync(),
          variables: {
            'beaconId': _request,
            'status': 2,
            'rejectionMessage': 'I cannot help today',
          },
        );
        expect(rejected['errors'], isNull);
        final afterRejection = await _graphql(hasura, senderToken, noteQuery);
        expect(afterRejection['errors'], isNull);
        expect((afterRejection['data'] as Map)['inbox_item'], isEmpty);
        expect((afterRejection['data'] as Map)['beacon_forward_edge'], [
          {
            'recipient_rejected': true,
            'recipient_rejection_message': 'I cannot help today',
          },
        ]);
        final ownerAfter = await _graphql(hasura, memberToken, noteQuery);
        expect((ownerAfter['data'] as Map)['inbox_item'], [
          {'private_note': 'My private dismiss note'},
        ]);
      },
    );
  });
}

Future<Map<String, dynamic>> _graphql(
  IsolatedHasuraSession hasura,
  String jwt,
  String query, {
  Map<String, Object?> variables = const {},
}) async {
  final response = await http.post(
    Uri.parse('${hasura.baseUrl}/v1/graphql'),
    headers: {
      'Content-Type': 'application/json',
      'Authorization': 'Bearer $jwt',
    },
    body: jsonEncode({'query': query, 'variables': variables}),
  );
  return jsonDecode(response.body) as Map<String, dynamic>;
}

final class _NoopUserRepository implements UserRepositoryPort {
  @override
  dynamic noSuchMethod(Invocation invocation) => throw UnimplementedError();
}

final class _NoopInvitationRepository implements InvitationRepositoryPort {
  @override
  dynamic noSuchMethod(Invocation invocation) => throw UnimplementedError();
}

Env _authEnv(Env base, ({String publicKey, String privateKey}) jwtKeys) => Env(
  environment: base.environment,
  pgHost: base.pgHost,
  pgPort: base.pgPort,
  pgDatabase: base.pgDatabase,
  pgUsername: base.pgUsername,
  pgPassword: base.pgPassword,
  printEnv: false,
  isDebugModeOn: false,
  publicKey: jwtKeys.publicKey,
  privateKey: jwtKeys.privateKey,
);
