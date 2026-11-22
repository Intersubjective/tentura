@Tags(['pg', 'multi-connection'])
library;

import 'dart:convert';

import 'package:dart_jsonwebtoken/dart_jsonwebtoken.dart';
import 'package:injectable/injectable.dart' show Environment;
import 'package:postgres/postgres.dart';
import 'package:test/test.dart';

import 'package:tentura_root/domain/entity/auth_request_intent.dart';
import 'package:tentura_root/domain/entity/beacon_status.dart';
import 'package:tentura_server/app/di.dart';
import 'package:tentura_server/data/database/tentura_db.dart';
import 'package:tentura_server/data/repository/invite_genealogy_repository.dart';
import 'package:tentura_server/data/repository/invite_seed_prompt_repository.dart';
import 'package:tentura_server/data/repository/user_block_repository.dart';
import 'package:tentura_server/data/repository/user_repository.dart';
import 'package:tentura_server/domain/entity/account_credential_entity.dart';
import 'package:tentura_server/domain/entity/beacon_kind.dart';
import 'package:tentura_server/domain/exception.dart';
import 'package:tentura_server/domain/port/user_repository_port.dart';
import 'package:tentura_server/domain/use_case/auth_case.dart';
import 'package:tentura_server/domain/use_case/beacon_case.dart';
import 'package:tentura_server/domain/use_case/credential_auth_case.dart';
import 'package:tentura_server/domain/use_case/invitation_case.dart';
import 'package:tentura_server/env.dart';

import '../../support/disposable_pg_target.dart';
import '../../support/pg_test_public_keys.dart';
import '../../support/pg_wait.dart';

const _inviter = 'U00000000001';
const _alice = 'U00000000002';
const _bob = 'U00000000003';
const _author = 'U00000000004';
const _firstInvite = 'I00000000001';
const _secondInvite = 'I00000000002';
const _draftInvite = 'I00000000003';
const _beacon = 'B00000000001';
const _draft = 'B00000000002';
const _parent = 'F00000000001';

const _holdInviterTicker =
    "SELECT 1 FROM public.user_vsids WHERE user_id = '$_inviter' FOR UPDATE";
const _holdParent =
    "SELECT 1 FROM public.beacon_forward_edge WHERE id = '$_parent' FOR NO KEY UPDATE";
const _holdHierarchy =
    "SELECT pg_advisory_xact_lock(hashtextextended('tentura.beacon_hierarchy.v1', 0))";
const _probeClaim =
    "SELECT id FROM public.invitation WHERE id = '$_firstInvite' FOR UPDATE NOWAIT";
const _probeUnclaimedInvite =
    "SELECT id FROM public.invitation WHERE id = '$_firstInvite' "
    'AND invited_id IS NULL AND accepted_at IS NULL FOR UPDATE NOWAIT';

Future<void> main() async {
  final target = DisposablePgTarget.fromNamedEnvironment(
    envVarName: 'TENTURA_INVITE_ACCEPT_CONCURRENCY_TEST_DB',
    defaultNamePrefix: 'tentura_test_invite_accept_concurrency',
  );
  final pgSkip = await pgSkipReason(target);
  if (pgSkip != null) {
    test('Postgres unavailable', () {}, skip: pgSkip);
    return;
  }

  late DisposablePgWriterSession session;
  late Connection writer;
  late Connection gate;
  late Connection parentGate;
  late TenturaDb recordingDb;
  late UserRepository recordingUsers;
  late UserRepositoryPort users;
  late InvitationCase invitations;
  final trustCalls = _TrustProjectionRecorder();
  final deviceKey = base64UrlEncode(
    EdDSAPublicKey.fromPEM(Env.kJwtPublicKey.replaceAll(r'\n', '\n')).bytes,
  );

  setUpAll(() async {
    session = await setUpDisposablePgWriter(target: target);
    writer = session.writer;
    final db = target.databaseEnv;
    gate = await Connection.open(
      db.pgEndpoint,
      settings: db.pgEndpointSettings,
    );
    parentGate = await Connection.open(
      db.pgEndpoint,
      settings: db.pgEndpointSettings,
    );
    final env = Env(
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
      maxConnectionCount: 4,
      printEnv: false,
      isDebugModeOn: false,
      isNeedInvite: true,
      genealogyNodeKeySecret: 'invite-accept-test-secret',
    );
    await configureDependencies(env);
    await getIt.allReady(ignorePendingAsyncCreation: true);
    users = getIt<UserRepositoryPort>();
    invitations = getIt<InvitationCase>();
    recordingDb = TenturaDb(env, scopeInterceptor: () => trustCalls);
    recordingUsers = UserRepository(
      env,
      recordingDb,
      InviteGenealogyRepository(
        env,
        recordingDb,
        UserBlockRepository(env, recordingDb),
      ),
      InviteSeedPromptRepository(recordingDb),
    );
    await writer.execute(_voteAuditSchema, queryMode: QueryMode.simple);
  });

  tearDownAll(() async {
    await recordingDb.close();
    await getIt.reset();
    await gate.close();
    await parentGate.close();
    await tearDownDisposablePgWriter(session: session);
  });

  setUp(() async {
    trustCalls.calls.clear();
    await writer.execute('''
TRUNCATE public.attention_occurrence, public.invitation, public.beacon, public."user",
  vote_insert_audit RESTART IDENTITY CASCADE
''');
    for (final (slot, id) in [_inviter, _alice, _bob, _author].indexed) {
      await writer.execute(
        Sql.named('''
INSERT INTO public."user" (id, display_name, public_key)
VALUES (@id, 'Existing account', @key)
'''),
        parameters: {
          'id': id,
          'key': pgTestPublicKey('inviteaccept', slot + 1),
        },
      );
    }
  });

  Future<Result> query(String sql, Map<String, Object?> args) =>
      writer.execute(Sql.named(sql), parameters: args);

  Future<void> invite(
    String id, {
    String issuer = _inviter,
    String? beacon,
    String? parent,
  }) => query(
    '''
INSERT INTO public.invitation (id, user_id, addressee_name, beacon_id, parent_forward_edge_id)
VALUES (@id, @issuer, 'Bob', @beacon, @parent)
''',
    {'id': id, 'issuer': issuer, 'beacon': beacon, 'parent': parent},
  );

  Future<void> makeBeacon(
    String id,
    BeaconKind kind, {
    bool draft = false,
  }) => query(
    '''
INSERT INTO public.beacon
  (id, user_id, title, description, status, kind, forward_policy, is_discoverable, published_at)
VALUES (@id, @author, '', '', @status, @kind, 1, false,
  CASE WHEN @draft::bool THEN NULL ELSE now() END)
''',
    {
      'id': id,
      'author': draft ? _inviter : _author,
      'status': (draft ? BeaconStatus.draft : BeaconStatus.open).smallintValue,
      'kind': kind.value,
      'draft': draft,
    },
  );

  Future<void> makeForwardedBeacon(BeaconKind kind) async {
    await makeBeacon(_beacon, kind);
    await query(
      '''
INSERT INTO public.beacon_forward_edge (id, beacon_id, sender_id, recipient_id)
VALUES (@id, @beacon, @author, @inviter)
''',
      {
        'id': _parent,
        'beacon': _beacon,
        'author': _author,
        'inviter': _inviter,
      },
    );
    await invite(_firstInvite, beacon: _beacon, parent: _parent);
  }

  Future<String> signUp(String code, {required bool device}) async {
    if (device) {
      final request = JWT({AuthRequestIntent.keyPublicKey: deviceKey}).sign(
        EdDSAPrivateKey.fromPEM(Env.kJwtPrivateKey.replaceAll(r'\n', '\n')),
        algorithm: JWTAlgorithm.EdDSA,
        expiresIn: const Duration(hours: 1),
      );
      return (await getIt<AuthCase>().signUpWithInvite(
        authRequestToken: request,
        invitationId: code,
        displayName: 'New account',
      )).sub;
    }
    final result = await getIt<CredentialAuthCase>().resolveOrCreate(
      type: CredentialType.emailOtp,
      identifier: '$code@example.test',
      displayName: 'New account',
      inviteId: code,
    );
    expect(result.isNewAccount, isTrue);
    return result.accountId;
  }

  Future<bool> accept(String code, String user) =>
      invitations.acceptAsExisting(code: code, userId: user);

  Future<void> vote(String subject, String object, {int amount = 1}) async {
    final connection = await Connection.open(
      target.databaseEnv.pgEndpoint,
      settings: target.databaseEnv.pgEndpointSettings,
    );
    try {
      await connection.execute(
        Sql.named('''
INSERT INTO public.vote_user (subject, object, amount)
VALUES (@subject, @object, @amount)
'''),
        parameters: {'subject': subject, 'object': object, 'amount': amount},
        timeout: kCompletionWait,
      );
    } finally {
      await connection.close();
    }
  }

  Future<T> behindLock<T>(
    String lock,
    int waiters,
    Future<T> Function() run, {
    Connection? blocker,
    Future<void> Function()? whileBlocked,
  }) async {
    Future<_Outcome<T>>? outcome;
    try {
      await (blocker ?? gate).runTx((tx) async {
        final blockerPid =
            (await tx.execute('SELECT pg_backend_pid()')).single.single! as int;
        await tx.execute(lock);
        outcome = _settle(run());
        final stopwatch = Stopwatch()..start();
        while (true) {
          // Count indirect waiters too. PostgreSQL can queue a second row
          // lock waiter behind the first instead of the original holder.
          final rows = await writer.execute(
            Sql.named('''
WITH RECURSIVE blocked(pid) AS (
  SELECT @blocker::int
  UNION
  SELECT activity.pid
  FROM pg_stat_activity activity
  JOIN blocked ON blocked.pid = ANY(pg_blocking_pids(activity.pid))
  WHERE activity.datname = current_database() AND activity.wait_event_type = 'Lock'
)
SELECT count(*) - 1 FROM blocked
'''),
            parameters: {'blocker': blockerPid},
            timeout: const Duration(seconds: 2),
          );
          if ((rows.single.single! as int) >= waiters) break;
          if (stopwatch.elapsed >= const Duration(seconds: 10)) {
            fail('Expected $waiters transactions to wait while holding $lock');
          }
          await Future<void>.delayed(const Duration(milliseconds: 20));
        }
        await whileBlocked?.call();
      });
    } on Object {
      await outcome?.timeout(kCompletionWait);
      rethrow;
    }
    return (await outcome!.timeout(kCompletionWait)).unwrap();
  }

  Future<bool> canLockNow(String sql) async {
    try {
      final rows = await writer.execute(sql);
      expect(rows, hasLength(1), reason: 'the row being probed must exist');
      return true;
    } on ServerException catch (error) {
      if (error.code != '55P03') rethrow;
      return false;
    }
  }

  Future<T> acceptPostBehindLocks<T>(
    Future<T> Function() consume, {
    required Future<void> Function() whileWaitingForParent,
  }) => behindLock(
    _holdParent,
    1,
    () => behindLock(
      _holdHierarchy,
      1,
      consume,
      whileBlocked: () async {
        expect(
          await canLockNow(_probeUnclaimedInvite),
          isTrue,
          reason:
              'the invite must stay unclaimed while waiting for the Post hierarchy lock',
        );
      },
    ),
    blocker: parentGate,
    whileBlocked: whileWaitingForParent,
  );

  Future<void> expectClaim(String code, String user, String origin) async {
    expect(
      await query(
        '''
SELECT invited_id, invite_origin, accepted_at IS NOT NULL
FROM public.invitation WHERE id = @code
''',
        {'code': code},
      ),
      [
        [user, origin, true],
      ],
    );
  }

  Future<void> expectContact(String inviter, String invitee) async {
    expect(
      await query(
        '''
SELECT contact_name FROM public.user_contact
WHERE viewer_id = @inviter AND subject_id = @invitee
''',
        {'inviter': inviter, 'invitee': invitee},
      ),
      [
        ['Bob'],
      ],
    );
  }

  Future<void> expectPair(String first, String second) async {
    final args = {'first': first, 'second': second};
    expect(
      await query('''
SELECT subject, object, amount FROM public.vote_user
WHERE (subject = @first AND object = @second)
   OR (subject = @second AND object = @first)
''', args),
      unorderedEquals(_orderedVotes(first, second)),
    );
    expect(
      await query('''
SELECT subject, object FROM public.user_trust_edge
WHERE (subject = @first AND object = @second)
   OR (subject = @second AND object = @first)
''', args),
      unorderedEquals([
        [first, second],
        [second, first],
      ]),
    );
  }

  Future<void> expectSignup(String code, String user) async {
    await expectClaim(code, user, 'new_account');
    await expectContact(_inviter, user);
    await expectPair(_inviter, user);
    expect(
      await query(
        '''
SELECT ancestor_user_id, descendant_user_id FROM public.invite_genealogy
WHERE invitation_id = @code
''',
        {'code': code},
      ),
      [
        [_inviter, user],
      ],
    );
    expect(
      await query(
        '''
SELECT state FROM public.invite_seed_prompt_state
WHERE inviter_user_id = @inviter AND invitee_user_id = @user
''',
        {'inviter': _inviter, 'user': user},
      ),
      [
        [0],
      ],
    );
  }

  Future<void> expectConcurrentVote() async {
    expect(
      await query(
        '''
SELECT amount FROM public.vote_user WHERE subject = @inviter AND object = @author
''',
        {'inviter': _inviter, 'author': _author},
      ),
      [
        [1],
      ],
    );
  }

  Future<void> expectForward(String recipient) async {
    expect(
      await query(
        '''
SELECT sender_id, recipient_id, parent_edge_id FROM public.beacon_forward_edge
WHERE beacon_id = @beacon AND recipient_id = @recipient AND cancelled_at IS NULL
''',
        {'beacon': _beacon, 'recipient': recipient},
      ),
      [
        [_inviter, recipient, _parent],
      ],
    );
  }

  Future<List<Object?>> voteStatements(String first, String second) async {
    // BEFORE ROW observes proposed rows even for ON CONFLICT DO NOTHING.
    // The AFTER STATEMENT marker delimits statements within each transaction.
    final rows = await query(
      '''
WITH events AS (
  SELECT *, count(*) FILTER (WHERE subject IS NULL) OVER (
    PARTITION BY xid ORDER BY seq ROWS BETWEEN UNBOUNDED PRECEDING AND 1 PRECEDING
  ) AS statement_no
  FROM vote_insert_audit
)
SELECT jsonb_agg(jsonb_build_array(subject, object, amount) ORDER BY seq)
FROM events
WHERE (subject = @first AND object = @second)
   OR (subject = @second AND object = @first)
GROUP BY xid, statement_no
ORDER BY min(seq)
''',
      {'first': first, 'second': second},
    );
    return [for (final row in rows) row.single];
  }

  Future<void> expectSingleVoteInsert(
    String first,
    String second, {
    int accepts = 1,
  }) async {
    expect(
      await voteStatements(first, second),
      [for (var i = 0; i < accepts; i++) _orderedVotes(first, second)],
      reason:
          'each accept inserts both votes in one statement, lowest subject id first',
    );
  }

  Future<void> expectContactBeforeVotes(String invitee) async {
    expect(
      await query(
        '''
SELECT bool_and(has_contact) FROM vote_insert_audit
WHERE (subject = @inviter AND object = @invitee)
   OR (subject = @invitee AND object = @inviter)
''',
        {'inviter': _inviter, 'invitee': invitee},
      ),
      [
        [true],
      ],
      reason: 'the invite contact must exist before the vote triggers run',
    );
  }

  Future<void> raceDraftDeletion<T>(Future<T> Function(String) consume) async {
    await makeBeacon(_draft, BeaconKind.post, draft: true);
    await invite(_draftInvite, beacon: _draft);
    final (acceptance, deletion) = await behindLock(
      _holdHierarchy,
      2,
      () async {
        final acceptance = _settle(consume(_draftInvite));
        final deletion = _settle(
          getIt<BeaconCase>().deleteById(beaconId: _draft, userId: _inviter),
        );
        return (await acceptance, await deletion);
      },
    );

    expect(deletion.unwrap(), isTrue);
    if (acceptance.error case final error?) {
      expect(
        error,
        anyOf(isA<IdNotFoundException>(), isA<PostNotOpenException>()),
        reason: 'an invite on a draft may be refused with a domain error',
      );
    }
    expect(
      await query('SELECT id FROM public.beacon WHERE id = @id', {
        'id': _draft,
      }),
      isEmpty,
    );
    expect(
      await query(
        '''
SELECT id FROM public.beacon_forward_edge WHERE beacon_id = @id AND cancelled_at IS NULL
''',
        {'id': _draft},
      ),
      isEmpty,
    );
  }

  for (final device in [true, false]) {
    final signup = device ? 'Device signup' : 'Credential signup';

    test('$signup and a concurrent inviter vote both commit', () async {
      await invite(_firstInvite);
      final user = await behindLock(_holdInviterTicker, 2, () async {
        final results = await Future.wait<Object?>([
          signUp(_firstInvite, device: device),
          vote(_inviter, _author).then((_) => null),
        ]);
        return results.first! as String;
      });

      await expectSignup(_firstInvite, user);
      await expectConcurrentVote();
      await expectSingleVoteInsert(_inviter, user);
      await expectContactBeforeVotes(user);
    });

    test(
      '$signup waits for the Post lock before claiming and preserves the forward',
      () async {
        await raceDraftDeletion((code) => signUp(code, device: device));
        await makeForwardedBeacon(BeaconKind.post);
        final forwards = <(String, String)>[];
        var generationAvailable = false;
        var claimAvailable = true;

        void recordForward(String beaconId, String recipient) =>
            forwards.add((beaconId, recipient));

        final user = await acceptPostBehindLocks(
          () => device
              ? users.createInvited(
                  invitationId: _firstInvite,
                  publicKey: pgTestPublicKey('inviteaccept', 8),
                  displayName: 'New account',
                  onPostForwardCreated: (beacon, recipient) async =>
                      recordForward(beacon.id, recipient),
                )
              : users.createInvitedWithCredential(
                  invitationId: _firstInvite,
                  type: CredentialType.emailOtp,
                  identifier: 'post-invite@example.test',
                  displayName: 'New account',
                  onPostForwardCreated: (beacon, recipient) async =>
                      recordForward(beacon.id, recipient),
                ),
          whileWaitingForParent: () async {
            claimAvailable = await canLockNow(_probeClaim);
            generationAvailable = await canLockNow(
              'SELECT id FROM public.visibility_trust_generation FOR UPDATE NOWAIT',
            );
          },
        );

        await expectSignup(_firstInvite, user.id);
        await expectForward(user.id);
        expect(forwards, [(_beacon, user.id)]);
        expect(
          claimAvailable,
          isFalse,
          reason: 'the signup claims before waiting on the parent',
        );
        expect(
          generationAvailable,
          isTrue,
          reason: 'trust must wait for the parent chain',
        );
        await expectSingleVoteInsert(_inviter, user.id);
        await expectContactBeforeVotes(user.id);
      },
    );
  }

  test(
    'Existing-account acceptance and a concurrent inviter vote both commit',
    () async {
      await invite(_firstInvite);
      await behindLock(_holdInviterTicker, 2, () async {
        final results = await Future.wait<Object?>([
          accept(_firstInvite, _alice),
          vote(_inviter, _author).then((_) => null),
        ]);
        expect(results.first, isTrue);
      });

      await expectClaim(_firstInvite, _alice, 'existing_account');
      await expectContact(_inviter, _alice);
      await expectPair(_inviter, _alice);
      await expectConcurrentVote();
      await expectSingleVoteInsert(_inviter, _alice);
      await expectContactBeforeVotes(_alice);
    },
  );

  test(
    'Different invites from one inviter can be accepted concurrently',
    () async {
      await invite(_firstInvite);
      await invite(_secondInvite);
      final results = await behindLock(
        _holdInviterTicker,
        2,
        () => Future.wait([
          accept(_firstInvite, _alice),
          accept(_secondInvite, _bob),
        ]),
      );

      expect(results, [true, true]);
      await expectClaim(_firstInvite, _alice, 'existing_account');
      await expectClaim(_secondInvite, _bob, 'existing_account');
      await expectPair(_inviter, _alice);
      await expectPair(_inviter, _bob);
      expect(
        [
          await voteStatements(_inviter, _alice),
          await voteStatements(_inviter, _bob),
        ],
        [
          [_orderedVotes(_inviter, _alice)],
          [_orderedVotes(_inviter, _bob)],
        ],
      );
    },
  );

  test(
    'Opposite-direction accepts claim both invites and share one vote pair',
    () async {
      await invite(_firstInvite);
      await invite(_secondInvite, issuer: _alice);
      final results = await behindLock(
        "SELECT id FROM public.invitation WHERE id IN ('$_firstInvite', '$_secondInvite') "
        'FOR NO KEY UPDATE',
        2,
        () => Future.wait([
          accept(_firstInvite, _alice),
          accept(_secondInvite, _inviter),
        ]),
      );

      expect(results, [true, true]);
      await expectClaim(_firstInvite, _alice, 'existing_account');
      await expectClaim(_secondInvite, _inviter, 'existing_account');
      await expectPair(_inviter, _alice);
      await expectSingleVoteInsert(_inviter, _alice, accepts: 2);
    },
  );

  test(
    'Friendship acceptance keeps existing votes and fills missing directions',
    () async {
      await invite(_firstInvite);
      await invite(_secondInvite);
      await vote(_inviter, _alice, amount: -1);
      await vote(_inviter, _bob, amount: -1);
      await vote(_bob, _inviter);
      await writer.execute('TRUNCATE vote_insert_audit RESTART IDENTITY');

      for (final (code, user) in [
        (_firstInvite, _alice),
        (_secondInvite, _bob),
      ]) {
        expect(
          await recordingDb.withMutatingUser(
            user,
            () => recordingUsers.bindMutual(
              invitationId: code,
              userId: user,
            ),
          ),
          isTrue,
        );
        await expectClaim(code, user, 'existing_account');
        expect(
          await query(
            '''
SELECT subject, object, amount FROM public.vote_user
WHERE (subject = @inviter AND object = @user)
   OR (subject = @user AND object = @inviter)
''',
            {'inviter': _inviter, 'user': user},
          ),
          unorderedEquals([
            [_inviter, user, -1],
            [user, _inviter, 1],
          ]),
        );
      }

      expect(
        [
          await voteStatements(_inviter, _alice),
          await voteStatements(_inviter, _bob),
        ],
        [
          [_orderedVotes(_inviter, _alice)],
          [_orderedVotes(_inviter, _bob)],
        ],
      );
    },
  );

  test(
    'Only the winner of a Request invite is admitted and the claim precedes the parent lock',
    () async {
      await makeForwardedBeacon(BeaconKind.request);
      var claimAvailable = true;
      final outcomes = await behindLock(
        _holdParent,
        2,
        () => Future.wait([
          _settle(accept(_firstInvite, _alice)),
          _settle(accept(_firstInvite, _bob)),
        ]),
        whileBlocked: () async {
          // A waiting loser can be queued on the claim after the reorder.
          // The winner already owns it by the time it waits on the parent.
          claimAvailable = await canLockNow(_probeClaim);
        },
      );

      final wins = [
        for (final (i, outcome) in outcomes.indexed)
          if (outcome.value == true) [_alice, _bob][i],
      ];
      expect(wins, hasLength(1));
      final winner = wins.single;
      final loser = winner == _alice ? _bob : _alice;
      final loserResult = outcomes[winner == _alice ? 1 : 0];
      if (loserResult.error case final error?) {
        expect(
          error,
          anyOf(isA<InvitationWrongException>(), isA<IdNotFoundException>()),
        );
      }
      await expectClaim(_firstInvite, winner, 'existing_account');
      await expectContact(_inviter, winner);
      await expectForward(winner);
      expect(
        await query(
          '''
SELECT id FROM public.beacon_forward_edge
WHERE beacon_id = @beacon AND recipient_id = @loser
''',
          {'beacon': _beacon, 'loser': loser},
        ),
        isEmpty,
      );
      expect(
        await query(
          '''
SELECT 1 FROM public.user_contact
WHERE (viewer_id = @inviter AND subject_id = @loser)
   OR (viewer_id = @loser AND subject_id = @inviter)
''',
          {'inviter': _inviter, 'loser': loser},
        ),
        isEmpty,
      );
      expect(
        await query(
          '''
SELECT subject, object FROM public.vote_user
WHERE (subject = @inviter AND object = @loser)
   OR (subject = @loser AND object = @inviter)
''',
          {'inviter': _inviter, 'loser': loser},
        ),
        isEmpty,
        reason: 'a losing accept must leave no vote in either direction',
      );

      await invite(_secondInvite, beacon: _beacon, parent: _parent);
      var forwards = 0;
      expect(
        await recordingDb.withMutatingUser(
          loser,
          () => recordingUsers.bindMutual(
            invitationId: _secondInvite,
            userId: loser,
            bindFriendship: false,
            onForwardCreated: () async => forwards++,
          ),
        ),
        isTrue,
      );
      await expectForward(loser);
      expect(forwards, 1);
      expect(
        await writer.execute('SELECT subject FROM public.vote_user'),
        isEmpty,
      );
      expect(
        await writer.execute('SELECT subject FROM vote_insert_audit'),
        isEmpty,
      );
      expect(
        trustCalls.calls,
        isEmpty,
        reason: 'Request admission makes no explicit trust projection',
      );
      expect(
        claimAvailable,
        isFalse,
        reason: 'the claim must be locked before the parent',
      );
    },
  );

  test(
    'Existing-account Post acceptance waits for the Post lock before claiming',
    () async {
      await raceDraftDeletion((code) => accept(code, _alice));
      await makeForwardedBeacon(BeaconKind.post);
      var claimAvailable = true;
      final accepted = await acceptPostBehindLocks(
        () => accept(_firstInvite, _bob),
        whileWaitingForParent: () async {
          claimAvailable = await canLockNow(_probeClaim);
        },
      );
      expect(accepted, isTrue);
      await expectClaim(_firstInvite, _bob, 'existing_account');
      await expectForward(_bob);
      expect(
        claimAvailable,
        isFalse,
        reason: 'the claim must be locked before the parent',
      );
    },
  );
}

List<List<Object>> _orderedVotes(String first, String second) {
  final subjects = [first, second]..sort();
  return [
    [subjects.first, subjects.last, 1],
    [subjects.last, subjects.first, 1],
  ];
}

typedef _Outcome<T> = ({T? value, Object? error, StackTrace? stack});

extension<T> on _Outcome<T> {
  T unwrap() {
    if (error case final error?) Error.throwWithStackTrace(error, stack!);
    return value as T;
  }
}

Future<_Outcome<T>> _settle<T>(Future<T> operation) async {
  try {
    return (value: await operation, error: null, stack: null);
  } on Object catch (error, stack) {
    return (value: null, error: error, stack: stack);
  }
}

final class _TrustProjectionRecorder extends QueryInterceptor {
  final calls = <String>[];

  @override
  Future<void> runCustom(
    QueryExecutor executor,
    String statement,
    List<Object?> args,
  ) {
    _record(statement);
    return super.runCustom(executor, statement, args);
  }

  @override
  Future<List<Map<String, Object?>>> runSelect(
    QueryExecutor executor,
    String statement,
    List<Object?> args,
  ) {
    _record(statement);
    return super.runSelect(executor, statement, args);
  }

  void _record(String statement) {
    if (statement.toLowerCase().contains('trust_project_pair')) {
      calls.add(statement);
    }
  }
}

const _voteAuditSchema = r'''
CREATE TABLE vote_insert_audit (
  seq bigint GENERATED ALWAYS AS IDENTITY,
  xid bigint NOT NULL DEFAULT txid_current(),
  subject text,
  object text,
  amount smallint,
  has_contact boolean
);

CREATE FUNCTION record_vote_insert() RETURNS trigger LANGUAGE plpgsql AS $$
BEGIN
  INSERT INTO vote_insert_audit (subject, object, amount, has_contact)
  VALUES (NEW.subject, NEW.object, NEW.amount, EXISTS (
    SELECT 1 FROM public.user_contact
    WHERE (viewer_id = NEW.subject AND subject_id = NEW.object)
       OR (viewer_id = NEW.object AND subject_id = NEW.subject)
  ));
  RETURN NEW;
END;
$$;

CREATE FUNCTION finish_vote_insert() RETURNS trigger LANGUAGE plpgsql AS $$
BEGIN
  INSERT INTO vote_insert_audit DEFAULT VALUES;
  RETURN NULL;
END;
$$;

CREATE TRIGGER test_vote_insert_row BEFORE INSERT ON public.vote_user
FOR EACH ROW EXECUTE FUNCTION record_vote_insert();

CREATE TRIGGER test_vote_insert_statement AFTER INSERT ON public.vote_user
FOR EACH STATEMENT EXECUTE FUNCTION finish_vote_insert();
''';
