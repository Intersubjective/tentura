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
import 'package:tentura_server/domain/entity/jwt_entity.dart';
import 'package:tentura_server/domain/port/beacon_repository_port.dart';
import 'package:tentura_server/domain/use_case/auth_case.dart';
import 'package:tentura_server/domain/use_case/credential_auth_case.dart';
import 'package:tentura_server/domain/use_case/invitation_case.dart';
import 'package:tentura_server/env.dart';

import '../../support/disposable_pg_target.dart';
import '../../support/pg_test_public_keys.dart';

const _issuer = 'Uretryissuer1';
const _existingUser = 'Uretryaccept1';
const _displayName = 'New invitee';
const _email = 'invite-retry@example.test';
const _deadlock = '40P01';
const _serializationFailure = '40001';
const _uniqueViolation = '23505';
// One initial attempt plus the existing retry helper's default single retry.
const _attemptBudget = 2;
const _callTimeout = Duration(seconds: 20);

Future<void> main() async {
  final target = DisposablePgTarget.fromNamedEnvironment(
    envVarName: 'TENTURA_INVITE_ACCEPT_RETRY_PG_TEST_DB',
    defaultNamePrefix: 'tentura_test_invite_accept_retry',
  );
  final pgSkip = await pgSkipReason(target);
  if (pgSkip != null) {
    test('Postgres unavailable', () {}, skip: pgSkip);
    return;
  }

  late DisposablePgWriterSession session;
  late Connection writer;
  late _InviteClaimFault fault;
  final devicePublicKey = base64UrlEncode(
    EdDSAPublicKey.fromPEM(Env.kJwtPublicKey.replaceAll(r'\n', '\n')).bytes,
  );
  final deviceRequest =
      JWT({
        AuthRequestIntent.keyPublicKey: devicePublicKey,
      }).sign(
        EdDSAPrivateKey.fromPEM(Env.kJwtPrivateKey.replaceAll(r'\n', '\n')),
        algorithm: JWTAlgorithm.EdDSA,
        expiresIn: const Duration(hours: 1),
      );

  setUpAll(() async {
    session = await setUpDisposablePgWriter(target: target);
    writer = session.writer;
    fault = _InviteClaimFault(writer);
    await fault.install();

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
TRUNCATE TABLE public.invite_claim_fault, public.attention_occurrence,
  public.invitation, public.beacon, public."user" CASCADE
''');
    for (final (slot, id) in [_issuer, _existingUser].indexed) {
      await writer.execute(
        Sql.named('''
INSERT INTO public."user" (id, display_name, public_key)
VALUES (@id, @name, @key)
'''),
        parameters: {
          'id': id,
          'name': id == _issuer ? 'Inviter' : 'Existing invitee',
          'key': pgTestPublicKey('inviteacceptretry', slot + 1),
        },
      );
    }
  });

  Future<Result> query(String sql, Map<String, Object?> values) =>
      writer.execute(Sql.named(sql), parameters: values);

  Future<String> createInvite({String? beaconId}) async =>
      (await getIt<InvitationCase>().create(
        userId: _issuer,
        addresseeName: _displayName,
        beaconId: beaconId,
      )).id;

  Future<String> createRequest() async =>
      (await getIt<BeaconRepositoryPort>().createBeacon(
        authorId: _issuer,
        title: 'Help with the community garden',
        description: 'Looking for help planting seedlings',
        kind: BeaconKind.request,
      )).id;

  Future<Result> requestForwards(String beaconId) => query(
    '''
SELECT sender_id, recipient_id, cancelled_at
FROM public.beacon_forward_edge WHERE beacon_id = @beacon
''',
    {'beacon': beaconId},
  );

  Future<JwtEntity> signUpWithDevice(String invitationId) => getIt<AuthCase>()
      .signUpWithInvite(
        authRequestToken: deviceRequest,
        invitationId: invitationId,
        displayName: _displayName,
      )
      .timeout(_callTimeout);

  Future<({String accountId, bool isNewAccount})> signUpWithEmail(
    String invitationId,
  ) => getIt<CredentialAuthCase>()
      .resolveOrCreate(
        type: CredentialType.emailOtp,
        identifier: _email,
        displayName: _displayName,
        inviteId: invitationId,
      )
      .timeout(_callTimeout);

  Future<void> expectInvitation(String invite, String? accepter) async {
    final rows = await query(
      '''
SELECT invited_id, accepted_at IS NOT NULL
FROM public.invitation
WHERE id = @id
''',
      {'id': invite},
    );
    expect(rows, [
      [accepter, accepter != null],
    ]);
  }

  Future<Result> newAccounts() => query(
    '''
SELECT id FROM public."user" WHERE id NOT IN (@issuer, @existing)
''',
    {'issuer': _issuer, 'existing': _existingUser},
  );

  Future<Result> deviceAccounts() => query(
    '''
SELECT id FROM public."user" WHERE public_key = @key
''',
    {'key': devicePublicKey},
  );

  Future<Result> credentialAccounts(CredentialType type, String identifier) =>
      query(
        '''
SELECT account_id FROM public.account_credential
WHERE type = @type AND identifier = @identifier
''',
        {'type': type.wire, 'identifier': identifier},
      );

  Future<Result> friendship() => query(
    '''
SELECT subject, object, amount FROM public.vote_user
WHERE (subject = @issuer AND object = @existing)
   OR (subject = @existing AND object = @issuer)
''',
    {'issuer': _issuer, 'existing': _existingUser},
  );

  Future<void> expectEvent({
    required String sourceKey,
    required String type,
    required String actor,
    required String recipient,
  }) async {
    final rows = await query(
      '''
SELECT o.event_type, o.actor_user_id, r.account_id
FROM public.attention_occurrence o
LEFT JOIN public.attention_occurrence_recipient r ON r.occurrence_id = o.id
WHERE o.source_event_key = @key
''',
      {'key': sourceKey},
    );
    expect(rows, [
      [type, actor, recipient],
    ], reason: 'Expected one attention event and its recipient for $sourceKey');
  }

  Future<void> expectInviteAccepted(String invite, String accepter) =>
      expectEvent(
        sourceKey: 'invitation:$invite:accepted',
        type: 'inviteAccepted',
        actor: accepter,
        recipient: _issuer,
      );

  Future<void> expectUnaccepted(String invite) async {
    await expectInvitation(invite, null);
    expect(
      await query(
        '''
SELECT source_event_key FROM public.attention_occurrence
WHERE source_event_key LIKE @prefix
''',
        {'prefix': 'invitation:$invite:%'},
      ),
      isEmpty,
    );
  }

  Future<void> expectUniqueViolationWithoutRetry(
    String invite,
    Future<Object> Function(String) accept,
  ) async {
    // Fail only the first claim so an incorrect retry would succeed.
    await fault.arm(invite, _uniqueViolation);
    await expectLater(accept(invite), _throwsSqlState(_uniqueViolation));
    expect(await fault.attempts(), 1);
    await expectUnaccepted(invite);
  }

  Future<void> expectDeviceSignup(String invite, JwtEntity jwt) async {
    final verified = getIt<AuthCase>().parseAndVerifyJwt(token: jwt.rawToken);
    expect(verified.sub, jwt.sub);
    expect(await newAccounts(), [
      [verified.sub],
    ]);
    expect(await deviceAccounts(), [
      [verified.sub],
    ]);
    expect(
      await credentialAccounts(CredentialType.ed25519Device, devicePublicKey),
      [
        [verified.sub],
      ],
    );
    await expectInvitation(invite, verified.sub);
    await expectInviteAccepted(invite, verified.sub);
  }

  group('Device signup through an invitation', () {
    test(
      'surfaces a unique violation immediately and recovers from a deadlock',
      () async {
        final invite = await createInvite();

        await expectUniqueViolationWithoutRetry(invite, signUpWithDevice);
        expect(await deviceAccounts(), isEmpty);
        expect(
          await credentialAccounts(
            CredentialType.ed25519Device,
            devicePublicKey,
          ),
          isEmpty,
        );

        await fault.arm(invite, _deadlock);
        final jwt = await signUpWithDevice(invite);
        expect(await fault.attempts(), _attemptBudget);
        await expectDeviceSignup(invite, jwt);
      },
    );

    test(
      'recovers from a serialization failure with one account and receipt',
      () async {
        final invite = await createInvite();
        await fault.arm(invite, _serializationFailure);

        final jwt = await signUpWithDevice(invite);

        expect(await fault.attempts(), _attemptBudget);
        await expectDeviceSignup(invite, jwt);
      },
    );

    test(
      'forwards the Request and records its receipt once after a deadlock',
      () async {
        final request = await createRequest();
        final invite = await createInvite(beaconId: request);
        await fault.arm(invite, _deadlock);

        final jwt = await signUpWithDevice(invite);

        expect(await fault.attempts(), _attemptBudget);
        await expectDeviceSignup(invite, jwt);
        expect(await requestForwards(request), [
          [_issuer, jwt.sub, null],
        ]);
        await expectEvent(
          sourceKey: 'invitation:$invite:forward',
          type: 'relayReceived',
          actor: _issuer,
          recipient: jwt.sub,
        );
      },
    );

    test(
      'rethrows a persistent deadlock after one retry and rolls back signup',
      () async {
        final request = await createRequest();
        final invite = await createInvite(beaconId: request);
        await fault.arm(invite, _deadlock, everyAttempt: true);

        await expectLater(signUpWithDevice(invite), _throwsSqlState(_deadlock));

        await expectUnaccepted(invite);
        expect(await requestForwards(request), isEmpty);
        expect(await newAccounts(), isEmpty);
        expect(await deviceAccounts(), isEmpty);
        expect(
          await credentialAccounts(
            CredentialType.ed25519Device,
            devicePublicKey,
          ),
          isEmpty,
        );
        expect(await fault.attempts(), _attemptBudget);
      },
    );
  });

  group('Email credential signup through an invitation', () {
    Future<void> expectSuccessfulSignup(String invite) async {
      final result = await signUpWithEmail(invite);
      expect(await fault.attempts(), _attemptBudget);
      expect(result.isNewAccount, isTrue);
      expect(await newAccounts(), [
        [result.accountId],
      ]);
      expect(
        await credentialAccounts(CredentialType.emailOtp, _email),
        [
          [result.accountId],
        ],
      );
      await expectInvitation(invite, result.accountId);
      await expectInviteAccepted(invite, result.accountId);
    }

    test(
      'surfaces a unique violation immediately and recovers from a deadlock',
      () async {
        final invite = await createInvite();
        await expectUniqueViolationWithoutRetry(invite, signUpWithEmail);
        expect(await newAccounts(), isEmpty);
        expect(
          await credentialAccounts(CredentialType.emailOtp, _email),
          isEmpty,
        );

        await fault.arm(invite, _deadlock);
        await expectSuccessfulSignup(invite);
      },
    );

    test(
      'recovers from a serialization failure with one account, credential and receipt',
      () async {
        final invite = await createInvite();
        await fault.arm(invite, _serializationFailure);

        await expectSuccessfulSignup(invite);
      },
    );

    test(
      'rethrows a persistent deadlock after one retry and rolls back signup',
      () async {
        final invite = await createInvite();
        await fault.arm(invite, _deadlock, everyAttempt: true);

        await expectLater(signUpWithEmail(invite), _throwsSqlState(_deadlock));

        await expectUnaccepted(invite);
        expect(await newAccounts(), isEmpty);
        expect(
          await credentialAccounts(CredentialType.emailOtp, _email),
          isEmpty,
        );
        expect(await fault.attempts(), _attemptBudget);
      },
    );
  });

  group('Accepting an invitation with an existing account', () {
    for (final (label, accept, retryableErrors) in [
      (
        'Invite link confirmation',
        (String invite) => getIt<InvitationCase>()
            .acceptAsExisting(
              code: invite,
              userId: _existingUser,
            )
            .timeout(_callTimeout),
        {'a deadlock': _deadlock},
      ),
      (
        'Invitation acceptance mutation',
        (String invite) => getIt<InvitationCase>()
            .accept(
              invitationId: invite,
              userId: _existingUser,
            )
            .timeout(_callTimeout),
        {
          'a deadlock': _deadlock,
          'a serialization failure': _serializationFailure,
        },
      ),
    ]) {
      group(label, () {
        for (final error in retryableErrors.entries) {
          final isDeadlock = error.value == _deadlock;
          test(
            isDeadlock
                ? 'surfaces a unique violation immediately and connects once after a deadlock'
                : 'recovers from ${error.key} and connects the users once',
            () async {
              final invite = await createInvite();
              if (isDeadlock) {
                await expectUniqueViolationWithoutRetry(invite, accept);
              }
              expect(await friendship(), isEmpty);
              await fault.arm(invite, error.value);

              expect(await accept(invite), isTrue);
              expect(await fault.attempts(), _attemptBudget);
              await expectInvitation(invite, _existingUser);
              expect(
                await friendship(),
                unorderedEquals([
                  [_issuer, _existingUser, 1],
                  [_existingUser, _issuer, 1],
                ]),
              );
              await expectInviteAccepted(invite, _existingUser);
              await expectEvent(
                sourceKey: 'invitation:$invite:mutual',
                type: 'mutualConnectionFormed',
                actor: _issuer,
                recipient: _existingUser,
              );
            },
          );
        }

        test(
          'rethrows a persistent deadlock after one retry without connecting',
          () async {
            final invite = await createInvite();
            await fault.arm(invite, _deadlock, everyAttempt: true);

            await expectLater(accept(invite), _throwsSqlState(_deadlock));

            await expectUnaccepted(invite);
            expect(await friendship(), isEmpty);
            expect(await fault.attempts(), _attemptBudget);
          },
        );
      });
    }
  });
}

Matcher _throwsSqlState(String code) => throwsA(
  isA<ServerException>()
      .having((error) => error.code, 'SQLSTATE', code)
      .having((error) => error.message, 'message', 'test invite claim failure'),
);

/// Count claims even when they roll back. Defer the fault until commit so
/// account, friendship, forwarding and attention writes have already run.
class _InviteClaimFault {
  _InviteClaimFault(this._writer);

  final Connection _writer;

  Future<void> install() async {
    await _writer.execute('CREATE SEQUENCE public.invite_claim_attempts');
    await _writer.execute('''
CREATE TABLE public.invite_claim_fault (
  invite_id text PRIMARY KEY,
  sql_state text NOT NULL,
  every_attempt boolean NOT NULL
)
''');
    await _writer.execute(r'''
CREATE FUNCTION public.fail_invite_claim() RETURNS trigger
LANGUAGE plpgsql AS $$
DECLARE
  fault public.invite_claim_fault%ROWTYPE;
  attempt bigint;
BEGIN
  SELECT * INTO fault FROM public.invite_claim_fault WHERE invite_id = NEW.id;
  IF NOT FOUND THEN
    RETURN NEW;
  END IF;
  attempt := nextval('public.invite_claim_attempts');
  IF attempt = 1 OR fault.every_attempt THEN
    RAISE EXCEPTION USING ERRCODE = fault.sql_state,
      MESSAGE = 'test invite claim failure';
  END IF;
  RETURN NEW;
END;
$$
''');
    await _writer.execute('''
CREATE CONSTRAINT TRIGGER fail_invite_claim
AFTER UPDATE ON public.invitation
DEFERRABLE INITIALLY DEFERRED
FOR EACH ROW
WHEN (OLD.invited_id IS NULL AND NEW.invited_id IS NOT NULL)
EXECUTE FUNCTION public.fail_invite_claim()
''');
  }

  Future<void> arm(
    String invite,
    String sqlState, {
    bool everyAttempt = false,
  }) async {
    await _writer.execute(
      'ALTER SEQUENCE public.invite_claim_attempts RESTART',
    );
    await _writer.execute(
      Sql.named('''
INSERT INTO public.invite_claim_fault (invite_id, sql_state, every_attempt)
VALUES (@invite, @state, @every)
ON CONFLICT (invite_id) DO UPDATE
SET sql_state = EXCLUDED.sql_state, every_attempt = EXCLUDED.every_attempt
'''),
      parameters: {'invite': invite, 'state': sqlState, 'every': everyAttempt},
    );
  }

  Future<int> attempts() async {
    final rows = await _writer.execute('''
SELECT CASE WHEN is_called THEN last_value ELSE 0 END
FROM public.invite_claim_attempts
''');
    return rows.single.single! as int;
  }
}
