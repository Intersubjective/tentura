@Tags(['pg'])
library;

import 'dart:convert';

import 'package:dart_jsonwebtoken/dart_jsonwebtoken.dart';
import 'package:injectable/injectable.dart' show Environment;
import 'package:postgres/postgres.dart';
import 'package:test/test.dart';

import 'package:tentura_root/domain/entity/auth_request_intent.dart';
import 'package:tentura_server/app/di.dart';
import 'package:tentura_server/domain/entity/account_credential_entity.dart';
import 'package:tentura_server/domain/entity/beacon_kind.dart';
import 'package:tentura_server/domain/exception.dart';
import 'package:tentura_server/domain/port/beacon_repository_port.dart';
import 'package:tentura_server/domain/use_case/auth_case.dart';
import 'package:tentura_server/domain/use_case/credential_auth_case.dart';
import 'package:tentura_server/domain/use_case/forward_case.dart';
import 'package:tentura_server/domain/use_case/invitation_case.dart';
import 'package:tentura_server/env.dart';

import '../../support/disposable_pg_target.dart';
import '../../support/pg_test_public_keys.dart';

const _alice = 'Ureceiptali01';
const _bob = 'Ureceiptbob01';

String _authRequestToken(String invitationId) {
  final publicKey = EdDSAPublicKey.fromPEM(
    Env.kJwtPublicKey.replaceAll(r'\n', '\n'),
  );
  final privateKey = EdDSAPrivateKey.fromPEM(
    Env.kJwtPrivateKey.replaceAll(r'\n', '\n'),
  );
  return JWT({
    AuthRequestIntent.keyPublicKey: base64UrlEncode(publicKey.bytes),
    AuthRequestIntentSignUp.keyCode: invitationId,
  }).sign(
    privateKey,
    algorithm: JWTAlgorithm.EdDSA,
    expiresIn: const Duration(minutes: 5),
  );
}

Future<void> main() async {
  final target = DisposablePgTarget.fromNamedEnvironment(
    envVarName: 'TENTURA_INVITED_SIGNUP_POST_RECEIPT_PG_TEST_DB',
    defaultNamePrefix: 'tentura_test_signup_post_receipt',
  );
  final pgSkip = await pgSkipReason(target);
  if (pgSkip != null) {
    test('Postgres unavailable', () {}, skip: pgSkip);
    return;
  }

  late DisposablePgWriterSession session;
  late Connection writer;

  setUpAll(() async {
    session = await setUpDisposablePgWriter(target: target);
    writer = session.writer;
    final db = target.databaseEnv;
    await configureDependencies(
      Env(
        environment: Environment.dev,
        serverUri: Uri.parse('http://127.0.0.1:2080'),
        publicKey: Env.kJwtPublicKey,
        privateKey: Env.kJwtPrivateKey,
        pgHost: db.pgHost,
        pgPort: db.pgPort,
        pgDatabase: db.pgDatabase,
        pgUsername: db.pgUsername,
        pgPassword: db.pgPassword,
        publicOrigin: 'http://127.0.0.1:2080',
        workersCount: 1,
        printEnv: false,
        isDebugModeOn: false,
        isNeedInvite: true,
        genealogyNodeKeySecret: 'test-genealogy-secret',
      ),
    );
    await getIt.allReady(ignorePendingAsyncCreation: true);
  });

  tearDownAll(() async {
    await getIt.reset();
    await tearDownDisposablePgWriter(session: session);
  });

  setUp(() async {
    await writer.execute('''
TRUNCATE TABLE public.attention_occurrence_recipient,
  public.attention_occurrence, public.invitation, public.beacon_forward_edge,
  public.beacon, public."user" CASCADE
''');
    for (final (slot, id) in [_alice, _bob].indexed) {
      await writer.execute(
        Sql.named('''
INSERT INTO public."user" (id, display_name, public_key)
VALUES (@id, @name, @key)
'''),
        parameters: {
          'id': id,
          'name': id == _alice ? 'Alice' : 'Bob',
          'key': pgTestPublicKey('postreceipt', slot + 1),
        },
      );
    }
    // Alice and Bob are already connected, so Alice can forward to Bob.
    await writer.execute(
      Sql.named('''
INSERT INTO public.vote_user (subject, object, amount)
VALUES (@alice, @bob, 1), (@bob, @alice, 1)
'''),
      parameters: {'alice': _alice, 'bob': _bob},
    );
  });

  Future<List<Map<String, dynamic>>> receivedPosts(
    String beaconId,
    String accountId,
  ) async => (await writer.execute(
    Sql.named('''
SELECT o.id, o.actor_user_id, r.account_id
FROM public.attention_occurrence o
JOIN public.attention_occurrence_recipient r ON r.occurrence_id = o.id
WHERE o.event_type = 'relayReceived'
  AND o.immutable_payload ->> 'beaconId' = @beacon
  AND r.account_id = @account
ORDER BY o.id
'''),
    parameters: {'beacon': beaconId, 'account': accountId},
  )).map((row) => row.toColumnMap()).toList();

  for (final credentialSignup in [false, true]) {
    final path = credentialSignup
        ? 'email credential signup'
        : 'device key signup';
    group('Post invite receipts through $path', () {
      Future<
        ({
          String beaconId,
          String newcomerId,
          String forwardEdgeId,
          Future<String> Function() signUp,
        })
      >
      joinPost() async {
        final post = await getIt<BeaconRepositoryPort>().createBeacon(
          authorId: _alice,
          title: '',
          description: '',
          kind: BeaconKind.post,
          isDiscoverable: false,
        );
        await getIt<ForwardCase>().forward(
          senderId: _alice,
          beaconId: post.id,
          recipientIds: [_bob],
        );
        expect(await receivedPosts(post.id, _bob), hasLength(1));
        final invitation = await getIt<InvitationCase>().create(
          userId: _bob,
          addresseeName: 'Newcomer',
          beaconId: post.id,
        );
        final token = _authRequestToken(invitation.id);
        Future<String> signUp() async {
          if (credentialSignup) {
            final result = await getIt<CredentialAuthCase>().resolveOrCreate(
              type: CredentialType.emailOtp,
              identifier: 'post-invite-newcomer@example.test',
              displayName: 'Newcomer',
              inviteId: invitation.id,
            );
            return result.accountId;
          }
          return (await getIt<AuthCase>().signUp(
            authRequestToken: token,
            displayName: 'Newcomer',
          )).sub;
        }

        final newcomerId = await signUp();
        final edges = await writer.execute(
          Sql.named('''
SELECT id FROM public.beacon_forward_edge
WHERE beacon_id = @beacon AND sender_id = @bob
  AND recipient_id = @newcomer AND cancelled_at IS NULL
'''),
          parameters: {
            'beacon': post.id,
            'bob': _bob,
            'newcomer': newcomerId,
          },
        );
        expect(
          edges,
          hasLength(1),
          reason: 'Signup forwards the Post to the new account',
        );
        return (
          beaconId: post.id,
          newcomerId: newcomerId,
          forwardEdgeId: edges.single.single! as String,
          signUp: signUp,
        );
      }

      test(
        'joining a Post invite records a shared Post receipt for the new account',
        () async {
          final joined = await joinPost();
          final receipts = await receivedPosts(
            joined.beaconId,
            joined.newcomerId,
          );
          expect(
            receipts,
            hasLength(1),
            reason:
                'Joining the Post invite must record a relayReceived occurrence addressed to the new account',
          );
          expect(receipts.single['actor_user_id'], _bob);
          expect(receipts.single['account_id'], joined.newcomerId);
        },
      );

      test(
        credentialSignup
            ? 'repeating credential signup returns the same account and preserves its single Post receipt'
            : 'repeating device signup rejects the consumed invite and preserves its single Post receipt',
        () async {
          final joined = await joinPost();
          final firstReceipts = await receivedPosts(
            joined.beaconId,
            joined.newcomerId,
          );

          // Device signup is a one-time operation: its public API rejects a
          // consumed invite. This checks that rejection separately from the
          // successful resolve-or-create retry supported by credential signup.
          if (credentialSignup) {
            expect(await joined.signUp(), joined.newcomerId);
          } else {
            await expectLater(
              joined.signUp(),
              throwsA(isA<InvitationWrongException>()),
            );
          }
          final retriedReceipts = await receivedPosts(
            joined.beaconId,
            joined.newcomerId,
          );
          final retriedEdges = await writer.execute(
            Sql.named('''
SELECT id FROM public.beacon_forward_edge
WHERE beacon_id = @beacon AND sender_id = @bob
  AND recipient_id = @newcomer AND cancelled_at IS NULL
'''),
            parameters: {
              'beacon': joined.beaconId,
              'bob': _bob,
              'newcomer': joined.newcomerId,
            },
          );
          expect(
            retriedEdges.map((row) => row.single),
            [joined.forwardEdgeId],
            reason:
                'The Bob-to-invitee edge already exists before retry '
                'and must survive without replacement or duplication',
          );
          final occurrences = await writer.execute(
            Sql.named('''
SELECT o.id
FROM public.attention_occurrence o
WHERE o.event_type = 'relayReceived'
  AND o.immutable_payload ->> 'beaconId' = @beacon
  AND o.actor_user_id = @bob
'''),
            parameters: {'beacon': joined.beaconId, 'bob': _bob},
          );

          expect(
            retriedReceipts,
            hasLength(1),
            reason:
                'The account must retain exactly one shared Post receipt after the repeated signup',
          );
          expect(retriedReceipts, firstReceipts);
          expect(
            occurrences,
            hasLength(1),
            reason:
                'The repeated signup must leave exactly one Post occurrence',
          );
        },
      );
    });
  }
}
