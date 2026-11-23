@Tags(['pg'])
library;

import 'dart:convert';

import 'package:dart_jsonwebtoken/dart_jsonwebtoken.dart';
import 'package:injectable/injectable.dart' show Environment;
import 'package:postgres/postgres.dart';
import 'package:shelf/shelf.dart';
import 'package:test/test.dart';

import 'package:tentura_root/domain/entity/auth_request_intent.dart';
import 'package:tentura_root/domain/entity/beacon_status.dart';
import 'package:tentura_server/api/controllers/session_controller.dart';
import 'package:tentura_server/app/di.dart';
import 'package:tentura_server/domain/entity/account_credential_entity.dart';
import 'package:tentura_server/domain/entity/beacon_kind.dart';
import 'package:tentura_server/domain/entity/email_auth_peek.dart';
import 'package:tentura_server/domain/entity/notification_kind.dart';
import 'package:tentura_server/domain/exception.dart';
import 'package:tentura_server/domain/notification/notification_copy_renderer.dart';
import 'package:tentura_server/domain/notification/notification_identity.dart';
import 'package:tentura_server/domain/port/email_auth_transaction_repository_port.dart';
import 'package:tentura_server/domain/use_case/auth_case.dart';
import 'package:tentura_server/domain/use_case/email_auth_case.dart';
import 'package:tentura_server/domain/use_case/invitation_case.dart';
import 'package:tentura_server/domain/use_case/session_case.dart';
import 'package:tentura_server/env.dart';

import '../../support/disposable_pg_target.dart';
import '../../support/pg_test_public_keys.dart';

const _author = 'U1a95ea4d001';
const _relay = 'U1a95ea4d002';
const _issuer = 'U1a95ea4d003';
const _request = 'B1a95ea4d001';
const _ancestor = 'F1a95ea4d001';
const _parent = 'F1a95ea4d002';
const _issuerName = 'Irina Volkova';
const _requestTitle = 'Community garden';
const _joinerName = 'New member';
const _email = 'garden-invite@example.test';
const _postExpiryConstraint = 'beacon_post_expires_at_ck';

final _lapseEn = RegExp(
  r'\b(lapsed|closed|expired|unavailable|cancelled|no longer (available|open))\b',
  caseSensitive: false,
);
final _lapseRu = RegExp(
  'закры|ист[её]к|недоступ|отмен|больше не доступ|больше нельзя',
  caseSensitive: false,
);
final _placeholderName = RegExp(
  'phantom|фантом|призрак',
  caseSensitive: false,
);

enum _SignupMethod {
  deviceKey('Device-key signup'),
  emailCredential('Email credential signup');

  const _SignupMethod(this.label);

  final String label;
}

Future<void> main() async {
  final target = DisposablePgTarget.fromNamedEnvironment(
    envVarName: 'TENTURA_REQUEST_INVITE_SIGNUP_PG_TEST_DB',
    defaultNamePrefix: 'tentura_test_request_invite_signup',
  );
  final skip = await pgSkipReason(target);
  if (skip != null) {
    test('Postgres unavailable', () {}, skip: skip);
    return;
  }

  late DisposablePgWriterSession session;
  late Connection writer;
  final devicePublicKey = base64UrlEncode(
    EdDSAPublicKey.fromPEM(Env.kJwtPublicKey.replaceAll(r'\n', '\n')).bytes,
  );

  setUpAll(() async {
    session = await setUpDisposablePgWriter(target: target);
    writer = session.writer;
    final db = target.databaseEnv;
    await configureDependencies(
      Env(
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

  Future<Result> query(String sql, Map<String, Object?> args) =>
      writer.execute(Sql.named(sql), parameters: args);

  Future<void> resetFixture() async {
    await writer.execute('''
TRUNCATE TABLE public.attention_occurrence, public.email_auth_transaction,
  public.invitation, public.beacon, public."user" CASCADE
''');
    for (final (slot, id) in [_author, _relay, _issuer].indexed) {
      await query(
        '''
INSERT INTO public."user" (id, display_name, public_key)
VALUES (@id, @name, @key)
''',
        {
          'id': id,
          'name': id == _issuer ? _issuerName : 'Garden volunteer',
          'key': pgTestPublicKey('requestInviteSignup', slot + 1),
        },
      );
    }
  }

  setUp(resetFixture);

  Future<bool> issuerCanRead() async {
    final rows = await query(
      'SELECT public.beacon_can_read_content(@request, @issuer)',
      {'request': _request, 'issuer': _issuer},
    );
    return switch (rows.single.single) {
      final bool allowed => allowed,
      final value => throw StateError(
        'Expected Boolean access result, got $value',
      ),
    };
  }

  Future<ServerException?> expireRequestForSignup() async {
    Future<Result> expire() => query(
      'UPDATE public.beacon SET expires_at = now() WHERE id = @request',
      {'request': _request},
    );

    try {
      await expire();
      return null;
    } on ServerException catch (error) {
      if (error.code != '23514' ||
          error.constraintName != _postExpiryConstraint) {
        rethrow;
      }

      // Let signup see the expired Request on the current baseline. Restore
      // the guard in this disposable database before the next test. The test
      // still requires the normal schema to admit the expired Request.
      final definition =
          (await query(
                '''
SELECT pg_get_constraintdef(oid) FROM pg_constraint
WHERE conrelid = 'public.beacon'::regclass AND conname = @constraint
''',
                {'constraint': _postExpiryConstraint},
              )).single.single!
              as String;
      await writer.execute(
        'ALTER TABLE public.beacon DROP CONSTRAINT $_postExpiryConstraint',
      );
      addTearDown(() async {
        await query(
          'UPDATE public.beacon SET expires_at = NULL WHERE id = @request',
          {'request': _request},
        );
        await writer.execute(
          'ALTER TABLE public.beacon '
          'ADD CONSTRAINT $_postExpiryConstraint $definition',
        );
      });
      await expire();
      return error;
    }
  }

  Future<String> issueInvite({bool withParentChain = true}) async {
    await query(
      '''
INSERT INTO public.beacon (id, user_id, title, description, status, kind,
  forward_policy, is_discoverable, published_at)
VALUES (@request, @author, @title, 'Help planting seedlings', @status, @kind,
  @policy, @discoverable, now())
''',
      {
        'request': _request,
        'author': _author,
        'title': _requestTitle,
        'status': BeaconStatus.open.smallintValue,
        'kind': BeaconKind.request.value,
        'policy': BeaconForwardPolicyValue.open.value,
        'discoverable': !withParentChain,
      },
    );
    if (withParentChain) {
      await query(
        '''
INSERT INTO public.beacon_forward_edge
  (id, beacon_id, sender_id, recipient_id, parent_edge_id)
VALUES (@ancestor, @request, @author, @relay, NULL),
       (@parent, @request, @relay, @issuer, @ancestor)
''',
        {
          'ancestor': _ancestor,
          'parent': _parent,
          'request': _request,
          'author': _author,
          'relay': _relay,
          'issuer': _issuer,
        },
      );
    } else {
      await query(
        '''
INSERT INTO public.vote_user (subject, object, amount)
VALUES (@author, @issuer, 1), (@issuer, @author, 1)
''',
        {'author': _author, 'issuer': _issuer},
      );
    }
    final invite = await getIt<InvitationCase>().create(
      userId: _issuer,
      addresseeName: _joinerName,
      beaconId: _request,
    );
    expect(
      await query(
        'SELECT parent_forward_edge_id FROM public.invitation WHERE id = @id',
        {'id': invite.id},
      ),
      [
        [if (withParentChain) _parent else null],
      ],
      reason: 'The invitation captures the issuer’s inbound forward, if any',
    );
    return invite.id;
  }

  Future<String> signUp(_SignupMethod method, String invite) async {
    final auth = getIt<AuthCase>();
    final String token;
    switch (method) {
      case _SignupMethod.deviceKey:
        final authRequest =
            JWT({
              AuthRequestIntent.keyPublicKey: devicePublicKey,
            }).sign(
              EdDSAPrivateKey.fromPEM(
                Env.kJwtPrivateKey.replaceAll(r'\n', '\n'),
              ),
              algorithm: JWTAlgorithm.EdDSA,
              expiresIn: const Duration(minutes: 5),
            );
        final jwt = await auth.signUpWithInvite(
          authRequestToken: authRequest,
          invitationId: invite,
          displayName: _joinerName,
        );
        token = jwt.rawToken;
      case _SignupMethod.emailCredential:
        final magicLinkToken = await getIt<EmailAuthTransactionRepositoryPort>()
            .create(
              normalizedEmail: _email,
              inviteCode: invite,
              expiresIn: const Duration(minutes: 5),
              userAgentHash: EmailAuthCase.hashFingerprint('test browser'),
              ipHash: EmailAuthCase.hashFingerprint('test IP'),
            );
        final confirmation = await getIt<EmailAuthCase>().confirm(
          magicLinkToken,
        );
        expect(confirmation, isA<EmailAuthLoginConfirmed>());
        final login = confirmation as EmailAuthLoginConfirmed;
        expect(login.isNewAccount, isTrue);
        final cookieName = getIt<SessionCase>().sessionCookieName();
        final response = await getIt<SessionController>().accessToken(
          Request(
            'POST',
            Uri.parse('http://127.0.0.1:2080/api/v2/session/access-token'),
            headers: {'cookie': '$cookieName=${login.sessionToken}'},
          ),
        );
        expect(response.statusCode, 200);
        final body =
            jsonDecode(await response.readAsString()) as Map<String, Object?>;
        token = body['access_token']! as String;
    }
    final joiner = auth.parseAndVerifyJwt(token: token).sub;
    final identityRows = await switch (method) {
      _SignupMethod.deviceKey => query(
        'SELECT id FROM public."user" WHERE public_key = @key',
        {'key': devicePublicKey},
      ),
      _SignupMethod.emailCredential => query(
        '''
SELECT u.id FROM public."user" u
JOIN public.account_credential c ON c.account_id = u.id
WHERE c.type = @type AND c.identifier = @email
''',
        {'type': CredentialType.emailOtp.wire, 'email': _email},
      ),
    };
    expect(identityRows, [
      [joiner],
    ], reason: 'The JWT belongs to the new account');
    expect(
      await query(
        '''
SELECT invited_id, invite_origin, accepted_at IS NOT NULL
FROM public.invitation WHERE id = @invite
''',
        {'invite': invite},
      ),
      [
        [joiner, 'new_account', true],
      ],
    );
    return joiner;
  }

  Future<Result> joinerForwards(String joiner) => query(
    '''
SELECT sender_id, parent_edge_id, cancelled_at IS NULL
FROM public.beacon_forward_edge
WHERE beacon_id = @request AND recipient_id = @joiner
''',
    {'request': _request, 'joiner': joiner},
  );

  Future<List<Map<String, Object?>>> receipts(
    String account, {
    String source = '',
  }) async {
    final rows = await query(
      '''
SELECT n.presentation_key, n.presentation_payload::text AS presentation_payload, n.kind,
       n.beacon_id, n.actor_user_id,
       jsonb_build_array(o.immutable_payload, r.role_facts, n.presentation_payload)::text
         AS event_facts
FROM public.notification_outbox n
JOIN public.attention_occurrence o ON o.id = n.occurrence_id
JOIN public.attention_occurrence_recipient r
  ON r.occurrence_id = o.id AND r.account_id = n.account_id
WHERE n.account_id = @account AND (@source = '' OR o.source_event_key = @source)
''',
      {'account': account, 'source': source},
    );
    return [for (final row in rows) row.toColumnMap()];
  }

  Future<String> renderCopy(
    Map<String, Object?> receipt,
    String account,
    String locale,
  ) async {
    final facts =
        jsonDecode(receipt['presentation_payload']! as String)
            as Map<String, Object?>;
    final identity = (await getIt<NotificationIdentityPort>().resolve(account, [
      IdentityRequest(
        beaconId: receipt['beacon_id'] as String? ?? '',
        actorId: receipt['actor_user_id'] as String?,
        relatedBeaconId: facts['relatedBeaconId'] as String?,
      ),
    ])).single;
    final copy = const NotificationCopyRenderer().render(
      presentationKey: receipt['presentation_key']! as String,
      facts: facts,
      kind: NotificationKind.values.byName(receipt['kind']! as String),
      identity: identity,
      locale: locale,
      tzOffsetMinutes: 0,
      now: DateTime.timestamp(),
    );
    return [
      copy.headline,
      copy.sentence,
      copy.entityLabel,
      copy.excerpt,
    ].nonNulls.join('\n');
  }

  Future<Map<String, Object?>> acceptedReceipt(
    String invite,
    String joiner,
  ) async {
    final key = 'invitation:$invite:accepted';
    expect(
      await query(
        '''
SELECT o.event_type, o.actor_user_id, r.account_id, r.role_facts->>'inviteOrigin'
FROM public.attention_occurrence o
JOIN public.attention_occurrence_recipient r ON r.occurrence_id = o.id
WHERE o.source_event_key = @source
''',
        {'source': key},
      ),
      [
        ['inviteAccepted', joiner, _issuer, 'new_account'],
      ],
    );
    final rows = await receipts(_issuer, source: key);
    expect(rows, hasLength(1));
    return rows.single;
  }

  Future<void> expectActiveInvite(_SignupMethod method) async {
    final invite = await issueInvite();
    final joiner = await signUp(method, invite);
    expect(await joinerForwards(joiner), [
      [_issuer, _parent, true],
    ]);
    final accepted = await acceptedReceipt(invite, joiner);
    expect(await renderCopy(accepted, _issuer, 'en'), isNot(matches(_lapseEn)));
    for (final receipt in await receipts(joiner)) {
      expect(await renderCopy(receipt, joiner, 'en'), isNot(matches(_lapseEn)));
    }
  }

  Future<void> expectLapsedInvite(_SignupMethod method, String invite) async {
    final joiner = await signUp(method, invite);
    final pair = {'issuer': _issuer, 'joiner': joiner};
    final votes = await query('''
SELECT subject, object, amount FROM public.vote_user
WHERE (subject = @issuer AND object = @joiner)
   OR (subject = @joiner AND object = @issuer)
''', pair);
    expect(
      votes.map((row) => (row[0], row[1])),
      unorderedEquals([(_issuer, joiner), (joiner, _issuer)]),
    );
    for (final vote in votes) {
      expect(vote[2], greaterThan(0));
    }
    expect(
      await joinerForwards(joiner),
      isEmpty,
      reason: 'A lapsed invite must never forward the Request to the joiner',
    );
    expect(
      await query(
        'SELECT 1 FROM public.attention_occurrence WHERE source_event_key = @key',
        {'key': 'invitation:$invite:forward'},
      ),
      isEmpty,
    );
    expect(
      await query(
        'SELECT 1 FROM public.inbox_item WHERE user_id = @joiner AND beacon_id = @request',
        {'joiner': joiner, 'request': _request},
      ),
      isEmpty,
    );

    final accepted = await acceptedReceipt(invite, joiner);
    expect(accepted['event_facts'], contains(_requestTitle));
    final cards = <Map<String, Object?>>[];
    for (final receipt in await receipts(joiner)) {
      if (receipt['actor_user_id'] != _issuer) continue;
      final copy = await renderCopy(receipt, joiner, 'en');
      if (copy.contains(_requestTitle) && _lapseEn.hasMatch(copy)) {
        cards.add(receipt);
      }
    }
    expect(
      cards,
      hasLength(1),
      reason: 'The joiner receives a Request-lapsed card from the issuer',
    );
    final card = cards.single;
    expect(card['event_facts'], contains(_requestTitle));
    for (final (locale, requestWord, lapse) in [
      ('en', RegExp(r'\brequest\b', caseSensitive: false), _lapseEn),
      ('ru', RegExp('запрос', caseSensitive: false), _lapseRu),
    ]) {
      final acceptedCopy = await renderCopy(accepted, _issuer, locale);
      final joinerCopy = await renderCopy(card, joiner, locale);
      expect(joinerCopy, contains(_issuerName));
      for (final copy in [acceptedCopy, joinerCopy]) {
        expect(copy, contains(_requestTitle), reason: locale);
        expect(copy, matches(requestWord), reason: locale);
        expect(copy, matches(lapse), reason: locale);
        expect(copy, isNot(matches(_placeholderName)), reason: locale);
      }
    }
  }

  for (final method in _SignupMethod.values) {
    group(method.label, () {
      test(
        'joins and connects with the issuer after the Request closes',
        () async {
          final invite = await issueInvite();
          await query(
            'UPDATE public.beacon SET status = @status WHERE id = @request',
            {'status': BeaconStatus.closed.smallintValue, 'request': _request},
          );
          expect(await issuerCanRead(), isTrue);
          await expectLapsedInvite(method, invite);
        },
      );

      test(
        'joins and connects with the issuer after the Request expires',
        () async {
          final invite = await issueInvite();
          final schemaRejection = await expireRequestForSignup();
          expect(
            await query(
              'SELECT status, expires_at <= now() FROM public.beacon WHERE id = @request',
              {'request': _request},
            ),
            [
              [BeaconStatus.open.smallintValue, true],
            ],
          );
          expect(await issuerCanRead(), isTrue);
          await expectLapsedInvite(method, invite);
          expect(
            schemaRejection,
            isNull,
            reason: 'The normal schema must admit the expired Request',
          );
        },
      );

      test(
        'joins and connects after the issuer loses access to the Request',
        () async {
          final invite = await issueInvite(withParentChain: false);
          await query(
            'UPDATE public.beacon SET is_discoverable = false WHERE id = @request',
            {'request': _request},
          );
          expect(
            await issuerCanRead(),
            isFalse,
            reason: 'The issuer only had discoverability access',
          );
          await expectLapsedInvite(method, invite);
        },
      );

      test(
        'joins and connects after the issuer loses the right to forward the Request',
        () async {
          final invite = await issueInvite();
          await query(
            'UPDATE public.beacon SET status = @status WHERE id = @request',
            {
              'status': BeaconStatus.reviewOpen.smallintValue,
              'request': _request,
            },
          );
          expect(await issuerCanRead(), isTrue);
          await expectLater(
            getIt<InvitationCase>().create(
              userId: _issuer,
              addresseeName: _joinerName,
              beaconId: _request,
            ),
            throwsA(isA<UnauthorizedException>()),
          );
          await expectLapsedInvite(method, invite);
        },
      );

      test(
        'forwards with an active chain and still joins after an ancestor is cancelled',
        () async {
          await expectActiveInvite(method);

          await resetFixture();
          final invite = await issueInvite();
          await query(
            'UPDATE public.beacon_forward_edge SET cancelled_at = now() WHERE id = @ancestor',
            {'ancestor': _ancestor},
          );
          expect(await issuerCanRead(), isTrue);
          expect(
            await query(
              'SELECT cancelled_at IS NULL FROM public.beacon_forward_edge WHERE id = @parent',
              {'parent': _parent},
            ),
            [
              [true],
            ],
            reason:
                'Only the grandparent of the prospective forward was cancelled',
          );
          await expectLapsedInvite(method, invite);
        },
      );
    });
  }
}
