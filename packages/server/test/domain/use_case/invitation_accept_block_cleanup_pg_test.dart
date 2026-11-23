@Tags(['pg', 'multi-connection'])
library;

import 'dart:async';

import 'package:injectable/injectable.dart' show Environment;
import 'package:postgres/postgres.dart';
import 'package:test/test.dart';

import 'package:tentura_server/app/di.dart';
import 'package:tentura_server/data/database/main_db_pool.dart';
import 'package:tentura_server/data/database/tentura_db.dart' hide isNull;
import 'package:tentura_server/domain/entity/beacon_kind.dart';
import 'package:tentura_server/domain/entity/invite_acceptance.dart';
import 'package:tentura_server/domain/exception.dart';
import 'package:tentura_server/domain/port/beacon_repository_port.dart';
import 'package:tentura_server/domain/use_case/invitation_case.dart';
import 'package:tentura_server/domain/use_case/user_block_case.dart';
import 'package:tentura_server/env.dart';

import '../../support/disposable_pg_target.dart';
import '../../support/pg_test_public_keys.dart';
import '../../support/pg_wait.dart';
import '../../support/session_database_di_harness.dart';

Future<void> main() async {
  final target = DisposablePgTarget.fromNamedEnvironment(
    envVarName: 'TENTURA_INVITATION_BLOCK_CLEANUP_TEST_DB',
    defaultNamePrefix: 'tentura_test_invitation_block_cleanup',
  );
  final pgSkip = await pgSkipReason(target);
  if (pgSkip != null) {
    test('Postgres unavailable', () {}, skip: pgSkip);
    return;
  }

  late Connection writer;
  late InvitationCase invitations;
  final queries = _AcceptanceQueries();
  var nextPair = 0;

  setUpAll(() async {
    final session = await setUpDisposablePgWriter(target: target);
    addTearDown(() => tearDownDisposablePgWriter(session: session));
    writer = session.writer;
    final db = target.databaseEnv;
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
      pgStatementTimeoutMs: kStableStateWait.inMilliseconds + 5000,
      printEnv: false,
      isDebugModeOn: false,
    );
    final previousWarning = driftRuntimeOptions.dontWarnAboutMultipleDatabases;
    driftRuntimeOptions.dontWarnAboutMultipleDatabases = true;
    addTearDown(() {
      driftRuntimeOptions.dontWarnAboutMultipleDatabases = previousWarning;
    });

    getIt
      ..skipDoubleRegistration = true
      ..registerFactory<TenturaDb>(
        () => TenturaDb.scoped(
          getIt<MainDbPool>(),
          scopeInterceptor: () => queries,
        ),
      );
    addTearDown(() async {
      getIt.skipDoubleRegistration = false;
      await getIt.reset();
    });
    await configureSessionDatabaseTestGraph(env);
    invitations = getIt<InvitationCase>();
  });

  setUp(() => queries.rollbacks = 0);

  Future<Result> query(String sql, Map<String, Object> args) =>
      writer.execute(Sql.named(sql), parameters: args);

  Future<_Pair> createInvite({required bool post}) async {
    final slot = nextPair++;
    final suffix = slot.toString().padLeft(9, '0');
    final inviter = 'Uba$suffix';
    final invitee = 'Ubb$suffix';
    await query(
      '''
INSERT INTO public."user" (id, display_name, public_key)
VALUES (@inviter, 'Inviter', @inviterKey), (@invitee, 'Invitee', @inviteeKey)
''',
      {
        'inviter': inviter,
        'invitee': invitee,
        'inviterKey': pgTestPublicKey('r${slot ~/ 4}', 2 * (slot % 4) + 1),
        'inviteeKey': pgTestPublicKey('r${slot ~/ 4}', 2 * (slot % 4) + 2),
      },
    );
    final beacon = post
        ? await getIt<BeaconRepositoryPort>().createBeacon(
            authorId: inviter,
            title: '',
            description: '',
            kind: BeaconKind.post,
            isDiscoverable: false,
          )
        : null;
    final invitation = await invitations.create(
      userId: inviter,
      addresseeName: 'Invitee',
      beaconId: beacon?.id,
    );
    return (inviter: inviter, invitee: invitee, invitation: invitation.id);
  }

  Future<Result> pairRows(_Pair pair) => query(
    '''
WITH pair(first_id, second_id) AS (
  VALUES (@inviter::text, @invitee::text), (@invitee::text, @inviter::text)
)
SELECT 'block', blocker_id, blocked_id FROM public.user_block
JOIN pair ON (blocker_id, blocked_id) = (first_id, second_id)
UNION ALL
SELECT 'contact', viewer_id, subject_id FROM public.user_contact
JOIN pair ON (viewer_id, subject_id) = (first_id, second_id)
UNION ALL
SELECT 'vote', subject, object FROM public.vote_user
JOIN pair ON (subject, object) = (first_id, second_id)
UNION ALL
SELECT 'active forward', sender_id, recipient_id FROM public.beacon_forward_edge
JOIN pair ON (sender_id, recipient_id) = (first_id, second_id)
WHERE cancelled_at IS NULL
UNION ALL
SELECT 'invitation', id, invited_id FROM public.invitation WHERE id = @invitation
''',
    {...pair.args, 'invitation': pair.invitation},
  );

  Future<void> block(_Pair pair) => getIt<UserBlockCase>().block(
    blockerId: pair.inviter,
    blockedId: pair.invitee,
    cascadeMode: 0,
  );

  Future<bool> waitForBlockOrLockWait(
    int acceptingPid,
    bool Function() done,
  ) async {
    final clock = Stopwatch()..start();
    while (!done()) {
      final waiting = await query(
        '''
SELECT EXISTS (
  SELECT 1 FROM pg_stat_activity
  WHERE datname = current_database() AND wait_event_type = 'Lock'
    AND @acceptingPid = ANY(pg_blocking_pids(pid))
)
''',
        {'acceptingPid': acceptingPid},
      );
      if (waiting.single.single == true) return true;
      if (clock.elapsed >= kStableStateWait) {
        fail('The block neither completed nor waited behind acceptance');
      }
      await Future<void>.delayed(const Duration(milliseconds: 20));
    }
    return false;
  }

  for (final post in [false, true]) {
    for (final byCode in [false, true]) {
      final friendship = !post || !byCode;
      group(
        '${post ? 'Post' : 'Plain'} invitation accepted ${byCode ? 'by code' : 'by ID'}',
        () {
          Future<InviteAcceptance> accept(_Pair pair) => byCode
              ? invitations.acceptAsExisting(
                  code: pair.invitation,
                  userId: pair.invitee,
                )
              : invitations.accept(
                  invitationId: pair.invitation,
                  userId: pair.invitee,
                );

          test(
            'A committed block rejects acceptance and leaves the invitation unclaimed',
            () async {
              final pair = await createInvite(post: post);
              await query('''
INSERT INTO public.user_contact (viewer_id, subject_id, contact_name)
VALUES (@invitee, @inviter, 'Saved inviter')
''', pair.args);
              final pause = _AcceptancePause(pair, afterBlockCheck: true);
              queries.pause = pause;
              final accepting = _outcome(accept(pair));
              late Object? acceptance;
              try {
                await pause.waitUntilReached(accepting);
                // The real initial lookup returned false. Keep it paused until the
                // block has committed and removed the pre-existing contact.
                await block(pair).timeout(kCompletionWait);
                expect(
                  await pairRows(pair),
                  unorderedEquals([
                    pair.blockRow,
                    pair.claimRow(null),
                  ]),
                );
              } finally {
                queries.pause = null;
                pause.release.complete();
                acceptance = await accepting.timeout(kCompletionWait);
              }

              expect(
                {
                  'acceptance': acceptance,
                  'rows': await pairRows(pair),
                  'transaction rollbacks': queries.rollbacks,
                },
                {
                  'acceptance': isA<IdNotFoundException>(),
                  'rows': unorderedEquals([pair.blockRow, pair.claimRow(null)]),
                  // Hiding the invitation can roll back the accepting transaction.
                  'transaction rollbacks': lessThanOrEqualTo(1),
                },
              );
            },
          );

          test(
            'A block waits for acceptance and removes the resulting pair data',
            () async {
              final pair = await createInvite(post: post);
              final pause = _AcceptancePause(pair, afterBlockCheck: false);
              queries.pause = pause;
              final accepting = _outcome(accept(pair));
              Future<Object?>? blocking;
              var blockDone = false;
              late bool blockWaited;
              late Object? acceptance;
              Object? blockResult;
              try {
                // The contact write has executed, and acceptance's transaction
                // still holds its locks. Start block on a different connection.
                final acceptingPid = await pause.waitUntilReached(accepting);
                blocking = _outcome(block(pair)).then((result) {
                  blockDone = true;
                  return result;
                });
                blockWaited = await waitForBlockOrLockWait(
                  acceptingPid,
                  () => blockDone,
                );
              } finally {
                queries.pause = null;
                pause.release.complete();
                final results = await Future.wait([
                  accepting,
                  ?blocking,
                ]).timeout(kCompletionWait);
                acceptance = results.first;
                if (blocking != null) blockResult = results.last;
              }

              expect(
                {
                  'acceptance': acceptance,
                  'block error': blockResult,
                  'block waited for acceptance': blockWaited,
                  'rows': await pairRows(pair),
                  'transaction rollbacks': queries.rollbacks,
                },
                {
                  'acceptance': InviteAcceptance.accepted,
                  'block error': isNull,
                  'block waited for acceptance': isTrue,
                  'rows': unorderedEquals([
                    pair.blockRow,
                    pair.claimRow(pair.invitee),
                  ]),
                  'transaction rollbacks': 0,
                },
              );
            },
          );

          test(
            post
                ? 'Acceptance without a block claims the invitation, saves a contact, and delivers the Post'
                : 'Acceptance without a block claims the invitation and saves a contact and reciprocal votes',
            () async {
              final pair = await createInvite(post: post);

              expect(
                await accept(pair).timeout(kCompletionWait),
                InviteAcceptance.accepted,
              );
              expect(
                await pairRows(pair),
                unorderedEquals([
                  pair.claimRow(pair.invitee),
                  ['contact', pair.inviter, pair.invitee],
                  if (friendship) ...[
                    ['vote', pair.inviter, pair.invitee],
                    ['vote', pair.invitee, pair.inviter],
                  ],
                  if (post) ['active forward', pair.inviter, pair.invitee],
                ]),
              );
            },
          );
        },
        timeout: const Timeout(Duration(seconds: 100)),
      );
    }
  }
}

typedef _Pair = ({String inviter, String invitee, String invitation});

extension on _Pair {
  Map<String, String> get args => {'inviter': inviter, 'invitee': invitee};

  Matcher get blockRow => equals(['block', inviter, invitee]);

  List<String?> claimRow(String? invitedId) => [
    'invitation',
    invitation,
    invitedId,
  ];
}

Future<Object?> _outcome<T>(Future<T> operation) async {
  try {
    return await operation;
  } on Object catch (error) {
    return error;
  }
}

final class _AcceptancePause {
  _AcceptancePause(this.pair, {required this.afterBlockCheck});

  final _Pair pair;
  final bool afterBlockCheck;
  final reached = Completer<int>();
  final release = Completer<void>();

  bool matches(List<Object?> args) =>
      !reached.isCompleted &&
      args.contains(pair.inviter) &&
      args.contains(pair.invitee);

  Future<int> waitUntilReached(Future<Object?> accepting) => Future.any([
    reached.future,
    accepting.then<int>(
      (result) =>
          fail('Acceptance finished before reaching the pause: $result'),
    ),
  ]).timeout(kStableStateWait);

  Future<void> hold(QueryExecutor executor) async {
    final rows = await executor.runSelect('SELECT pg_backend_pid() AS pid', []);
    reached.complete(rows.single['pid']! as int);
    await release.future.timeout(kStableStateWait + kCompletionWait);
  }
}

/// Pauses real SQL results without changing either use case or any row.
final class _AcceptanceQueries extends QueryInterceptor {
  _AcceptancePause? pause;
  // Check for failed transactions even when the use case retries them.
  int rollbacks = 0;

  @override
  Future<void> rollbackTransaction(TransactionExecutor inner) {
    rollbacks++;
    return super.rollbackTransaction(inner);
  }

  @override
  Future<List<Map<String, Object?>>> runSelect(
    QueryExecutor executor,
    String statement,
    List<Object?> args,
  ) async {
    final rows = await super.runSelect(executor, statement, args);
    final current = pause;
    if (current != null &&
        current.afterBlockCheck &&
        statement.startsWith('SELECT public.block_hides(') &&
        current.matches(args) &&
        rows.single['hidden'] == false) {
      await current.hold(executor);
    }
    return rows;
  }

  @override
  Future<int> runInsert(
    QueryExecutor executor,
    String statement,
    List<Object?> args,
  ) async {
    final result = await super.runInsert(executor, statement, args);
    final current = pause;
    if (current != null &&
        !current.afterBlockCheck &&
        statement.startsWith('INSERT INTO "user_contact" ') &&
        current.matches(args)) {
      await current.hold(executor);
    }
    return result;
  }
}
