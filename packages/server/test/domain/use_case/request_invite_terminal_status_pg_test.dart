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
import 'package:tentura_server/domain/entity/beacon_kind.dart';
import 'package:tentura_server/domain/entity/invite_acceptance.dart';
import 'package:tentura_server/domain/use_case/beacon_case.dart';
import 'package:tentura_server/domain/use_case/invitation_case.dart';
import 'package:tentura_server/env.dart';

import '../../support/disposable_pg_target.dart';
import '../../support/pg_test_public_keys.dart';
import '../../support/pg_wait.dart';
import '../../support/session_database_di_harness.dart';

const _request = 'B1acce570001';
const _issuer = 'U1acce570001';
const _invitee = 'U1acce570002';
const _origin = 'http://127.0.0.1:2080';

enum _StatusChange {
  cancel('Cancellation', BeaconStatus.cancelled),
  delete('Deletion', BeaconStatus.deleted);

  const _StatusChange(this.label, this.status);

  final String label;
  final BeaconStatus status;

  Object get expectedResult => switch (this) {
    cancel => status.smallintValue,
    delete => true,
  };

  Future<Object> apply(BeaconCase beacons) async => switch (this) {
    cancel => (await beacons.beaconCancel(
      beaconId: _request,
      userId: _issuer,
    )).status,
    delete => await beacons.deleteById(beaconId: _request, userId: _issuer),
  };
}

Future<void> main() async {
  final target = DisposablePgTarget.fromNamedEnvironment(
    envVarName: 'TENTURA_REQUEST_INVITE_TERMINAL_STATUS_TEST_DB',
    defaultNamePrefix: 'tentura_test_request_invite_terminal',
  );
  final skip = await pgSkipReason(target);
  if (skip != null) {
    test('Postgres unavailable', () {}, skip: skip);
    return;
  }

  late Connection observer;
  late TenturaDb db;
  late InvitationCase invitations;
  late BeaconCase beacons;
  late _RaceQueries race;

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
        () =>
            TenturaDb.scoped(getIt<MainDbPool>(), scopeInterceptor: () => race),
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
    beacons = getIt<BeaconCase>();
  });

  Future<Result> query(String sql, Map<String, Object?> args) =>
      observer.execute(Sql.named(sql), parameters: args);

  setUp(() async {
    race = _RaceQueries();
    await observer.execute('''
TRUNCATE public.attention_occurrence, public.invitation,
  public.beacon, public."user" CASCADE
''');
    for (final (slot, user) in [_issuer, _invitee].indexed) {
      await query(
        'INSERT INTO public."user" (id, display_name, public_key) '
        'VALUES (@id, @name, @key)',
        {
          'id': user,
          'name': 'Participant $slot',
          'key': pgTestPublicKey('requestInviteTerminalStatus', slot + 1),
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

  Future<bool> waitForBlock({
    required int waiter,
    required int blocker,
    required bool Function() bypassed,
  }) async {
    expect(waiter, isNot(blocker), reason: 'Use separate Postgres backends');
    final clock = Stopwatch()..start();
    while (!bypassed()) {
      final result = await query(
        '''
SELECT EXISTS (
  SELECT 1 FROM pg_stat_activity
  WHERE datname = current_database() AND pid = @waiter
    AND wait_event_type = 'Lock' AND @blocker = ANY(pg_blocking_pids(pid))
)
''',
        {'waiter': waiter, 'blocker': blocker},
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
        // Lease the backend for observation. The use cases own their transactions.
        _Running accept(String invite) => _Running(
          db.withConnectionScope(
            () => byCode
                ? invitations.acceptAsExisting(code: invite, userId: _invitee)
                : invitations.accept(invitationId: invite, userId: _invitee),
          ),
        );

        for (final change in _StatusChange.values) {
          test('${change.label} consumes a waiting invite without delivery', () async {
            final invite = await issueInvite();
            final initialRead = race.initialRead = _Pause(
              'initial Request read',
            );
            final beforeStatusWrite = race.beforeStatusWrite = _Pause(
              'Request status write',
            );
            final beforeForward = race.beforeForward = _Pause('forward insert');
            final accepting = accept(invite);
            _Running? changing;
            late bool waited;
            var waitedInReverse = false;
            late List<Object?> outcomes;
            try {
              final acceptingPid = await initialRead.waitFor(accepting);
              changing = _Running(change.apply(beacons));
              final changingPid = await beforeStatusWrite.waitFor(changing);
              initialRead.resume();
              waited = await waitForBlock(
                waiter: acceptingPid,
                blocker: changingPid,
                // Hold a bypassing acceptance before its forward insert can
                // contend on the Request row through the foreign key.
                bypassed: () => beforeForward.reached || accepting.done,
              );
              expect(accepting.done, isFalse);
              expect(await status(), BeaconStatus.open.smallintValue);
              beforeStatusWrite.resume();
              if (!waited) {
                // Let the author commit first if it can. If it instead waits
                // for acceptance, release the forward insert so PostgreSQL
                // can resolve the competing locks without a test-induced wait.
                waitedInReverse = await waitForBlock(
                  waiter: changingPid,
                  blocker: acceptingPid,
                  bypassed: () => changing!.done,
                );
              }
            } finally {
              initialRead.resume();
              beforeStatusWrite.resume();
              beforeForward.resume();
              outcomes = await Future.wait([
                accepting.result,
                if (changing != null) changing.result,
              ]).timeout(kCompletionWait);
            }

            expect(
              {
                'acceptance': outcomes.first,
                'acceptance waited for status change': waited,
                'status change waited on bypassing acceptance': waitedInReverse,
                'status change result': outcomes.last,
                'final status': await status(),
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
                'acceptance waited for status change': isTrue,
                'status change waited on bypassing acceptance': isFalse,
                'status change result': change.expectedResult,
                'final status': change.status.smallintValue,
                'forward edges': isEmpty,
                'invite claim': [
                  [_invitee, isNotNull],
                ],
                'reciprocal votes': isEmpty,
                'forward attention': isEmpty,
                'invitee inbox': isEmpty,
              },
            );
          });

          test(
            '${change.label} waits for invite delivery already in progress',
            () async {
              final invite = await issueInvite();
              final beforeForward = race.beforeForward = _Pause(
                'forward insert',
              );
              final accepting = accept(invite);
              final connected = Completer<int>();
              _Running? changing;
              late bool waited;
              late List<Object?> outcomes;
              try {
                final acceptingPid = await beforeForward.waitFor(accepting);
                changing = _Running(
                  db.withConnectionScope(() async {
                    final row = await db
                        .customSelect('SELECT pg_backend_pid() AS pid')
                        .getSingle();
                    connected.complete(row.read<int>('pid'));
                    return change.apply(beacons);
                  }),
                );
                final changingPid = await changing.waitFor(
                  connected.future,
                  'status change backend',
                );
                waited = await waitForBlock(
                  waiter: changingPid,
                  blocker: acceptingPid,
                  bypassed: () => changing!.done,
                );
                if (waited) expect(changing.done, isFalse);
              } finally {
                beforeForward.resume();
                outcomes = await Future.wait([
                  accepting.result,
                  if (changing != null) changing.result,
                ]).timeout(kCompletionWait);
              }

              expect(
                {
                  'acceptance': outcomes.first,
                  'status change result': outcomes.last,
                  'status change waited for acceptance': waited,
                  'final status': await status(),
                  'forward edges': await forwards(),
                },
                {
                  'acceptance': InviteAcceptance.accepted,
                  'status change result': change.expectedResult,
                  'status change waited for acceptance': isTrue,
                  'final status': change.status.smallintValue,
                  'forward edges': [
                    [_issuer, _invitee, isNull],
                  ],
                },
              );
            },
          );
        }
      },
      timeout: const Timeout(Duration(seconds: 100)),
    );
  }
}

final class _Running {
  _Running(Future<Object?> operation) {
    result = operation
        .then<Object?>((value) => value, onError: AsyncError.new)
        .whenComplete(() => done = true);
  }

  late final Future<Object?> result;
  bool done = false;

  Future<int> waitFor(Future<int> pid, String stage) => Future.any([
    pid,
    result.then<int>(
      (outcome) => fail('Operation finished before $stage: $outcome'),
    ),
  ]).timeout(kStableStateWait);
}

final class _Pause {
  _Pause(this.label);

  final String label;
  final _pid = Completer<int>();
  final _release = Completer<void>();

  bool get reached => _pid.isCompleted;

  Future<int> waitFor(_Running operation) =>
      operation.waitFor(_pid.future, label);

  Future<void> hold(QueryExecutor executor) async {
    final rows = await executor.runSelect('SELECT pg_backend_pid() AS pid', []);
    _pid.complete(rows.single['pid']! as int);
    await _release.future.timeout(kStableStateWait + kCompletionWait);
  }

  void resume() {
    if (!_release.isCompleted) _release.complete();
  }
}

/// Pauses the real use cases at their database statements.
final class _RaceQueries extends QueryInterceptor {
  _Pause? initialRead;
  _Pause? beforeStatusWrite;
  _Pause? beforeForward;

  @override
  Future<int> runUpdate(
    QueryExecutor executor,
    String statement,
    List<Object?> args,
  ) async {
    final write = beforeStatusWrite;
    // The author has acquired the locks for this transition by the status write.
    if (write != null &&
        !write.reached &&
        statement.startsWith('UPDATE "beacon" SET "status" = ') &&
        args.contains(_request)) {
      await write.hold(executor);
    }
    return super.runUpdate(executor, statement, args);
  }

  @override
  Future<List<Map<String, Object?>>> runSelect(
    QueryExecutor executor,
    String statement,
    List<Object?> args,
  ) async {
    final forward = beforeForward;
    if (forward != null &&
        !forward.reached &&
        statement.startsWith('INSERT INTO "beacon_forward_edge" ') &&
        args.contains(_request) &&
        args.contains(_invitee)) {
      await forward.hold(executor);
    }
    final rows = await super.runSelect(executor, statement, args);
    final read = initialRead;
    if (read != null &&
        !read.reached &&
        rows.length == 1 &&
        rows.single['beacon.id'] == _request) {
      expect(rows.single['beacon.status'], BeaconStatus.open.smallintValue);
      await read.hold(executor);
    }
    return rows;
  }
}
