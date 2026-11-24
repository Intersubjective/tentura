@Tags(['pg', 'multi-connection'])
library;

import 'dart:convert';

import 'package:dart_jsonwebtoken/dart_jsonwebtoken.dart';
import 'package:drift/drift.dart' show driftRuntimeOptions;
import 'package:injectable/injectable.dart' show Environment;
import 'package:postgres/postgres.dart';
import 'package:shelf_plus/shelf_plus.dart' show Handler, Request;
import 'package:tentura_root/domain/entity/auth_request_intent.dart';
import 'package:test/test.dart';

import 'package:tentura_server/api/root_router.dart';
import 'package:tentura_server/app/di.dart';
import 'package:tentura_server/domain/entity/account_credential_entity.dart';
import 'package:tentura_server/domain/entity/invite_acceptance.dart';
import 'package:tentura_server/domain/entity/invite_preview_result.dart';
import 'package:tentura_server/domain/port/phantom_merge_wake_port.dart';
import 'package:tentura_server/domain/use_case/auth_case.dart';
import 'package:tentura_server/domain/use_case/credential_auth_case.dart';
import 'package:tentura_server/domain/use_case/invitation_case.dart';
import 'package:tentura_server/env.dart';

import '../../../support/disposable_pg_target.dart';
import '../../../support/pg_test_public_keys.dart';
import '../../../support/session_database_di_harness.dart';

const _issuer = 'U781a00000001';
const _issuerName = 'Invite issuer';
const _joiner = 'U781a00000002';
const _otherJoiner = 'U781a00000003';
const _person = 'PH781a00000001';
const _personName = 'Private map name';
const _personEmoji = '🪁';
const _privateTagId = 'T781a00000001';
const _privateTagName = 'Private map tag';
const _addresseeName = 'Private invite name';
const _ordinaryName = 'Ordinary contact name';
const _origin = 'http://127.0.0.1:2080';
const _commitFailure = 'Invite claim rejected at commit';

Future<void> main() async {
  final target = DisposablePgTarget.fromNamedEnvironment(
    envVarName: 'TENTURA_PHANTOM_INVITE_ACCEPTANCE_PG_TEST_DB',
    defaultNamePrefix: 'tentura_test_phantom_invite_accept',
  );
  final skip = await pgSkipReason(target);

  group('Accepting invitations for people not on Tentura yet', () {
    late _Fixtures fixtures;
    late _MergeWakeSpy mergeWake;
    late AuthCase auth;
    late CredentialAuthCase credentialAuth;
    late InvitationCase invitations;
    late Handler handler;

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
      mergeWake = _MergeWakeSpy(session.writer);
      getIt.registerSingleton<PhantomMergeWakePort>(mergeWake);

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
          workersCount: 1,
          printEnv: false,
          isDebugModeOn: false,
          isNeedInvite: true,
        ),
      );
      auth = getIt<AuthCase>();
      credentialAuth = getIt<CredentialAuthCase>();
      invitations = getIt<InvitationCase>();
      handler = (await getIt.getAsync<RootRouter>()).routeHandler();
    });

    setUp(() async {
      await fixtures.reset();
      mergeWake.calls.clear();
    });

    Future<void> acceptByCode(String code, String userId) async {
      expect(
        await invitations.acceptAsExisting(code: code, userId: userId),
        InviteAcceptance.accepted,
      );
    }

    Future<void> acceptByMutation(String code, String userId) async {
      final reply = await handler(
        Request(
          'POST',
          Uri.parse('$_origin/api/v2/graphql'),
          headers: {
            'authorization': 'Bearer ${auth.issueAccessToken(userId).rawToken}',
            'content-type': 'application/json',
          },
          body: jsonEncode({
            'query':
                r'mutation Accept($id: String!) { invitationAccept(id: $id) }',
            'variables': {'id': code},
          }),
        ),
      );
      final body = await reply.readAsString();
      expect(reply.statusCode, 200, reason: body);
      expect(jsonDecode(body), {
        'data': {'invitationAccept': true},
      });
    }

    Future<String> signUpWithCredential(String code) async {
      final result = await credentialAuth.resolveOrCreate(
        type: CredentialType.emailOtp,
        identifier: 'join-$code@example.test',
        displayName: 'New account',
        inviteId: code,
      );
      expect(result.isNewAccount, isTrue);
      return result.accountId;
    }

    Future<String> signUpWithDevice(String code) async {
      final devicePublicKey = EdDSAPublicKey.fromPEM(
        Env.kJwtPublicKey.replaceAll(r'\n', '\n'),
      );
      final devicePrivateKey = EdDSAPrivateKey.fromPEM(
        Env.kJwtPrivateKey.replaceAll(r'\n', '\n'),
      );
      final token =
          JWT({
            AuthRequestIntent.keyPublicKey: base64UrlEncode(
              devicePublicKey.bytes,
            ),
            AuthRequestIntentSignUp.keyCode: code,
          }).sign(
            devicePrivateKey,
            algorithm: JWTAlgorithm.EdDSA,
            expiresIn: const Duration(minutes: 5),
          );

      final account = await auth.signUp(
        authRequestToken: token,
        displayName: 'New device account',
      );
      return account.sub;
    }

    test(
      'device signup consumes the invite and queues a new-account merge',
      () async {
        final code = await fixtures.seedInvite();
        final account = await signUpWithDevice(code);

        await fixtures.expectQueuedMerge(code, account, origin: 1);
        await mergeWake.expectOnceAfterCommit(code);
      },
    );

    test(
      'ordinary device signup preserves the contact without waking a merge',
      () async {
        final code = await fixtures.seedInvite(linked: false);
        final account = await signUpWithDevice(code);

        await fixtures.expectOrdinaryAcceptance(code, account);
        expect(mergeWake.calls, isEmpty);
      },
    );

    test(
      'credential signup queues a merge for a linked invite and saves the contact for an ordinary invite',
      () async {
        final ordinary = await fixtures.seedInvite(linked: false);
        final ordinaryAccount = await signUpWithCredential(ordinary);
        await fixtures.expectOrdinaryAcceptance(ordinary, ordinaryAccount);
        expect(mergeWake.calls, isEmpty);

        final linked = await fixtures.seedInvite();
        final linkedAccount = await signUpWithCredential(linked);

        await fixtures.expectQueuedMerge(linked, linkedAccount, origin: 1);
        await mergeWake.expectOnceAfterCommit(linked);
      },
    );

    for (final entrypoint in {
      'accepting by invite code': acceptByCode,
      'accepting through the invitation mutation': acceptByMutation,
    }.entries) {
      group(entrypoint.key, () {
        final accept = entrypoint.value;

        test(
          'creates mutual trust and queues a merge for a linked invite',
          () async {
            final ordinary = await fixtures.seedInvite(linked: false);
            await accept(ordinary, _otherJoiner);
            await fixtures.expectOrdinaryAcceptance(ordinary, _otherJoiner);
            expect(mergeWake.calls, isEmpty);

            final code = await fixtures.seedInvite();
            expect(await fixtures.votes(_joiner), isEmpty);
            await accept(code, _joiner);

            await fixtures.expectQueuedMerge(code, _joiner, origin: 2);
            await mergeWake.expectOnceAfterCommit(code);
          },
        );

        test(
          'consumes the invite and queues a merge when trust is already mutual',
          () async {
            await fixtures.seedMutualTrust();
            final code = await fixtures.seedInvite();

            await accept(code, _joiner);

            await fixtures.expectQueuedMerge(code, _joiner, origin: 2);
            await mergeWake.expectOnceAfterCommit(code);
          },
        );
      });
    }

    group('When invite acceptance rolls back at commit', () {
      for (final entrypoint in <String, Future<Object?> Function(String)>{
        'device signup': signUpWithDevice,
        'credential signup': signUpWithCredential,
        'accepting by invite code': (code) =>
            invitations.acceptAsExisting(code: code, userId: _joiner),
        'accepting through the invitation mutation case': (code) =>
            invitations.accept(invitationId: code, userId: _joiner),
      }.entries) {
        test('${entrypoint.key} leaves the merge worker asleep', () async {
          final code = await fixtures.seedInvite();
          await fixtures.rejectInviteClaimAtCommit();

          await expectLater(
            entrypoint.value(code),
            throwsA(
              isA<ServerException>().having(
                (error) => error.message,
                'message',
                _commitFailure,
              ),
            ),
          );
          expect(mergeWake.calls, isEmpty);
          expect(await fixtures.mergeJobs(), isEmpty);
        });
      }
    });

    test(
      'an existing queued merge survives a second accept and the second accepter gets mutual trust',
      () async {
        final previous = await fixtures.seedInvite(claimant: _otherJoiner);
        await fixtures.seedQueuedMerge(previous, _otherJoiner);
        final code = await fixtures.seedInvite();
        expect(code, isNot(previous));
        final priorJobs = await fixtures.mergeJobs();
        expect(priorJobs, [
          [_person, _issuer, _otherJoiner, previous, 2, 'queued'],
        ]);
        expect(
          await fixtures.invitePhantomId(code),
          priorJobs.single[0],
          reason: 'The new invite shares the queued job’s phantom key',
        );
        expect(await fixtures.votes(_joiner), isEmpty);

        await acceptByCode(code, _joiner);

        await fixtures.expectClaimAndTrust(code, _joiner);
        final jobs = await fixtures.mergeJobs();
        expect(jobs, hasLength(1));
        expect(jobs, priorJobs);
        expect(
          await fixtures.contactNames(_joiner),
          isEmpty,
          reason:
              'Accept leaves the contact name to the merge, even when a job is already queued',
        );
      },
    );

    test(
      'invite previews keep map details private and let mutual friends accept a linked invite',
      () async {
        await fixtures.seedMutualTrust();
        await fixtures.seedPrivateTag();
        final ordinary = await fixtures.seedInvite(linked: false);
        final linked = await fixtures.seedInvite();

        final ordinaryAnonymous = (await invitations.preview(
          code: ordinary,
        )).toJson();
        final ordinaryFriend = (await invitations.preview(
          code: ordinary,
          callerUserId: _joiner,
        )).toJson();
        const inviter = {
          'id': _issuer,
          'displayName': _issuerName,
          'image': null,
        };
        expect(ordinaryAnonymous['inviter'], inviter);
        expect(ordinaryFriend['inviter'], inviter);
        expect(ordinaryFriend['callerStatus'], 'already-friends');
        expect(ordinaryFriend['suggestedAction'], 'already-friends');
        if (ordinaryFriend.containsKey('phantomInvite')) {
          expect(ordinaryFriend['phantomInvite'], isFalse);
        }

        final linkedAnonymous = (await invitations.preview(
          code: linked,
        )).toJson();
        final linkedFriend = await invitations.preview(
          code: linked,
          callerUserId: _joiner,
        );
        final linkedFriendJson = linkedFriend.toJson();

        for (final (caller, payload) in [
          ('anonymous', linkedAnonymous),
          ('mutual friend', linkedFriendJson),
        ]) {
          final encoded = jsonEncode(payload);
          for (final (detail, value) in const [
            ('phantom id', _person),
            ('map name', _personName),
            ('invite addressee name', _addresseeName),
            ('emoji', _personEmoji),
            ('tag id', _privateTagId),
            ('tag name', _privateTagName),
          ]) {
            expect(
              encoded,
              isNot(contains(value)),
              reason: 'The $caller preview must hide the $detail',
            );
          }
          // Check both payloads before asserting routing so a privacy failure
          // is visible even when the mutual-friend status is still wrong.
          expect(
            {...payload}
              ..remove('callerStatus')
              ..remove('suggestedAction')
              ..remove('phantomInvite'),
            {'inviter': inviter, 'codeStatus': 'available'},
            reason:
                'The $caller preview must omit private fields, including notes',
          );
        }

        if (linkedAnonymous.containsKey('phantomInvite')) {
          expect(linkedAnonymous['phantomInvite'], isTrue);
        }
        expect(linkedAnonymous['callerStatus'], 'anonymous');
        expect(linkedAnonymous['suggestedAction'], 'accept-as-new');
        expect(
          {
            'status': linkedFriend.callerStatus,
            'callerStatus': linkedFriendJson['callerStatus'],
            'suggestedAction': linkedFriendJson['suggestedAction'],
            'phantomInvite': linkedFriendJson['phantomInvite'],
          },
          {
            'status': InviteCallerStatus.existingUser,
            'callerStatus': 'existing-user',
            'suggestedAction': 'accept-as-existing',
            'phantomInvite': true,
          },
        );
      },
    );
  }, skip: skip);
}

final class _MergeWakeSpy implements PhantomMergeWakePort {
  _MergeWakeSpy(this._reader);

  // The fixture connection is separate from the case layer's transaction.
  final Connection _reader;
  final calls = <({String invitationId, Future<bool> commitVisible})>[];

  @override
  Future<void> wake(String invitationId) async {
    final commitVisible = _readCommittedClaimAndJob(invitationId);
    calls.add((invitationId: invitationId, commitVisible: commitVisible));
    await commitVisible;
  }

  Future<bool> _readCommittedClaimAndJob(String invitationId) async {
    final result = await _reader.execute(
      Sql.named('''
SELECT EXISTS (
  SELECT 1
  FROM public.invitation i
  JOIN public.phantom_merge_job j ON j.invitation_id = i.id
  WHERE i.id = @code AND i.accepted_at IS NOT NULL
    AND i.invited_id = j.user_id AND j.state = 'queued'
)
'''),
      parameters: {'code': invitationId},
    );
    return result.single.single == true;
  }

  Future<void> expectOnceAfterCommit(String invitationId) async {
    expect(calls.map((call) => call.invitationId), [invitationId]);
    expect(
      await calls.single.commitVisible,
      isTrue,
      reason: 'Wake must see the claimed invitation and its queued job',
    );
  }
}

final class _Fixtures {
  const _Fixtures(this._writer);

  final Connection _writer;

  Future<Result> _sql(String statement, Map<String, Object?> parameters) =>
      _writer.execute(Sql.named(statement), parameters: parameters);

  Future<Result> _ownerSql(
    String statement,
    Map<String, Object?> parameters,
  ) => _writer.executeWithOwnerScopes(
    [_issuer],
    Sql.named(statement),
    parameters: parameters,
  );

  Future<void> reset() async {
    await _writer.execute('TRUNCATE TABLE public."user" CASCADE');
    for (final (index, id) in [_issuer, _joiner, _otherJoiner].indexed) {
      await _sql(
        '''
INSERT INTO public."user" (id, display_name, public_key)
VALUES (@id, @name, @key)
''',
        {
          'id': id,
          'name': id == _issuer ? _issuerName : 'Existing account $index',
          'key': pgTestPublicKey('phantomacceptance', index + 1),
        },
      );
    }

    await _ownerSql(
      '''
INSERT INTO public.phantom (id, owner_id, display_name, emoji)
VALUES (@id, @owner, @name, @emoji)
''',
      {
        'id': _person,
        'owner': _issuer,
        'name': _personName,
        'emoji': _personEmoji,
      },
    );
  }

  Future<String> seedInvite({bool linked = true, String? claimant}) async {
    final result = await _ownerSql(
      '''
INSERT INTO public.invitation
  (user_id, phantom_id, addressee_name, invited_id, accepted_at, invite_origin)
VALUES (@owner, @person, @name, @claimant::text,
        CASE WHEN @claimant IS NOT NULL THEN now() END,
        CASE WHEN @claimant IS NOT NULL THEN 'existing_account' END)
RETURNING id
''',
      {
        'owner': _issuer,
        'person': linked ? _person : null,
        'name': linked ? _addresseeName : _ordinaryName,
        'claimant': claimant,
      },
    );
    return result.single.single! as String;
  }

  Future<String?> invitePhantomId(String code) async =>
      (await _sql(
            'SELECT phantom_id FROM public.invitation WHERE id = @code',
            {'code': code},
          )).single.single
          as String?;

  Future<void> rejectInviteClaimAtCommit() async {
    await _writer.execute('''
CREATE FUNCTION public.reject_invite_claim_at_commit() RETURNS trigger
LANGUAGE plpgsql AS \$\$
BEGIN
  RAISE EXCEPTION '$_commitFailure';
END;
\$\$
''');
    addTearDown(() async {
      await _writer.execute(
        'DROP FUNCTION public.reject_invite_claim_at_commit() CASCADE',
      );
    });
    await _writer.execute('''
CREATE CONSTRAINT TRIGGER reject_invite_claim_at_commit
AFTER UPDATE ON public.invitation
DEFERRABLE INITIALLY DEFERRED FOR EACH ROW
WHEN (NEW.invited_id IS NOT NULL)
EXECUTE FUNCTION public.reject_invite_claim_at_commit()
''');
  }

  Future<void> seedMutualTrust() async {
    await _sql(
      '''
INSERT INTO public.vote_user (subject, object, amount)
VALUES (@issuer, @joiner, 1), (@joiner, @issuer, 1)
''',
      {'issuer': _issuer, 'joiner': _joiner},
    );
  }

  Future<void> seedPrivateTag() async {
    await _ownerSql(
      '''
INSERT INTO public.person_tag (id, owner_id, name, glyph, color, ord)
VALUES (@tag, @owner, @name, 'T', 0, 0)
''',
      {'tag': _privateTagId, 'owner': _issuer, 'name': _privateTagName},
    );
    await _ownerSql(
      '''
INSERT INTO public.phantom_tag_member (tag_id, owner_id, phantom_id, source)
VALUES (@tag, @owner, @person, 0)
''',
      {'tag': _privateTagId, 'owner': _issuer, 'person': _person},
    );
  }

  Future<void> seedQueuedMerge(String code, String account) async {
    await _sql(
      '''
INSERT INTO public.phantom_merge_job
  (id, phantom_id, owner_id, user_id, origin, invitation_id, state)
VALUES ('PM781a00000001', @person, @issuer, @account, 2, @code, 'queued')
''',
      {'person': _person, 'issuer': _issuer, 'account': account, 'code': code},
    );
  }

  // This disposable database belongs to this file. Read all jobs so unexpected
  // jobs with incorrect invitation or person ids also fail the assertions.
  Future<Result> mergeJobs() => _writer.execute('''
SELECT phantom_id, owner_id, user_id, invitation_id, origin, state
FROM public.phantom_merge_job
''');

  Future<Result> contactNames(String account) => _sql(
    '''
SELECT contact_name FROM public.user_contact
WHERE viewer_id = @issuer AND subject_id = @account
''',
    {'issuer': _issuer, 'account': account},
  );

  Future<Result> votes(String account) => _sql(
    '''
SELECT subject, object, amount FROM public.vote_user
WHERE (subject = @issuer AND object = @account)
   OR (subject = @account AND object = @issuer)
''',
    {'issuer': _issuer, 'account': account},
  );

  Future<void> expectClaimAndTrust(String code, String account) async {
    final claim = await _sql(
      'SELECT invited_id, accepted_at FROM public.invitation WHERE id = @code',
      {'code': code},
    );
    expect(claim, [
      [account, isNotNull],
    ]);
    expect(
      await votes(account),
      unorderedEquals([
        [_issuer, account, 1],
        [account, _issuer, 1],
      ]),
    );
  }

  Future<void> expectQueuedMerge(
    String code,
    String account, {
    required int origin,
  }) async {
    await expectClaimAndTrust(code, account);
    expect(
      {'jobs': await mergeJobs(), 'contact names': await contactNames(account)},
      {
        'jobs': [
          [_person, _issuer, account, code, origin, 'queued'],
        ],
        'contact names': isEmpty,
      },
    );
  }

  Future<void> expectOrdinaryAcceptance(String code, String account) async {
    await expectClaimAndTrust(code, account);
    expect(await mergeJobs(), isEmpty);
    expect(await contactNames(account), [
      [_ordinaryName],
    ]);
  }
}
