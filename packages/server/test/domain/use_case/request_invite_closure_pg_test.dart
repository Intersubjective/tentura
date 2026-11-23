@Tags(['pg', 'multi-connection'])
library;

import 'dart:async';

import 'package:injectable/injectable.dart' show Environment;
import 'package:postgres/postgres.dart';
import 'package:test/test.dart';

import 'package:tentura_root/domain/entity/beacon_status.dart';
import 'package:tentura_server/app/di.dart';
import 'package:tentura_server/data/database/main_db_pool.dart';
import 'package:tentura_server/data/database/tentura_db.dart'
    hide isNotNull, isNull;
import 'package:tentura_server/domain/commitment/commitment_event_kind.dart';
import 'package:tentura_server/domain/entity/beacon_kind.dart';
import 'package:tentura_server/domain/entity/invite_acceptance.dart';
import 'package:tentura_server/domain/use_case/closure_case.dart';
import 'package:tentura_server/domain/use_case/invitation_case.dart';
import 'package:tentura_server/env.dart';

import '../../support/disposable_pg_target.dart';
import '../../support/pg_test_public_keys.dart';
import '../../support/pg_wait.dart';
import '../../support/session_database_di_harness.dart';

const _request = 'B1acce550001';
const _issuer = 'U1acce550001';
const _invitee = 'U1acce550002';
const _helpers = ['U1acce550003', 'U1acce550004', 'U1acce550005'];
const _origin = 'http://127.0.0.1:2080';

Future<void> main() async {
  final target = DisposablePgTarget.fromNamedEnvironment(
    envVarName: 'TENTURA_REQUEST_INVITE_CLOSURE_TEST_DB',
    defaultNamePrefix: 'tentura_test_request_invite_closure',
  );
  final skip = await pgSkipReason(target);
  if (skip != null) {
    test('Postgres unavailable', () {}, skip: skip);
    return;
  }

  late Connection observer;
  late TenturaDb db;
  late InvitationCase invitations;
  late ClosureCase closures;
  var race = _RaceQueries();

  setUpAll(() async {
    final session = await setUpDisposablePgWriter(target: target);
    addTearDown(() => tearDownDisposablePgWriter(session: session));
    observer = session.writer;
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
          scopeInterceptor: () => race,
        ),
      );
    addTearDown(() async {
      getIt.skipDoubleRegistration = false;
      await getIt.reset();
    });
    final database = target.databaseEnv;
    await configureSessionDatabaseTestGraph(
      Env(
        environment: Environment.dev,
        serverUri: Uri.parse(_origin),
        publicOrigin: _origin,
        publicKey: Env.kJwtPublicKey,
        privateKey: Env.kJwtPrivateKey,
        pgHost: database.pgHost,
        pgPort: database.pgPort,
        pgDatabase: database.pgDatabase,
        pgUsername: database.pgUsername,
        pgPassword: database.pgPassword,
        workersCount: 1,
        maxConnectionCount: 4,
        pgStatementTimeoutMs: kStableStateWait.inMilliseconds + 5000,
        printEnv: false,
        isDebugModeOn: false,
      ),
    );
    db = getIt<TenturaDb>();
    invitations = getIt<InvitationCase>();
    closures = getIt<ClosureCase>();
  });

  Future<Result> query(String sql, Map<String, Object?> args) =>
      observer.execute(Sql.named(sql), parameters: args);

  setUp(() async {
    race = _RaceQueries();
    await observer.execute('''
TRUNCATE public.attention_occurrence, public.invitation,
  public.beacon, public."user" CASCADE
''');
    for (final (slot, user) in [_issuer, _invitee, ..._helpers].indexed) {
      await query(
        'INSERT INTO public."user" (id, display_name, public_key) '
        'VALUES (@id, @name, @key)',
        {
          'id': user,
          'name': 'Participant $slot',
          'key': pgTestPublicKey('requestInviteClosure', slot + 1),
        },
      );
    }
    await query(
      '''
INSERT INTO public.beacon (id, user_id, title, description, status, kind,
  forward_policy, is_discoverable, published_at)
VALUES (@request, @issuer, 'Community garden', 'Help planting seedlings',
  @status, @kind, @policy, true, now())
''',
      {
        'request': _request,
        'issuer': _issuer,
        'status': BeaconStatus.open.smallintValue,
        'kind': BeaconKind.request.value,
        'policy': BeaconForwardPolicyValue.open.value,
      },
    );
  });

  Future<String> issueInvite() async {
    final invite = await invitations.create(
      userId: _issuer,
      addresseeName: 'Invitee',
      beaconId: _request,
    );
    return invite.id;
  }

  Future<int> status() async {
    final rows = await query(
      'SELECT status FROM public.beacon WHERE id = @request',
      {'request': _request},
    );
    return rows.single.single! as int;
  }

  Future<Result> forwards() => query(
    '''
SELECT sender_id, recipient_id, cancelled_at
FROM public.beacon_forward_edge
WHERE beacon_id = @request AND recipient_id = @invitee
''',
    {'request': _request, 'invitee': _invitee},
  );

  Future<bool> waitForLock({
    required int waiter,
    required int blocker,
    required bool Function() bypassed,
  }) async {
    expect(waiter, isNot(blocker), reason: 'Use separate Postgres backends');
    final clock = Stopwatch()..start();
    while (!bypassed()) {
      final result = await query(
        '''
WITH request_lock AS (
  SELECT hashtextextended(@request, 4242) AS key
)
SELECT EXISTS (
  SELECT 1 FROM pg_stat_activity activity
  JOIN pg_locks waiting ON waiting.pid = activity.pid
  CROSS JOIN request_lock
  WHERE activity.datname = current_database() AND activity.pid = @waiter
    AND activity.wait_event_type = 'Lock'
    AND waiting.locktype = 'advisory' AND NOT waiting.granted
    AND waiting.classid::bigint = ((key >> 32) & 4294967295)
    AND waiting.objid::bigint = (key & 4294967295) AND waiting.objsubid = 1
    AND @blocker = ANY(pg_blocking_pids(activity.pid))
)
''',
        {'request': _request, 'waiter': waiter, 'blocker': blocker},
      );
      if (result.single.single == true) return true;
      if (clock.elapsed >= kStableStateWait) {
        fail('Backend $waiter neither waited on $blocker nor progressed');
      }
      await Future<void>.delayed(const Duration(milliseconds: 20));
    }
    return false;
  }

  for (final byCode in [true, false]) {
    group(
      'Existing account accepts a Request invite ${byCode ? 'by code' : 'by ID'}',
      () {
        // A lease exposes the initial read to the interceptor. The use cases
        // still open and commit their own transactions.
        _Running<InviteAcceptance> accept(String invite) => _Running(
          db.withConnectionScope(
            () => byCode
                ? invitations.acceptAsExisting(code: invite, userId: _invitee)
                : invitations.accept(invitationId: invite, userId: _invitee),
          ),
        );

        for (final closeStatus in [
          BeaconStatus.closed,
          BeaconStatus.reviewOpen,
        ]) {
          test(
            closeStatus == BeaconStatus.closed
                ? 'Closing a Request consumes the waiting invite without delivery'
                : 'Opening a closure review consumes the waiting invite without delivery',
            () async {
              if (closeStatus == BeaconStatus.reviewOpen) {
                // A review with fewer than three members settles immediately.
                for (final (slot, helper) in _helpers.indexed) {
                  await query(
                    '''
INSERT INTO public.beacon_help_offer (beacon_id, user_id)
VALUES (@request, @helper)
''',
                    {'request': _request, 'helper': helper},
                  );
                  await query(
                    '''
INSERT INTO public.beacon_commitment_event
  (id, beacon_id, user_id, actor_user_id, kind)
VALUES (@event, @request, @helper, @issuer, @kind)
''',
                    {
                      'event': 'E1acce55000${slot + 1}',
                      'request': _request,
                      'helper': helper,
                      'issuer': _issuer,
                      'kind': CommitmentEventKind.acknowledged.smallintValue,
                    },
                  );
                }
              }
              final invite = await issueInvite();
              final initialRead = race.initialRead = _Pause(
                'initial Request read',
              );
              final locked = race.closureLocked = _Pause(
                'closure Request lock',
              );
              final beforeForward = race.beforeForward = _Pause(
                'forward insert',
              );
              final accepting = accept(invite);
              _Running<void>? closing;
              late bool waited;
              late Object? acceptance;
              try {
                final acceptingPid = await initialRead.waitFor(accepting);
                closing = _Running(
                  closures.close(authorId: _issuer, beaconId: _request),
                );
                final closingPid = await locked.waitFor(closing);
                initialRead.resume();
                waited = await waitForLock(
                  waiter: acceptingPid,
                  blocker: closingPid,
                  // Hold an acceptance that bypasses the lock until closure
                  // commits, so it tries to deliver after the status change.
                  bypassed: () =>
                      beforeForward.reached.isCompleted || accepting.done,
                );
                expect(accepting.done, isFalse);
                expect(await status(), BeaconStatus.open.smallintValue);
                locked.resume();
                expect(await closing.result.timeout(kCompletionWait), isNull);
                expect(await status(), closeStatus.smallintValue);
              } finally {
                initialRead.resume();
                locked.resume();
                beforeForward.resume();
                final results = await Future.wait([
                  accepting.result,
                  if (closing != null) closing.result,
                ]).timeout(kCompletionWait);
                acceptance = results.first;
              }

              if (closeStatus == BeaconStatus.reviewOpen) {
                expect(
                  await query(
                    'SELECT epoch FROM public.beacon_closure WHERE beacon_id = @request AND status = 0',
                    {'request': _request},
                  ),
                  [
                    [1],
                  ],
                );
              }
              expect(
                {
                  'acceptance': acceptance,
                  'acceptance waited for closure': waited,
                  'forward edges': await forwards(),
                  'invite claim': await query(
                    'SELECT invited_id, accepted_at FROM public.invitation WHERE id = @invite',
                    {'invite': invite},
                  ),
                  'reciprocal votes': await query(
                    '''
SELECT subject, object FROM public.vote_user
WHERE (subject, object) IN ((@issuer, @invitee), (@invitee, @issuer))
''',
                    {'issuer': _issuer, 'invitee': _invitee},
                  ),
                  'forward attention': await query(
                    'SELECT source_event_key FROM public.attention_occurrence WHERE source_event_key = @key',
                    {'key': 'invitation:$invite:forward'},
                  ),
                  'invitee inbox': await query(
                    'SELECT beacon_id FROM public.inbox_item WHERE user_id = @invitee AND beacon_id = @request',
                    {'request': _request, 'invitee': _invitee},
                  ),
                },
                {
                  'acceptance': InviteAcceptance.requestLapsed,
                  'acceptance waited for closure': isTrue,
                  'forward edges': isEmpty,
                  'invite claim': [
                    [_invitee, isNotNull],
                  ],
                  'reciprocal votes': isEmpty,
                  'forward attention': isEmpty,
                  'invitee inbox': isEmpty,
                },
              );
            },
          );
        }

        test(
          'Closure waits for an invite delivery that already has the Request lock',
          () async {
            final invite = await issueInvite();
            final beforeForward = race.beforeForward = _Pause('forward insert');
            final accepting = accept(invite);
            final closeConnected = Completer<int>();
            _Running<void>? closing;
            late bool waited;
            late List<Object?> outcomes;
            try {
              final acceptingPid = await beforeForward.waitFor(accepting);
              closing = _Running(
                db.withConnectionScope(() async {
                  final row = await db
                      .customSelect('SELECT pg_backend_pid() AS pid')
                      .getSingle();
                  closeConnected.complete(row.read<int>('pid'));
                  await closures.close(authorId: _issuer, beaconId: _request);
                }),
              );
              final closingPid = await Future.any([
                closeConnected.future,
                closing.result.then<int>(
                  (result) => fail(
                    'Closure finished before obtaining a connection: $result',
                  ),
                ),
              ]).timeout(kStableStateWait);
              waited = await waitForLock(
                waiter: closingPid,
                blocker: acceptingPid,
                bypassed: () => closing!.done,
              );
            } finally {
              beforeForward.resume();
              outcomes = await Future.wait([
                accepting.result,
                if (closing != null) closing.result,
              ]).timeout(kCompletionWait);
            }

            expect(
              {
                'acceptance': outcomes.first,
                'closure error': outcomes.last,
                'closure waited for acceptance': waited,
                'final status': await status(),
                'forward edges': await forwards(),
              },
              {
                'acceptance': InviteAcceptance.accepted,
                'closure error': isNull,
                'closure waited for acceptance': isTrue,
                'final status': BeaconStatus.closed.smallintValue,
                'forward edges': [
                  [_issuer, _invitee, isNull],
                ],
              },
            );
          },
        );
      },
      timeout: const Timeout(Duration(seconds: 100)),
    );
  }
}

final class _Running<T> {
  _Running(Future<T> operation) {
    result = operation
        .then<Object?>(
          (value) => value,
          onError: AsyncError.new,
        )
        .whenComplete(() {
          done = true;
        });
  }

  late final Future<Object?> result;
  bool done = false;
}

final class _Pause {
  _Pause(this.label);

  final String label;
  final reached = Completer<int>();
  final _release = Completer<void>();

  Future<int> waitFor(_Running<Object?> operation) => Future.any([
    reached.future,
    operation.result.then<int>(
      (result) => fail('Operation finished before $label: $result'),
    ),
  ]).timeout(kStableStateWait);

  Future<void> hold(QueryExecutor executor) async {
    final rows = await executor.runSelect('SELECT pg_backend_pid() AS pid', []);
    reached.complete(rows.single['pid']! as int);
    await _release.future.timeout(kStableStateWait + kCompletionWait);
  }

  void resume() {
    if (!_release.isCompleted) _release.complete();
  }
}

/// Pauses the real statements at staging points without changing their results.
final class _RaceQueries extends QueryInterceptor {
  _Pause? initialRead;
  _Pause? closureLocked;
  _Pause? beforeForward;

  @override
  Future<void> runCustom(
    QueryExecutor executor,
    String statement,
    List<Object?> args,
  ) async {
    await super.runCustom(executor, statement, args);
    final pause = closureLocked;
    if (pause != null &&
        !pause.reached.isCompleted &&
        statement ==
            r'SELECT pg_advisory_xact_lock(hashtextextended($1, 4242))' &&
        args.contains(_request)) {
      await pause.hold(executor);
    }
  }

  @override
  Future<List<Map<String, Object?>>> runSelect(
    QueryExecutor executor,
    String statement,
    List<Object?> args,
  ) async {
    final forward = beforeForward;
    if (forward != null &&
        !forward.reached.isCompleted &&
        statement.startsWith('INSERT INTO "beacon_forward_edge" ') &&
        args.contains(_request) &&
        args.contains(_invitee)) {
      await forward.hold(executor);
    }
    final rows = await super.runSelect(executor, statement, args);
    final read = initialRead;
    if (read != null &&
        !read.reached.isCompleted &&
        rows.length == 1 &&
        rows.single['beacon.id'] == _request) {
      expect(rows.single['beacon.status'], BeaconStatus.open.smallintValue);
      await read.hold(executor);
    }
    return rows;
  }
}
