@Tags(['pg'])
library;

import 'package:injectable/injectable.dart' show Environment;
import 'package:postgres/postgres.dart';
import 'package:test/test.dart';

import 'package:tentura_server/app/di.dart';
import 'package:tentura_server/domain/entity/beacon_kind.dart';
import 'package:tentura_server/domain/port/beacon_repository_port.dart';
import 'package:tentura_server/domain/use_case/forward_case.dart';
import 'package:tentura_server/domain/use_case/invitation_case.dart';
import 'package:tentura_server/env.dart';

import '../../support/disposable_pg_target.dart';
import '../../support/pg_test_public_keys.dart';

const _alice = 'Uexistingali01';
const _bob = 'Uexistingbob01';
const _invitee = 'Uexistingjoin1';

Future<void> main() async {
  final target = DisposablePgTarget.fromNamedEnvironment(
    envVarName: 'TENTURA_EXISTING_ACCOUNT_POST_INVITE_RECEIPT_PG_TEST_DB',
    defaultNamePrefix: 'tentura_test_existing_post_receipt',
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
    for (final (slot, id) in [_alice, _bob, _invitee].indexed) {
      await writer.execute(
        Sql.named('''
INSERT INTO public."user" (id, display_name, public_key)
VALUES (@id, @name, @key)
'''),
        parameters: {
          'id': id,
          'name': {_alice: 'Alice', _bob: 'Bob', _invitee: 'Invitee'}[id],
          'key': pgTestPublicKey('existingpostreceipt', slot + 1),
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
SELECT o.id, o.actor_user_id, r.account_id,
  o.immutable_payload ->> 'kind' AS notification_kind,
  o.immutable_payload ->> 'beaconId' AS payload_beacon_id,
  o.immutable_payload ->> 'body' AS body,
  r.role_facts ->> 'actorUserId' AS payload_sender_id,
  b.user_id AS beacon_author_id,
  (SELECT d.payload ->> 'beaconKind'
   FROM public.attention_channel_delivery d
   WHERE d.occurrence_id = o.id AND d.account_id = r.account_id
   LIMIT 1) AS payload_beacon_kind
FROM public.attention_occurrence o
JOIN public.attention_occurrence_recipient r ON r.occurrence_id = o.id
JOIN public.beacon b ON b.id = o.immutable_payload ->> 'beaconId'
WHERE o.event_type = 'relayReceived'
  AND o.immutable_payload ->> 'beaconId' = @beacon
  AND r.account_id = @account
ORDER BY o.id
'''),
    parameters: {'beacon': beaconId, 'account': accountId},
  )).map((row) => row.toColumnMap()).toList();

  group('Existing account Post invite receipts', () {
    for (final connected in [false, true]) {
      test(
        connected
            ? 'a connected invitee receives one shared Post receipt and no duplicate from another invite'
            : 'an unconnected invitee receives one shared Post receipt and no duplicate from another invite',
        () async {
          if (connected) {
            await writer.execute(
              Sql.named('''
INSERT INTO public.vote_user (subject, object, amount)
VALUES (@bob, @invitee, 1), (@invitee, @bob, 1)
'''),
              parameters: {'bob': _bob, 'invitee': _invitee},
            );
          }
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
          expect(await receivedPosts(post.id, _invitee), isEmpty);

          final invitations = getIt<InvitationCase>();
          final invitation = await invitations.create(
            userId: _bob,
            addresseeName: 'Invitee',
            beaconId: post.id,
          );
          expect(
            await invitations.acceptAsExisting(
              code: invitation.id,
              userId: _invitee,
            ),
            isTrue,
          );
          final firstReceipts = await receivedPosts(post.id, _invitee);
          expect(
            firstReceipts,
            hasLength(1),
            reason:
                'Accepting a Post invite must deliver one shared Post receipt to the existing account',
          );
          expect(firstReceipts.single['actor_user_id'], _bob);
          expect(firstReceipts.single['account_id'], _invitee);
          expect(firstReceipts.single['notification_kind'], 'newRelay');
          expect(firstReceipts.single['payload_beacon_id'], post.id);
          expect(firstReceipts.single['payload_sender_id'], _bob);
          expect(firstReceipts.single['beacon_author_id'], _alice);
          expect(firstReceipts.single['payload_beacon_kind'], 'post');
          expect(firstReceipts.single['body'], 'Bob shared a post with you');
          Future<List<String>> forwardEdgeIds() async => (await writer.execute(
            Sql.named('''
SELECT id FROM public.beacon_forward_edge
WHERE beacon_id = @beacon AND sender_id = @bob
  AND recipient_id = @invitee AND cancelled_at IS NULL
'''),
            parameters: {
              'beacon': post.id,
              'bob': _bob,
              'invitee': _invitee,
            },
          )).map((row) => row.single! as String).toList();
          final firstEdges = await forwardEdgeIds();
          expect(firstEdges, hasLength(1));

          // A fresh invite can be consumed when Bob's forward edge already
          // exists. It must preserve that edge and produce no new occurrence.
          final anotherInvitation = await invitations.create(
            userId: _bob,
            addresseeName: 'Invitee',
            beaconId: post.id,
          );
          expect(
            await invitations.acceptAsExisting(
              code: anotherInvitation.id,
              userId: _invitee,
            ),
            isTrue,
          );
          expect(await forwardEdgeIds(), firstEdges);
          expect(
            await receivedPosts(post.id, _invitee),
            firstReceipts,
            reason: 'An existing forward edge must not produce another receipt',
          );
        },
      );
    }
    for (final connected in [false, true]) {
      test(
        connected
            ? 'a connected invitee with a pre-existing forward edge receives no receipt when accepting an invite'
            : 'an unconnected invitee with a pre-existing forward edge receives no receipt when accepting an invite',
        () async {
          if (connected) {
            await writer.execute(
              Sql.named('''
INSERT INTO public.vote_user (subject, object, amount)
VALUES (@bob, @invitee, 1), (@invitee, @bob, 1)
'''),
              parameters: {'bob': _bob, 'invitee': _invitee},
            );
          }
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
          // Seed an existing delivery without attention, before any invitation
          // is accepted. Acceptance must not backfill a shared Post receipt.
          final edges = await writer.execute(
            Sql.named('''
INSERT INTO public.beacon_forward_edge
  (beacon_id, sender_id, recipient_id, parent_edge_id)
SELECT @beacon, @bob, @invitee, id
FROM public.beacon_forward_edge
WHERE beacon_id = @beacon AND sender_id = @alice AND recipient_id = @bob
RETURNING id
'''),
            parameters: {
              'beacon': post.id,
              'alice': _alice,
              'bob': _bob,
              'invitee': _invitee,
            },
          );
          expect(edges, hasLength(1));
          expect(await receivedPosts(post.id, _invitee), isEmpty);
          final invitations = getIt<InvitationCase>();
          final invitation = await invitations.create(
            userId: _bob,
            addresseeName: 'Invitee',
            beaconId: post.id,
          );
          expect(
            await invitations.acceptAsExisting(
              code: invitation.id,
              userId: _invitee,
            ),
            isTrue,
          );
          expect(await receivedPosts(post.id, _invitee), isEmpty);
          final remainingEdges = await writer.execute(
            Sql.named('''
SELECT id FROM public.beacon_forward_edge
WHERE beacon_id = @beacon AND sender_id = @bob
  AND recipient_id = @invitee AND cancelled_at IS NULL
'''),
            parameters: {'beacon': post.id, 'bob': _bob, 'invitee': _invitee},
          );
          expect(remainingEdges.map((row) => row.single), [
            edges.single.single,
          ]);
        },
      );
    }
  });
}
