@Tags(['pg', 'mr'])
library;

import 'dart:convert';

import 'package:dart_jsonwebtoken/dart_jsonwebtoken.dart';
import 'package:injectable/injectable.dart' show Environment;
import 'package:postgres/postgres.dart';
import 'package:shelf_plus/shelf_plus.dart';
import 'package:test/test.dart';

import 'package:tentura_root/domain/entity/auth_request_intent.dart';
import 'package:tentura_server/api/root_router.dart';
import 'package:tentura_server/app/di.dart';
import 'package:tentura_server/domain/entity/beacon_kind.dart';
import 'package:tentura_server/domain/use_case/auth_case.dart';
import 'package:tentura_server/domain/use_case/beacon_case.dart';
import 'package:tentura_server/domain/use_case/invitation_case.dart';
import 'package:tentura_server/domain/use_case/post_case.dart';
import 'package:tentura_server/env.dart';

import '../../support/disposable_pg_target.dart';
import '../../support/pg_test_public_keys.dart';

const _alice = 'Uabc000000001';
const _existing = 'Uabc000000002';
const _observer = 'Uabc000000003';
const _postText = 'Who would like to join the community garden?';
const _origin = 'http://127.0.0.1:2080';

String _signupRequestToken(String invitationId) {
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
    envVarName: 'TENTURA_POST_INVITE_ACTIVITY_RECEIPT_PG_TEST_DB',
    defaultNamePrefix: 'tentura_test_post_link_receipt',
  );
  final pgSkip = await pgSkipReason(target);
  if (pgSkip != null) {
    test('Postgres unavailable', () {}, skip: pgSkip);
    return;
  }

  late DisposablePgWriterSession session;
  late Connection writer;
  late Handler api;
  final accessTokens = <String, String>{};

  setUpAll(() async {
    // Activity provenance uses pgmer2; the mr tag serializes its shared service.
    session = await setUpDisposablePgWriter(
      target: target,
      createPgmer2Extension: true,
    );
    writer = session.writer;
    final db = target.databaseEnv;
    await configureDependencies(
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
        workersCount: 1,
        printEnv: false,
        isDebugModeOn: false,
        isNeedInvite: true,
        qaAuthEnabled: true,
        qaSimpleLoginMode: true,
        qaEmailDomains: const ['example.test'],
        genealogyNodeKeySecret: 'test-genealogy-secret',
      ),
    );
    await getIt.allReady(ignorePendingAsyncCreation: true);
    api = (await getIt.getAsync<RootRouter>()).routeHandler();
  });

  tearDownAll(() async {
    await getIt.reset();
    await tearDownDisposablePgWriter(session: session);
  });

  setUp(() async {
    accessTokens.clear();
    await writer.execute('''
TRUNCATE public.attention_occurrence, public.notification_outbox,
  public.invitation, public.beacon, public."user" CASCADE
''');
    for (final (slot, id) in [_alice, _existing, _observer].indexed) {
      await writer.execute(
        Sql.named('''
INSERT INTO public."user" (id, display_name, public_key)
VALUES (@id, @name, @key)
'''),
        parameters: {
          'id': id,
          'name': {
            _alice: 'Alice',
            _existing: 'Existing person',
            _observer: 'Observer',
          }[id],
          'key': pgTestPublicKey('postlinkreceipt', slot + 1),
        },
      );
    }
  });

  Map<String, String> auth(String accountId) => {
    'authorization':
        'Bearer ${accessTokens[accountId] ?? getIt<AuthCase>().issueAccessToken(accountId).rawToken}',
  };

  Future<Map<String, dynamic>> jsonResponse(Response response) async {
    final body = await response.readAsString();
    expect(response.statusCode, 200, reason: body);
    return jsonDecode(body) as Map<String, dynamic>;
  }

  Future<Map<String, dynamic>> graphql(
    String? accountId,
    String query,
    Map<String, Object?> variables,
  ) async {
    final result = await jsonResponse(
      await api(
        Request(
          'POST',
          Uri.parse('$_origin/api/v2/graphql'),
          headers: {
            if (accountId != null) ...auth(accountId),
            'content-type': 'application/json',
          },
          body: jsonEncode({'query': query, 'variables': variables}),
        ),
      ),
    );
    expect(result['errors'], isNull, reason: jsonEncode(result));
    return result['data']! as Map<String, dynamic>;
  }

  Future<({String postId, String inviteId})> inviteToUnsentPost() async {
    final draft = await getIt<BeaconCase>().create(
      userId: _alice,
      title: '',
      kind: BeaconKind.post,
      isDiscoverable: false,
    );
    await getIt<PostCase>().publish(
      authorId: _alice,
      beaconId: draft.id,
      body: _postText,
      mentionUserIds: const [],
      mentionOffsets: const [],
      mentionLengths: const [],
      recipientIds: const [],
      notes: const {},
      forwardPolicy: BeaconForwardPolicyValue.open,
    );
    expect(
      (await writer.execute(
        Sql.named(
          'SELECT count(*) FROM public.beacon_forward_edge '
          'WHERE beacon_id = @post',
        ),
        parameters: {'post': draft.id},
      )).single.single,
      0,
      reason: 'The author has published the Post without sending it to anyone',
    );
    // This is the use case behind invitationCreate in Forward -> Invite person.
    final invitation = await getIt<InvitationCase>().create(
      userId: _alice,
      addresseeName: 'Garden visitor',
      beaconId: draft.id,
    );
    return (postId: draft.id, inviteId: invitation.id);
  }

  Future<List<Map<String, dynamic>>> sharedPostRows(
    String accountId,
    String postId,
  ) async {
    // The Activity API scopes this query to the authenticated account.
    // "all" selects read and unread items, not other users' receipts.
    final result = await graphql(
      accountId,
      '''
query {
  attentionFeed(view: "all", surface: "activity") {
    page { items {
      id beaconId beaconKind postRootExcerpt
      eventsPreview { id actorUserId body presentationKey beaconId }
    } }
  }
}
''',
      const {},
    );
    final page = (result['attentionFeed']! as Map)['page']! as Map;
    return (page['items']! as List)
        .cast<Map<String, dynamic>>()
        .where((row) => row['beaconId'] == postId)
        .toList();
  }

  Future<void> expectReceiptPrivateToInvitee(String postId) async {
    expect(
      await sharedPostRows(_observer, postId),
      isEmpty,
      reason: "Another account must not receive the invitee's Post card",
    );
    final authorRows = await sharedPostRows(_alice, postId);
    expect(
      authorRows
          .expand((row) => row['eventsPreview']! as List)
          .where(
            (event) => (event as Map)['presentationKey'] == 'relay_received',
          ),
      isEmpty,
      reason: "The inviter must not receive the invitee's shared Post receipt",
    );
  }

  void expectSharedPostReceipt(
    List<Map<String, dynamic>> rows,
    String postId,
  ) {
    expect(rows, hasLength(1), reason: 'For you must show the invited Post');
    final row = rows.single;
    expect(row['beaconKind'], 1);
    expect(row['postRootExcerpt'], _postText);
    final shares = (row['eventsPreview']! as List)
        .cast<Map<String, dynamic>>()
        .where((event) => event['presentationKey'] == 'relay_received')
        .toList();
    expect(
      shares,
      hasLength(1),
      reason: 'For you must name who shared the Post, not only show its card',
    );
    expect(shares.single['actorUserId'], _alice);
    expect(shares.single['body'], 'Alice shared a post with you');
    expect(shares.single['beaconId'], postId);
  }

  Future<void> openPost(String accountId, String postId) async {
    final result = await graphql(
      accountId,
      r'''
query($id: String!) {
  postSummary(id: $id) { id rootExcerpt }
}
''',
      {'id': postId},
    );
    expect(result['postSummary'], {'id': postId, 'rootExcerpt': _postText});
  }

  Future<void> connectExistingPerson() => writer.execute(
    Sql.named('''
INSERT INTO public.vote_user (subject, object, amount)
VALUES (@alice, @invitee, 1), (@invitee, @alice, 1)
'''),
    parameters: {'alice': _alice, 'invitee': _existing},
  );

  Future<Response> acceptExisting(String inviteId) async => api(
    Request(
      'POST',
      Uri.parse('$_origin/api/v2/invite/$inviteId/accept-as-existing'),
      headers: auth(_existing),
    ),
  );

  group('Post invite links deliver shared Post Activity receipts', () {
    test(
      'email signup creates one shared Post receipt before Post access '
      'and login retry preserves it',
      () async {
        final link = await inviteToUnsentPost();
        await expectReceiptPrivateToInvitee(link.postId);
        Future<Response> signUp() async => api(
          Request(
            'POST',
            Uri.parse('$_origin/api/v2/auth/email/test-login'),
            headers: {'content-type': 'application/json'},
            body: jsonEncode({
              'email': 'garden-visitor@example.test',
              'inviteCode': link.inviteId,
            }),
          ),
        );
        final first = await signUp();
        final cookie = first.headers['set-cookie']!.split(';').first;
        expect((await jsonResponse(first))['isNewAccount'], isTrue);
        final profile = await jsonResponse(
          await api(
            Request(
              'GET',
              Uri.parse('$_origin/api/v2/accounts/me/profile'),
              headers: {'cookie': cookie},
            ),
          ),
        );
        final accountId = profile['id']! as String;
        expect(
          (await writer.execute(
            Sql.named(
              'SELECT invited_id FROM public.invitation WHERE id = @id',
            ),
            parameters: {'id': link.inviteId},
          )).single.single,
          accountId,
          reason: 'New-account signup has consumed this Post invite',
        );
        final before = await sharedPostRows(accountId, link.postId);
        await expectReceiptPrivateToInvitee(link.postId);
        expectSharedPostReceipt(before, link.postId);
        await openPost(accountId, link.postId);
        expect((await jsonResponse(await signUp()))['isNewAccount'], isFalse);
        final after = await sharedPostRows(accountId, link.postId);
        expectSharedPostReceipt(after, link.postId);
        expect(
          after,
          before,
          reason: 'Login retry must preserve the same receipt',
        );
      },
    );

    test('a connected person can accept an unsent Post from its invite preview '
        'and retry preserves one receipt', () async {
      await connectExistingPerson();
      final link = await inviteToUnsentPost();
      expect(
        await sharedPostRows(_existing, link.postId),
        isEmpty,
        reason: 'The connected invitee has no Post receipt before acceptance',
      );
      await expectReceiptPrivateToInvitee(link.postId);
      final preview = await jsonResponse(
        await api(
          Request(
            'GET',
            Uri.parse('$_origin/api/v2/invite/${link.inviteId}/preview'),
            headers: auth(_existing),
          ),
        ),
      );
      expect(preview['codeStatus'], 'available');
      expect(
        preview['suggestedAction'],
        'accept-as-existing',
        reason: 'An existing connection must still be offered Post acceptance',
      );
      // Follow the preview's CTA through the same REST route as the client.
      final accepted = await jsonResponse(await acceptExisting(link.inviteId));
      expect(accepted['ok'], isTrue);
      final before = await sharedPostRows(_existing, link.postId);
      final retry = await acceptExisting(link.inviteId);
      expect(retry.statusCode, anyOf(200, 404));
      await retry.readAsString();
      final after = await sharedPostRows(_existing, link.postId);
      await expectReceiptPrivateToInvitee(link.postId);
      expectSharedPostReceipt(before, link.postId);
      expectSharedPostReceipt(after, link.postId);
      expect(
        after,
        before,
        reason: 'Accept retry must preserve the same receipt',
      );
    });

    test('GraphQL invite signup creates one private shared Post receipt '
        'before Post access and accept retry preserves it', () async {
      final link = await inviteToUnsentPost();
      await expectReceiptPrivateToInvitee(link.postId);
      final token = _signupRequestToken(link.inviteId);
      final publicKey =
          (JWT.decode(token).payload as Map)[AuthRequestIntent.keyPublicKey];
      expect(
        (await writer.execute(
          Sql.named(
            'SELECT count(*) FROM public."user" WHERE public_key = @key',
          ),
          parameters: {'key': publicKey},
        )).single.single,
        0,
        reason: 'The device belongs to a brand-new account',
      );
      final result = await graphql(
        null,
        r'''
mutation SignUp($authRequestToken: String!, $displayName: String!) {
  signUp(authRequestToken: $authRequestToken, displayName: $displayName) {
    subject access_token
  }
}
''',
        {'authRequestToken': token, 'displayName': 'Garden visitor'},
      );
      final signup = result['signUp']! as Map;
      final accountId = signup['subject']! as String;
      accessTokens[accountId] = signup['access_token']! as String;
      expect(
        (await writer.execute(
          Sql.named('SELECT invited_id FROM public.invitation WHERE id = @id'),
          parameters: {'id': link.inviteId},
        )).single.single,
        accountId,
        reason: 'GraphQL signup must consume the Post invite',
      );
      final before = await sharedPostRows(accountId, link.postId);
      await expectReceiptPrivateToInvitee(link.postId);
      expectSharedPostReceipt(before, link.postId);
      await openPost(accountId, link.postId);

      // A consumed invite may return 404 or an idempotent success; either
      // outcome must leave the original shared Post receipt intact.
      final retry = await api(
        Request(
          'POST',
          Uri.parse(
            '$_origin/api/v2/invite/${link.inviteId}/accept-as-existing',
          ),
          headers: auth(accountId),
        ),
      );
      expect(retry.statusCode, anyOf(200, 404));
      await retry.readAsString();
      final after = await sharedPostRows(accountId, link.postId);
      await expectReceiptPrivateToInvitee(link.postId);
      expectSharedPostReceipt(after, link.postId);
      expect(
        after,
        before,
        reason: 'Accept retry must preserve the same receipt',
      );
    });
  });
}
