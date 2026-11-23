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
import 'package:tentura_server/domain/exception.dart';
import 'package:tentura_server/domain/exception_codes.dart';
import 'package:tentura_server/domain/use_case/beacon_case.dart';
import 'package:tentura_server/domain/use_case/invitation_case.dart';
import 'package:tentura_server/domain/use_case/user_erasure_case.dart';
import 'package:tentura_server/env.dart';

import '../../support/disposable_pg_target.dart';
import '../../support/pg_test_public_keys.dart';
import '../../support/pg_wait.dart';
import '../../support/session_database_di_harness.dart';

const _author = 'Ue2ace000001';
const _issuer = 'Ue2ace000002';
const _invitee = 'Ue2ace000003';
const _earlierRequest = 'Be2ace000001';
const _request = 'Be2ace000002';
const _post = 'Be2ace000003';
const _draft = 'Be2ace000004';
const _origin = 'http://127.0.0.1:2080';

Future<void> main() async {
  final target = DisposablePgTarget.fromNamedEnvironment(
    envVarName: 'TENTURA_REQUEST_INVITE_AUTHOR_ERASURE_TEST_DB',
    defaultNamePrefix: 'tentura_test_request_invite_author_erase',
  );
  final skip = await pgSkipReason(target);
  if (skip != null) {
    test('Postgres unavailable', () {}, skip: skip);
    return;
  }

  late Connection observer;
  late TenturaDb db;
  late InvitationCase invitations;
  late AccountErasureCase erasure;
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
        pgStatementTimeoutMs:
            (kStableStateWait + kCompletionWait).inMilliseconds,
        printEnv: false,
        isDebugModeOn: false,
      ),
    );
    db = getIt<TenturaDb>();
    invitations = getIt<InvitationCase>();
    erasure = getIt<AccountErasureCase>();
    beacons = getIt<BeaconCase>();
  });

  Future<Result> query(String sql, Map<String, Object?> args) =>
      observer.execute(Sql.named(sql), parameters: args);

  Future<void> publishRequest(String id) async {
    await query(
      '''
INSERT INTO public.beacon (id, user_id, title, description, status, kind,
  forward_policy, is_discoverable, published_at)
VALUES (@id, @author, 'Community garden', 'Help planting seedlings',
  @status, @kind, @policy, true, now())
''',
      {
        'id': id,
        'author': _author,
        'status': BeaconStatus.open.smallintValue,
        'kind': BeaconKind.request.value,
        'policy': BeaconForwardPolicyValue.open.value,
      },
    );
  }

  setUp(() async {
    race = _RaceQueries();
    await observer.execute('''
TRUNCATE public.attention_occurrence, public.invitation,
  public.beacon, public."user" CASCADE
''');
    for (final (slot, user) in [_author, _issuer, _invitee].indexed) {
      await query(
        'INSERT INTO public."user" (id, display_name, public_key) '
        'VALUES (@id, @name, @key)',
        {
          'id': user,
          'name': 'Participant $slot',
          'key': pgTestPublicKey('requestInviteAuthorErasure', slot + 1),
        },
      );
    }
    await publishRequest(_request);
    // The issuer can read and forward as an admitted member. Their invitation
    // survives erasure of the author so we can verify the committed claim.
    await query(
      '''
INSERT INTO public.beacon_participant (beacon_id, user_id, role, status, room_access)
VALUES (@request, @issuer, 2, 0, 3)
''',
      {'request': _request, 'issuer': _issuer},
    );
  });

  Future<void> seedOtherOwnedBeacons({required bool chunked}) async {
    await query(
      '''
INSERT INTO public.beacon
  (id, user_id, title, description, status, kind, forward_policy, is_discoverable,
   published_at)
VALUES (@post, @author, '', 'Garden photos', @open, @postKind, @policy, false, now()),
       (@draft, @author, 'Private draft', '', @draftStatus, @requestKind, @policy, false, NULL)
''',
      {
        'post': _post,
        'draft': _draft,
        'author': _author,
        'open': BeaconStatus.open.smallintValue,
        'draftStatus': BeaconStatus.draft.smallintValue,
        'postKind': BeaconKind.post.value,
        'requestKind': BeaconKind.request.value,
        'policy': BeaconForwardPolicyValue.open.value,
      },
    );
    if (chunked) {
      await publishRequest(_earlierRequest);
      await query(
        '''
INSERT INTO public.beacon (id, user_id, title, description, status)
SELECT 'Bedraft' || lpad(i::text, 5, '0'), @author, 'Private draft', '', @draft
FROM generate_series(1, 200) AS n(i)
''',
        {'author': _author, 'draft': BeaconStatus.draft.smallintValue},
      );
    }
  }

  Future<String> issueInvite() async {
    final invite = await invitations.create(
      userId: _issuer,
      addresseeName: 'Invitee',
      beaconId: _request,
    );
    return invite.id;
  }

  Future<int> status([String id = _request]) async =>
      (await query(
            'SELECT status FROM public.beacon WHERE id = @request',
            {'request': id},
          )).single.single!
          as int;

  Future<Result> authorRows() => query(
    'SELECT id FROM public."user" WHERE id = @author',
    {'author': _author},
  );

  Future<void> expectErasedBeacons() async {
    expect(await authorRows(), isEmpty);
    expect(
      await query(
        '''
SELECT status, user_id, title, description
FROM public.beacon WHERE id IN (@request, @post) ORDER BY id
''',
        {'request': _request, 'post': _post},
      ),
      [
        [
          BeaconStatus.deleted.smallintValue,
          null,
          'Deleted request',
          'This request was deleted.',
        ],
        [BeaconStatus.deleted.smallintValue, null, '', ''],
      ],
    );
    expect(
      await query(
        'SELECT id FROM public.beacon WHERE id = @draft OR id LIKE @batch',
        {'draft': _draft, 'batch': 'Bedraft%'},
      ),
      isEmpty,
    );
  }

  Future<bool> waitForBlock({
    required int waiter,
    required int blocker,
    required bool Function() bypassed,
    String? waitEvent,
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
    AND (@event::text IS NULL OR wait_event = @event)
)
''',
        {'waiter': waiter, 'blocker': blocker, 'event': waitEvent},
      );
      if (result.single.single == true) return true;
      if (clock.elapsed >= kStableStateWait) {
        fail('Backend $waiter neither waited on $blocker nor progressed');
      }
      await Future<void>.delayed(const Duration(milliseconds: 20));
    }
    return false;
  }

  _Running erase() => _Running(db, () => erasure.deleteById(id: _author));

  _Running changeRequest({required bool cancel}) => _Running(db, () async {
    if (cancel) {
      final result = await beacons.beaconCancel(
        beaconId: _request,
        userId: _author,
      );
      return result.status;
    }
    return beacons.deleteById(beaconId: _request, userId: _author);
  });

  _Running holdRequestLock(Completer<void> locked, Future<void> release) =>
      _Running(
        db,
        () => db.withJoinedTransaction(() async {
          await db.customStatement(
            r'SELECT pg_advisory_xact_lock(hashtextextended($1, 4242))',
            [_request],
          );
          locked.complete();
          await release.timeout(kStableStateWait + kCompletionWait);
          return null;
        }),
      );

  for (final chunked in [false, true]) {
    group('Erasing an account with ${chunked ? 'many' : 'few'} owned beacons', () {
      setUp(() => seedOtherOwnedBeacons(chunked: chunked));
      for (final byCode in [false, true]) {
        final entryPoint = byCode ? 'by code' : 'by ID';
        _Running accept(String invite) => _Running(
          db,
          () => byCode
              ? invitations.acceptAsExisting(code: invite, userId: _invitee)
              : invitations.accept(invitationId: invite, userId: _invitee),
        );

        test(
          'erasure consumes a waiting invite $entryPoint without delivery',
          () async {
            final invite = await issueInvite();
            final initialRead = race.initialRead = _Pause(
              'initial Request read',
            );
            final statusWrite = race.statusWrite = _Pause(
              chunked ? 'after status write' : 'before status write',
            );
            race.holdAfterStatusWrite = chunked;
            final forwardInsert = race.forwardInsert = _Pause('forward insert');

            final accepting = accept(invite);
            _Running? erasing;
            late bool waited;
            late List<Object?> outcomes;
            try {
              final acceptPid = await initialRead.waitFor(accepting);
              final operation = erasing = erase();
              final erasePid = await statusWrite.waitFor(operation);
              initialRead.resume();
              // A bypassing accept must stop before it can appear to serialize
              // merely because the forward insert checks the beacon foreign key.
              waited = await waitForBlock(
                waiter: acceptPid,
                blocker: erasePid,
                bypassed: () => forwardInsert.reached || accepting.done,
                waitEvent: 'advisory',
              );
              expect(await status(), BeaconStatus.open.smallintValue);
              if (chunked) {
                expect(
                  await status(_earlierRequest),
                  BeaconStatus.deleted.smallintValue,
                );
                expect(await authorRows(), hasLength(1));
              }

              statusWrite.resume();
              if (!waited && !accepting.done) {
                // Give the erasure a chance to commit before releasing an
                // incorrectly allowed delivery. Release delivery if erasure
                // itself cannot make progress until the accept transaction ends.
                await waitForBlock(
                  waiter: erasePid,
                  blocker: acceptPid,
                  bypassed: () => operation.done,
                );
              }
            } finally {
              initialRead.resume();
              statusWrite.resume();
              forwardInsert.resume();
              outcomes = await Future.wait([
                accepting.result,
                if (erasing != null) erasing.result,
              ]).timeout(kCompletionWait);
            }

            await expectErasedBeacons();
            expect(
              {
                'acceptance': outcomes.first,
                'acceptance waited on erasure advisory lock': waited,
                'erasure returned': outcomes.last,
                'forward edges': await query(
                  'SELECT id FROM public.beacon_forward_edge '
                  'WHERE beacon_id = @request AND recipient_id = @invitee',
                  {'request': _request, 'invitee': _invitee},
                ),
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
                'acceptance waited on erasure advisory lock': true,
                'erasure returned': true,
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

        test(
          'erasure waits for invite delivery already in progress $entryPoint',
          () async {
            final invite = await issueInvite();
            final forwardInsert = race.forwardInsert = _Pause('forward insert');
            // Detect erasure passing the missing advisory lock before a
            // later statement can block for a different reason.
            final statusWrite = race.statusWrite = _Pause(
              'before status write',
            );
            final accepting = accept(invite);
            _Running? erasing;
            late bool waited;
            late List<Object?> outcomes;
            try {
              final acceptPid = await forwardInsert.waitFor(accepting);
              final operation = erasing = erase();
              final erasePid = await operation.connect();
              waited = await waitForBlock(
                waiter: erasePid,
                blocker: acceptPid,
                bypassed: () => statusWrite.reached || operation.done,
                waitEvent: 'advisory',
              );
              expect(operation.done, isFalse);
              if (chunked) {
                expect(
                  await status(_earlierRequest),
                  BeaconStatus.deleted.smallintValue,
                );
                expect(await authorRows(), hasLength(1));
              }
              forwardInsert.resume();
            } finally {
              forwardInsert.resume();
              statusWrite.resume();
              outcomes = await Future.wait([
                accepting.result,
                if (erasing != null) erasing.result,
              ]).timeout(kCompletionWait);
            }

            await expectErasedBeacons();
            expect(
              (waited, outcomes.first, outcomes.last),
              (true, InviteAcceptance.accepted, true),
              reason:
                  'Erasure must wait on invite delivery before deleting the Request',
            );
          },
        );
      }
    });
  }

  for (final cancel in [true, false]) {
    test(
      'erasure holds the hierarchy while waiting to lock the Request before a concurrent ${cancel ? 'Cancel' : 'Delete'}',
      () async {
        final releaseLock = Completer<void>();
        final locked = Completer<void>();
        final holder = holdRequestLock(locked, releaseLock.future);
        final statusWrite = race.statusWrite = _Pause('before status write');
        _Running? erasing;
        _Running? changing;
        late bool waited;
        late bool competingActionWaited;
        late Object rowLock;
        late List<Object?> outcomes;
        try {
          await locked.future.timeout(kStableStateWait);
          final operation = erasing = erase();
          final erasePid = await operation.connect();
          waited = await waitForBlock(
            waiter: erasePid,
            blocker: await holder.connect(),
            bypassed: () => statusWrite.reached || operation.done,
            waitEvent: 'advisory',
          );
          try {
            rowLock = await query(
              'SELECT id FROM public.beacon WHERE id = @request FOR UPDATE NOWAIT',
              {'request': _request},
            );
          } on ServerException catch (error) {
            rowLock = error;
          }

          final competingAction = changing = changeRequest(cancel: cancel);
          competingActionWaited = await waitForBlock(
            waiter: await competingAction.connect(),
            blocker: erasePid,
            bypassed: () => competingAction.done,
            waitEvent: 'advisory',
          );
        } finally {
          releaseLock.complete();
          statusWrite.resume();
          outcomes = await Future.wait([
            holder.result,
            if (erasing != null) erasing.result,
            if (changing != null) changing.result,
          ]).timeout(kCompletionWait);
        }

        expect(outcomes.first, isNull);
        expect(outcomes[1], isTrue);
        expect(
          outcomes.last,
          anyOf(
            cancel ? BeaconStatus.cancelled.smallintValue : true,
            isA<AsyncError>().having(
              (error) => error.error,
              'error',
              isA<ExceptionBase>().having(
                (error) => error.code.codeNumber,
                'domain rejection code',
                anyOf(
                  const GeneralExceptionCodes(
                    GeneralExceptionCode.idNotFoundException,
                  ).codeNumber,
                  const EvaluationExceptionCodes(
                    EvaluationExceptionCode.notEligible,
                  ).codeNumber,
                  const EvaluationExceptionCodes(
                    EvaluationExceptionCode.beaconNotClosable,
                  ).codeNumber,
                ),
              ),
            ),
          ),
          reason: 'The author action must succeed or report a domain rejection',
        );
        expect(
          await status(),
          anyOf(
            BeaconStatus.cancelled.smallintValue,
            BeaconStatus.deleted.smallintValue,
          ),
        );
        expect(
          {
            'erasure waited on Request advisory lock': waited,
            'author action waited on erasure': competingActionWaited,
            'row acquired with FOR UPDATE NOWAIT': rowLock,
          },
          {
            'erasure waited on Request advisory lock': true,
            'author action waited on erasure': true,
            'row acquired with FOR UPDATE NOWAIT': [
              [_request],
            ],
          },
          reason:
              'The advisory lock must leave the beacon row free until erasure can proceed',
        );
      },
    );
  }

  test(
    'erasure completes after a concurrent Cancel and leaves a deleted Request',
    () async {
      final statusChange = race.statusWrite = _Pause('author status write');
      final changing = changeRequest(cancel: true);
      final erasureWrite = _Pause('erasure status write');
      final releaseLock = Completer<void>();
      final locked = Completer<void>();
      _Running? holder;
      _Running? erasing;
      late bool waitedForAction;
      late bool waitedForRequestLock;
      late List<Object?> outcomes;
      try {
        final changePid = await statusChange.waitFor(changing);
        race.statusWrite = erasureWrite;

        // Queue another holder of the Request lock while the author's
        // action still holds it. This makes the next erasure wait observable
        // after the author's action has committed.
        final queued = holder = holdRequestLock(locked, releaseLock.future);
        final holderPid = await queued.connect();
        expect(
          await waitForBlock(
            waiter: holderPid,
            blocker: changePid,
            bypassed: () => queued.done,
            waitEvent: 'advisory',
          ),
          isTrue,
        );
        final operation = erasing = erase();
        final erasePid = await operation.connect();
        waitedForAction = await waitForBlock(
          waiter: erasePid,
          blocker: changePid,
          bypassed: () => operation.done,
          waitEvent: 'advisory',
        );
        statusChange.resume();
        await locked.future.timeout(kStableStateWait);
        waitedForRequestLock = await waitForBlock(
          waiter: erasePid,
          blocker: holderPid,
          bypassed: () => erasureWrite.reached || operation.done,
          waitEvent: 'advisory',
        );
      } finally {
        statusChange.resume();
        erasureWrite.resume();
        releaseLock.complete();
        outcomes = await Future.wait([
          changing.result,
          if (holder != null) holder.result,
          if (erasing != null) erasing.result,
        ]).timeout(kCompletionWait);
      }

      expect(await status(), BeaconStatus.deleted.smallintValue);
      expect(
        (
          outcomes.first,
          outcomes[1],
          outcomes.last,
          waitedForAction,
          waitedForRequestLock,
        ),
        (
          BeaconStatus.cancelled.smallintValue,
          null,
          true,
          true,
          true,
        ),
        reason:
            'Erasure must wait for the author action and the Request lock before deleting',
      );
    },
  );
}

final class _Running {
  _Running(TenturaDb db, Future<Object?> Function() operation) {
    result = db
        .withConnectionScope(() async {
          final row = await db
              .customSelect('SELECT pg_backend_pid() AS pid')
              .getSingle();
          _pid.complete(row.read<int>('pid'));
          return operation();
        })
        .then<Object?>((value) => value, onError: AsyncError.new)
        .whenComplete(() => done = true);
  }

  final _pid = Completer<int>();
  late final Future<Object?> result;
  bool done = false;

  Future<int> connect() => waitFor(_pid.future, 'database connection');

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

/// Pauses real statements on the connection that will execute them.
final class _RaceQueries extends QueryInterceptor {
  _Pause? initialRead;
  _Pause? statusWrite;
  _Pause? forwardInsert;
  bool holdAfterStatusWrite = false;

  @override
  Future<int> runUpdate(
    QueryExecutor executor,
    String statement,
    List<Object?> args,
  ) async {
    final write = statusWrite;
    if (write == null ||
        write.reached ||
        !statement.startsWith('UPDATE "beacon" SET "status" = ') ||
        !args.contains(_request)) {
      return super.runUpdate(executor, statement, args);
    }
    if (!holdAfterStatusWrite) await write.hold(executor);
    final changed = await super.runUpdate(executor, statement, args);
    if (holdAfterStatusWrite) await write.hold(executor);
    return changed;
  }

  @override
  Future<List<Map<String, Object?>>> runSelect(
    QueryExecutor executor,
    String statement,
    List<Object?> args,
  ) async {
    // Drift executes insertReturningOrNull via runSelect to fetch RETURNING rows.
    final forward = forwardInsert;
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
