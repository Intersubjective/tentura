@Tags(['pg'])
library;

import 'dart:async';
import 'dart:convert';
import 'dart:isolate';

import 'package:drift/drift.dart' show driftRuntimeOptions;
import 'package:logging/logging.dart';
import 'package:postgres/postgres.dart';
import 'package:test/test.dart';

import 'package:tentura_server/app/di.dart';
import 'package:tentura_server/app/workers/task_worker.dart';
import 'package:tentura_server/domain/entity/invite_acceptance.dart';
import 'package:tentura_server/domain/port/owner_graph_transaction_port.dart';
import 'package:tentura_server/domain/use_case/invitation_case.dart';
import 'package:tentura_server/domain/use_case/phantom_case.dart';
import 'package:tentura_server/env.dart';
import 'package:tentura_server/utils/id.dart';

import '../../support/disposable_pg_target.dart';
import '../../support/owner_graph_contention.dart';
import '../../support/pg_test_public_keys.dart';
import '../../support/session_database_di_harness.dart';

const _owner = 'U781j00000001';
const _joined = 'U781j00000002';
const _otherOwner = 'U781j00000003';
const _fault = 'Merge audit is temporarily unavailable';
const _passLimit = Duration(seconds: 4);
const _wakeLimit = Duration(seconds: 2);
const _waitingLimit = Duration(seconds: 2);
const _retryLimit = 10;

typedef _Row = Map<String, Object?>;
typedef _Job = ({String id, String phantom, String owner, String user});

Future<void> main() async {
  final target = DisposablePgTarget.fromNamedEnvironment(
    envVarName: 'TENTURA_PHANTOM_MERGE_WORKER_TEST_DB',
    defaultNamePrefix: 'tentura_test_phantom_merge_worker',
    useDevBindings: true,
  );
  final skip = await pgSkipReason(target);

  group('Processing queued phantom merges', () {
    late _Fixture fixture;

    setUpAll(() async {
      final previousWarning =
          driftRuntimeOptions.dontWarnAboutMultipleDatabases;
      driftRuntimeOptions.dontWarnAboutMultipleDatabases = true;
      addTearDown(() {
        driftRuntimeOptions.dontWarnAboutMultipleDatabases = previousWarning;
      });
      final session = await setUpDisposablePgWriter(target: target);
      addTearDown(() => tearDownDisposablePgWriter(session: session));
      await enforceOwnerScope(session);
      addTearDown(() async {
        getIt.skipDoubleRegistration = false;
        await getIt.reset();
      });
      final env = _workerEnv(target.databaseEnv);
      await configureSessionDatabaseTestGraph(env);
      fixture = _Fixture(session.writer, env);
    });

    setUp(() => fixture.reset());

    test('a sweep claims due work past a locked queue row', () async {
      final locked = await fixture.enqueue();
      final available = await fixture.enqueue();
      final before = await fixture.job(locked);
      final gate = await fixture.openGate();
      late _RunningWorker worker;
      await gate.runTx((tx) async {
        // The separate claim statement must SKIP LOCKED (plan §5.2).
        await tx.execute(
          Sql.named(
            'SELECT id FROM public.phantom_merge_job WHERE id = @id FOR UPDATE',
          ),
          parameters: {'id': locked.id},
        );
        worker = await fixture.startWorker();
        await fixture.waitForState(available, 'done');
        expect(await fixture.job(locked), before);
        expect(await fixture.merges(locked), isEmpty);
      });
      await worker.close();

      await fixture.withWorker((_) => fixture.waitForState(locked, 'done'));
      await fixture.expectMergedOnce(locked, attempts: 1);
      await fixture.expectMergedOnce(available, attempts: 1);
    });

    test(
      'an unexpired lease keeps a second worker from claiming a join',
      () async {
        final job = await fixture.enqueue();
        late _Row firstLease;
        late _RunningWorker firstWorker;
        late _RunningWorker secondWorker;
        await fixture.withOwnerHeld(job, () async {
          firstWorker = await fixture.startWorker();
          firstLease = (await fixture.waitForClaimBehindScope(job)).row;
          final otherJob = await fixture.enqueue(owner: _otherOwner);
          secondWorker = await fixture.startWorker();
          await fixture.waitForState(otherJob, 'done', limit: _waitingLimit);
          expect(await fixture.job(job), firstLease);
          expect(await fixture.merges(job), isEmpty);
        });

        await fixture.waitForState(job, 'done');
        await secondWorker.close();
        await firstWorker.close();
        await fixture.expectMergedOnce(job, attempts: 1);
        final finished = await fixture.job(job);
        expect(finished['lease_owner'], firstLease['lease_owner']);
        expect(finished['lease_until'], firstLease['lease_until']);
      },
    );

    test(
      'an expired claimant leaves the replacement lease intact before the new worker merges',
      () async {
        final job = await fixture.enqueue();
        final phantomBefore = await fixture.phantom(job);
        final gate = await fixture.openGate();
        final gatePid =
            (await gate.execute('SELECT pg_backend_pid()')).single.single!
                as int;
        final queueGate = await fixture.openGate();
        final queueGatePid =
            (await queueGate.execute('SELECT pg_backend_pid()')).single.single!
                as int;
        final gateEntered = Completer<void>();
        final releaseGate = Completer<void>();
        Future<void>? gateTransaction;
        late _Row replacement;
        late int firstBackend;
        late int replacementBackend;
        late _RunningWorker firstWorker;
        late _RunningWorker secondWorker;
        try {
          await queueGate.runTx((tx) async {
            await fixture.withOwnerHeld(job, () async {
              firstWorker = await fixture.startWorker();
              final first = await fixture.waitForClaimBehindScope(job);
              firstBackend = first.backend;
              // Queue a second holder between the two workers. Once it enters,
              // the first worker has left the scope and the second is still out.
              gateTransaction = gate.runTx((tx) async {
                await tx.execute(
                  Sql.named(
                    "SELECT pg_advisory_xact_lock(hashtextextended('owner_graph:' || @owner, 4242))",
                  ),
                  parameters: {'owner': job.owner},
                );
                gateEntered.complete();
                await releaseGate.future;
              })..ignore();
              await fixture.waitForScopeWaiters(job, {
                first.backend,
                gatePid,
              }, 2);
              await fixture.updateJob(
                job,
                "lease_until = now() - interval '1 second'",
              );
              secondWorker = await fixture.startWorker();
              replacement = await fixture.waitForJob(
                job,
                (row) =>
                    row['lease_owner'] != null &&
                    row['lease_owner'] != first.row['lease_owner'],
                reason: 'The second worker should claim the expired lease.',
                limit: _waitingLimit,
              );
              final waiting = await fixture.waitForScopeWaiters(
                job,
                {first.backend, gatePid},
                3,
              );
              replacementBackend = waiting.difference({
                first.backend,
                gatePid,
              }).single;
              expect(
                replacement,
                allOf(
                  containsPair('state', 'queued'),
                  containsPair('attempts', 2),
                ),
              );
              expect(await fixture.job(job), replacement);
              expect(await fixture.phantom(job), phantomBefore);
              expect(await fixture.merges(job), isEmpty);
              await tx.execute(
                'LOCK TABLE public.phantom_merge_job IN ACCESS EXCLUSIVE MODE',
                timeout: _waitingLimit,
              );
            });

            // The original worker now holds the owner scope and is trying to
            // re-read the queue. The replacement worker still cannot enter.
            await fixture.waitForBackendBlockedBy(firstBackend, queueGatePid);
            expect(await fixture.ownerScopeBackends(job, granted: true), {
              firstBackend,
            });
            await fixture.waitForBackendBlockedBy(
              replacementBackend,
              firstBackend,
            );
            final lockedRow = (await tx.execute(
              Sql.named(
                'SELECT * FROM public.phantom_merge_job WHERE id = @id',
              ),
              parameters: {'id': job.id},
            )).single.toColumnMap();
            expect(lockedRow, replacement);
            expect(await fixture.phantom(job), phantomBefore);
            expect(await fixture.merges(job), isEmpty);
          });

          await gateEntered.future.timeout(_waitingLimit);
          await fixture.waitForBackendBlockedBy(replacementBackend, gatePid);
          expect(
            await fixture.job(job),
            replacement,
            reason:
                'The stale claimant must leave the replacement row unchanged.',
          );
          expect(await fixture.phantom(job), phantomBefore);
          expect(await fixture.merges(job), isEmpty);
        } finally {
          releaseGate.complete();
          await gateTransaction?.timeout(_passLimit);
        }

        await fixture.waitForState(job, 'done');
        await secondWorker.close();
        await firstWorker.close();
        await fixture.expectMergedOnce(job, attempts: 2);
        final finished = await fixture.job(job);
        expect(finished['lease_owner'], replacement['lease_owner']);
        expect(finished['lease_until'], replacement['lease_until']);
      },
    );

    for (final (description, change) in [
      ('finished by another operation', "state = 'done', done_at = now()"),
      ('assigned to another worker', "lease_owner = 'another-worker'"),
    ]) {
      test(
        'a worker leaves a job $description while it waits for the scope',
        () async {
          final job = await fixture.enqueue();
          final phantomBefore = await fixture.phantom(job);
          final gate = await fixture.openGate();
          final gatePid =
              (await gate.execute('SELECT pg_backend_pid()')).single.single!
                  as int;
          late _Row changed;
          late _RunningWorker worker;
          await gate.runTx((tx) async {
            late ({_Row row, int backend}) claim;
            await fixture.withOwnerHeld(job, () async {
              worker = await fixture.startWorker();
              claim = await fixture.waitForClaimBehindScope(job);
              changed = (await tx.execute(
                Sql.named(
                  'UPDATE public.phantom_merge_job SET $change WHERE id = @id RETURNING *',
                ),
                parameters: {'id': job.id},
              )).single.toColumnMap();
            });
            // A fresh row lock must wait for the uncommitted change. Verify
            // that the same backend is now inside the owner's scope.
            await fixture.waitForBackendBlockedBy(claim.backend, gatePid);
            expect(
              await fixture.ownerScopeBackends(job, granted: true),
              contains(claim.backend),
            );
            expect(await fixture.job(job), claim.row);
          });
          await worker.close();

          expect(await fixture.job(job), changed);
          expect(await fixture.phantom(job), phantomBefore);
          expect(await fixture.merges(job), isEmpty);
        },
      );
    }

    test('the owner transaction locks the re-read job before merging', () async {
      final job = await fixture.enqueue();
      final gate = await fixture.openGate();
      final blocker = (await gate.execute(
        'SELECT pg_backend_pid()',
      )).single.single;
      await gate.runTx((tx) async {
        // Stall the first merge write to observe the scoped FOR UPDATE
        // re-read required by plan §5.2 while the transaction is still open.
        await tx.execute('LOCK TABLE public.phantom_merge IN SHARE MODE');
        await fixture.startWorker();
        await fixture.waitFor(
          () async => (await fixture.sql(
            '''
SELECT EXISTS (
  SELECT 1 FROM pg_stat_activity
  WHERE datname = current_database() AND wait_event_type = 'Lock'
    AND @blocker = ANY(pg_blocking_pids(pid))
)
''',
            {'blocker': blocker},
          )).single.single,
          (waiting) => waiting == true,
          reason: 'The worker should reach the held audit insert.',
        );
        expect((await fixture.job(job))['lease_owner'], isNotNull);
        await expectLater(
          fixture.sql(
            'SELECT id FROM public.phantom_merge_job WHERE id = @id FOR UPDATE NOWAIT',
            {'id': job.id},
          ),
          throwsA(
            isA<ServerException>().having(
              (error) => error.code,
              'SQLSTATE',
              '55P03',
            ),
          ),
        );
      });
      await fixture.waitForState(job, 'done');
      await fixture.expectMergedOnce(job, attempts: 1);
    });

    test(
      'a completion update affecting zero rows rolls back the merge',
      () async {
        final job = await fixture.enqueue();
        final phantomBefore = await fixture.phantom(job);
        final attentionBefore = await fixture.attention();
        // A BEFORE UPDATE trigger returning NULL makes the final statement
        // affect zero rows. The sequence records that it was attempted.
        await fixture.rejectCompletion();
        await fixture.withWorker((_) async {
          await fixture.waitFor(
            fixture.completionWasAttempted,
            (attempted) => attempted,
            reason: 'The worker should attempt to finish the claimed merge.',
          );
        });

        expect((await fixture.job(job))['state'], isNot('done'));
        expect(await fixture.merges(job), isEmpty);
        expect(await fixture.phantom(job), phantomBefore);
        expect(await fixture.attention(), attentionBefore);
      },
    );

    for (final (reason, description, expectsCard) in [
      ('deleted', 'a removed entry is skipped without an owner card', false),
      (
        'inactive',
        'an already linked entry is skipped without an owner card',
        false,
      ),
      (
        'self',
        'an invite back to the owner skips the merge and offers a link card',
        true,
      ),
      (
        'blocked',
        'a blocked join skips the merge and offers an owner-only link card',
        true,
      ),
    ]) {
      test(description, () async {
        final job = reason == 'blocked'
            ? await fixture.accept(await fixture.createInvite())
            : await fixture.enqueue(user: reason == 'self' ? _owner : _joined);
        switch (reason) {
          case 'deleted':
            await fixture.removePhantom(job);
          case 'inactive':
            await fixture.markInactive(job);
          case 'blocked':
            await fixture.blockJoined();
        }
        final before = await fixture.phantom(job);
        if (reason == 'deleted') {
          expect(before, isNull);
        } else {
          expect(
            before,
            containsPair(
              'merged_at',
              reason == 'inactive' ? isNotNull : isNull,
            ),
          );
        }
        final attentionBefore = await fixture.attention();
        if (reason == 'blocked') await fixture.expectMutualTrust();

        late _Row skipped;
        await fixture.withWorker((_) async {
          skipped = await fixture.waitForState(job, 'skipped');
          expect(skipped['reason'], reason);
        });

        expect(await fixture.phantom(job), before);
        expect(await fixture.merges(job), isEmpty);
        if (expectsCard) {
          await fixture.expectSingleOwnerCardAfterLaterSweep(
            job,
            skipped,
            attentionBefore,
          );
        } else {
          expect(await fixture.attention(), attentionBefore);
        }
        if (reason == 'blocked') await fixture.expectMutualTrust();
      });
    }

    test(
      'a temporary merge failure releases the lease and retries only when due',
      () async {
        final job = await fixture.enqueue();
        final phantomBefore = await fixture.phantom(job);
        final attentionBefore = await fixture.attention();
        await fixture.rejectMerge();
        final retry = await fixture.expectRetry(
          job,
          attempt: 1,
          backoffSeconds: 30,
        );
        final scheduledAt = retry['next_attempt_at']! as DateTime;
        expect(await fixture.phantom(job), phantomBefore);
        expect(await fixture.merges(job), isEmpty);
        expect(await fixture.attention(), attentionBefore);

        await fixture.allowMerge();
        final dueJob = await fixture.enqueue(user: _otherOwner);
        await fixture.withWorker((_) async {
          final done = await fixture.waitForState(dueJob, 'done');
          expect((done['done_at']! as DateTime).isBefore(scheduledAt), isTrue);
          expect(await fixture.job(job), retry);
          expect(await fixture.merges(job), isEmpty);
        });

        // The production worker isolate uses wall time. Move the persisted
        // deadline to the database clock only after the early sweep check.
        final dueAt = await fixture.releaseScheduledRetry(job, scheduledAt);
        final finished = await fixture.withWorker(
          (_) => fixture.waitForState(job, 'done'),
        );
        expect((finished['done_at']! as DateTime).isBefore(dueAt), isFalse);
        await fixture.expectMergedOnce(job, attempts: 2);
      },
    );

    test(
      'exhausting merge retries alerts the operator and records one owner link card',
      () async {
        final job = await fixture.enqueue();
        final attentionBefore = await fixture.attention();
        final phantomBefore = await fixture.phantom(job);
        await fixture.rejectMerge();
        const retryDelays = [30, 60, 120, 240, 480, 960, 960, 960, 960];
        for (final (index, delay) in retryDelays.indexed) {
          await fixture.expectRetry(
            job,
            attempt: index + 1,
            backoffSeconds: delay,
          );
          await fixture.makeDue(job);
        }

        late _Row failed;
        await fixture.withWorker((worker) async {
          failed = await fixture.waitForState(job, 'failed');
          expect(failed, containsPair('attempts', _retryLimit));
          expect(failed, containsPair('last_error', contains(_fault)));
          await fixture.waitFor(
            () async => worker.severe,
            (messages) => messages.any((message) => message.contains(job.id)),
            reason: 'An exhausted job should be named in a SEVERE log.',
          );
        });

        await fixture.allowMerge();
        await fixture.expectSingleOwnerCardAfterLaterSweep(
          job,
          failed,
          attentionBefore,
        );
        expect(await fixture.phantom(job), phantomBefore);
        expect(await fixture.merges(job), isEmpty);
      },
    );

    test(
      'the periodic sweep processes silent due jobs and leaves future work untouched',
      () async {
        final initial = await fixture.enqueue();
        late _Job future;
        await fixture.withWorker((_) async {
          await fixture.waitForState(initial, 'done');
          // These jobs share owner, joined user and origin. Only their
          // eligibility differs when the next sweep sees them.
          future = await fixture.enqueue(dueInFuture: true);
          final futureBefore = await fixture.job(future);
          final later = await fixture.enqueue();
          await fixture.waitForState(
            later,
            'done',
            limit: const Duration(seconds: 35),
          );
          await fixture.expectMergedOnce(later, attempts: 1);
          expect(await fixture.job(future), futureBefore);
          expect(await fixture.merges(future), isEmpty);
        });
        await fixture.expectMergedOnce(initial, attempts: 1);
        // With only the schedule changed, the same job is picked up.
        await fixture.makeDue(future);
        await fixture.withWorker((_) => fixture.waitForState(future, 'done'));
        await fixture.expectMergedOnce(future, attempts: 1);
      },
      timeout: const Timeout(Duration(seconds: 55)),
    );

    test(
      'a committed invite wakes the listening worker between sweeps',
      () async {
        final invitation = await fixture.createInvite();
        final warmup = await fixture.enqueue(owner: _otherOwner);
        final listener = await Connection.open(
          fixture.env.pgEndpoint,
          settings: fixture.env.pgEndpointSettings,
        );
        addTearDown(listener.close);
        final notified = Completer<String>();
        final subscription = listener.channels['phantom_merge_jobs'].listen((
          message,
        ) {
          if (!notified.isCompleted) notified.complete(message);
        });
        addTearDown(subscription.cancel);
        await listener.execute('LISTEN phantom_merge_jobs');

        await fixture.withWorker((_) async {
          // Begin after the first sweep, so a merge immediately after accept
          // cannot be supplied by the startup pass.
          final warmed = await fixture.poll(
            () => fixture.job(warmup),
            (row) => row['state'] == 'done',
            _passLimit,
          );
          final job = await fixture.accept(invitation);
          expect(await notified.future.timeout(_wakeLimit), invitation);
          await fixture.waitForState(job, 'done', limit: _wakeLimit);
          expect(
            warmed['state'],
            'done',
            reason: 'The startup sweep must have passed.',
          );
          await fixture.expectMergedOnce(job, attempts: 1);
        });
      },
    );
  }, skip: skip);
}

Env _workerEnv(Env db) => Env(
  environment: db.environment,
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
  sentryDsn: '',
  taskOnEmptyDelay: const Duration(milliseconds: 50),
);

class _Fixture {
  _Fixture(this.writer, this.env);

  final Connection writer;
  final Env env;

  Future<void> reset() async {
    await writer.execute('DROP FUNCTION IF EXISTS test_reject_merge() CASCADE');
    await writer.execute(
      'DROP FUNCTION IF EXISTS test_reject_completion() CASCADE',
    );
    await writer.execute(
      'DROP SEQUENCE IF EXISTS test_merge_completion_attempts',
    );
    await writer.execute(
      'TRUNCATE public."user", public.attention_occurrence CASCADE',
    );
    for (final (index, id) in [_owner, _joined, _otherOwner].indexed) {
      await sql(
        'INSERT INTO public."user" (id, display_name, public_key) VALUES (@id, @name, @key)',
        {
          'id': id,
          'name': 'Account ${index + 1}',
          'key': pgTestPublicKey('mergeworker', index + 1),
        },
      );
    }
  }

  Future<Result> sql(String query, [Map<String, Object?> args = const {}]) =>
      writer.execute(Sql.named(query), parameters: args, timeout: _passLimit);

  Future<List<_Row>> rows(
    String query, [
    Map<String, Object?> args = const {},
  ]) async => (await sql(query, args)).map((row) => row.toColumnMap()).toList();

  Future<String> createInvite() async {
    final phantom = await getIt<PhantomCase>().create(
      ownerId: _owner,
      name: 'Anna K.',
    );
    return getIt<PhantomCase>().saveInvite(
      ownerId: _owner,
      id: phantom,
      rotate: false,
    );
  }

  Future<_Job> accept(String invitation) async {
    expect(
      await getIt<InvitationCase>().acceptAsExisting(
        code: invitation,
        userId: _joined,
      ),
      InviteAcceptance.accepted,
    );
    final row = (await rows(
      'SELECT * FROM public.phantom_merge_job WHERE invitation_id = @id',
      {'id': invitation},
    )).single;
    return (
      id: row['id']! as String,
      phantom: row['phantom_id']! as String,
      owner: _owner,
      user: _joined,
    );
  }

  Future<_Job> enqueue({
    String owner = _owner,
    String user = _joined,
    bool dueInFuture = false,
  }) async {
    final phantom = await getIt<PhantomCase>().create(
      ownerId: owner,
      name: 'Anna K.',
    );
    final id = generateId('PM');
    await sql(
      '''
INSERT INTO public.phantom_merge_job
  (id, phantom_id, owner_id, user_id, origin, invitation_id, next_attempt_at)
VALUES
  (@id, @phantom, @owner, @user, 2, @invite,
   now() + CASE WHEN @future THEN interval '1 hour' ELSE interval '0 seconds' END)
''',
      {
        'id': id,
        'phantom': phantom,
        'owner': owner,
        'user': user,
        'future': dueInFuture,
        'invite': generateId('I'),
      },
    );
    return (id: id, phantom: phantom, owner: owner, user: user);
  }

  Future<_Row> job(_Job job) async => (await rows(
    'SELECT * FROM public.phantom_merge_job WHERE id = @id',
    {'id': job.id},
  )).single;

  Future<void> updateJob(_Job job, String set) => sql(
    'UPDATE public.phantom_merge_job SET $set WHERE id = @id',
    {'id': job.id},
  );

  Future<_Row?> phantom(_Job job) async => (await rows(
    'SELECT * FROM public.phantom WHERE id = @id',
    {'id': job.phantom},
  )).singleOrNull;

  Future<List<_Row>> merges(_Job job) => rows(
    'SELECT * FROM public.phantom_merge WHERE phantom_id = @id',
    {'id': job.phantom},
  );

  Future<void> removePhantom(_Job job) =>
      sql('DELETE FROM public.phantom WHERE id = @id', {'id': job.phantom});

  Future<void> markInactive(_Job job) => writer.executeWithOwnerScopes(
    [job.owner],
    Sql.named(
      'UPDATE public.phantom SET merged_at = now(), merge_origin = 3 WHERE id = @id',
    ),
    parameters: {'id': job.phantom},
  );

  Future<void> blockJoined() => sql(
    '''
INSERT INTO public.user_block (blocker_id, blocked_id, origin_id)
VALUES (@owner, @user, @user)
''',
    {'owner': _owner, 'user': _joined},
  );

  Future<void> expectMutualTrust() async {
    expect(
      await sql(
        '''
SELECT subject, object, amount FROM public.vote_user
WHERE (subject = @owner AND object = @user)
   OR (subject = @user AND object = @owner)
''',
        {'owner': _owner, 'user': _joined},
      ),
      unorderedEquals([
        [_owner, _joined, 1],
        [_joined, _owner, 1],
      ]),
    );
  }

  Future<List<_Row>> attention() => rows('''
SELECT occurrence.id, occurrence.actor_user_id,
       occurrence.immutable_payload::text AS payload,
       COALESCE(
         jsonb_agg(recipient.account_id ORDER BY recipient.account_id)
           FILTER (WHERE recipient.account_id IS NOT NULL),
         '[]'::jsonb
       )::text AS recipients,
       COALESCE(
         jsonb_agg(recipient.role_facts ORDER BY recipient.account_id)
           FILTER (WHERE recipient.account_id IS NOT NULL),
         '[]'::jsonb
       )::text AS role_facts
FROM public.attention_occurrence occurrence
LEFT JOIN public.attention_occurrence_recipient recipient
  ON recipient.occurrence_id = occurrence.id
GROUP BY occurrence.id
ORDER BY occurrence.id
''');

  Future<void> expectSingleOwnerCardAfterLaterSweep(
    _Job job,
    _Row terminal,
    List<_Row> attentionBefore,
  ) async {
    await expectOwnerCard(job, attentionBefore);
    // A fresh worker sees the terminal job alongside work it can still do.
    final probe = await enqueue(owner: _otherOwner);
    await withWorker((_) => waitForState(probe, 'done'));
    expect(await this.job(job), terminal);
    await expectOwnerCard(job, attentionBefore, ignorePhantom: probe.phantom);
  }

  Future<void> expectOwnerCard(
    _Job job,
    List<_Row> before, {
    String? ignorePhantom,
  }) async {
    final previousIds = before.map((row) => row['id']).toSet();
    final newCards = (await attention()).where((row) {
      return !previousIds.contains(row['id']) &&
          (ignorePhantom == null || !_hasId(row, ignorePhantom));
    }).toList();
    expect(newCards, hasLength(1));
    final card = newCards.single;
    expect(jsonDecode(card['recipients']! as String), [job.owner]);
    expect(
      _hasId(card, job.phantom),
      isTrue,
      reason: 'The action needs the private entry.',
    );
    expect(
      card['actor_user_id'] == job.user || _hasId(card, job.user),
      isTrue,
      reason: 'The action needs the account to link.',
    );
  }

  bool _hasId(_Row card, String id) =>
      _containsId(jsonDecode(card['payload']! as String), id) ||
      _containsId(jsonDecode(card['role_facts']! as String), id);

  bool _containsId(Object? value, String id) => switch (value) {
    List<Object?>() => value.any((item) => _containsId(item, id)),
    Map<String, Object?>() => value.values.any((item) => _containsId(item, id)),
    _ => value == id,
  };

  Future<void> expectMergedOnce(_Job job, {required int attempts}) async {
    final finished = await this.job(job);
    expect(finished, containsPair('state', 'done'));
    expect(finished, containsPair('done_at', isA<DateTime>()));
    expect(finished, containsPair('attempts', attempts));
    final history = await merges(job);
    expect(history, hasLength(1));
    final merge = history.single;
    expect(merge, containsPair('owner_id', job.owner));
    expect(merge, containsPair('user_id', job.user));
    expect(
      await phantom(job),
      allOf(
        containsPair('current_merge_id', merge['id']),
        containsPair('merged_user_id', job.user),
      ),
    );
  }

  Future<T> withWorker<T>(Future<T> Function(_RunningWorker) body) async {
    final worker = await _RunningWorker.start(env);
    try {
      return await body(worker);
    } finally {
      await worker.close();
    }
  }

  Future<_RunningWorker> startWorker() async {
    final worker = await _RunningWorker.start(env);
    addTearDown(worker.close);
    return worker;
  }

  Future<Connection> openGate() async {
    final gate = await Connection.open(
      env.pgEndpoint,
      settings: env.pgEndpointSettings,
    );
    addTearDown(gate.close);
    return gate;
  }

  Future<void> withOwnerHeld(_Job job, Future<void> Function() action) =>
      whileOwnerGraphScopeHeld(
        getIt<OwnerGraphTransactionPort>(),
        job.owner,
        action,
      );

  Future<({_Row row, int backend})> waitForClaimBehindScope(_Job job) async {
    final lease = await waitForJob(
      job,
      (row) => row['lease_owner'] != null,
      reason: 'A worker must commit the claim while the owner scope is held.',
      limit: _waitingLimit,
    );
    expect(lease['state'], 'queued');
    expect(lease['attempts'], 1);
    expect(
      (lease['lease_until']! as DateTime).isAfter(DateTime.timestamp()),
      isTrue,
    );
    final backends = await waitForScopeWaiters(job, {}, 1);
    return (row: lease, backend: backends.single);
  }

  Future<Set<int>> ownerScopeBackends(_Job job, {bool granted = false}) async =>
      {
        for (final row in await sql(
          '''
WITH scope AS (SELECT hashtextextended('owner_graph:' || @owner, 4242) AS key)
SELECT pid FROM pg_locks, scope
  WHERE locktype = 'advisory' AND objsubid = 1 AND granted = @granted
    AND database = (SELECT oid FROM pg_database WHERE datname = current_database())
    AND classid::bigint = ((key >> 32) & 4294967295)
    AND objid::bigint = (key & 4294967295)
''',
          {'owner': job.owner, 'granted': granted},
        ))
          row.single! as int,
      };

  Future<Set<int>> waitForScopeWaiters(
    _Job job,
    Set<int> expected,
    int count,
  ) => waitFor(
    () => ownerScopeBackends(job),
    (backends) => backends.length == count && backends.containsAll(expected),
    reason: 'The expected sessions must reach the held owner scope.',
    limit: _waitingLimit,
  );

  Future<void> waitForBackendBlockedBy(int backend, int blocker) async {
    await waitFor(
      () async =>
          (await sql(
            '''
SELECT @blocker = ANY(pg_blocking_pids(pid))
FROM pg_stat_activity
WHERE datname = current_database() AND pid = @backend
''',
            {'backend': backend, 'blocker': blocker},
          )).singleOrNull?.single ==
          true,
      (waiting) => waiting,
      reason: 'Backend $backend must wait for session $blocker.',
      limit: _waitingLimit,
    );
  }

  Future<_Row> waitForState(
    _Job job,
    String state, {
    Duration limit = _passLimit,
  }) => waitForJob(
    job,
    (row) => row['state'] == state,
    reason: 'The merge worker should move the job to $state.',
    limit: limit,
  );

  Future<_Row> waitForJob(
    _Job job,
    bool Function(_Row) matches, {
    required String reason,
    Duration limit = _passLimit,
  }) => waitFor(() => this.job(job), matches, reason: reason, limit: limit);

  Future<T> waitFor<T>(
    Future<T> Function() read,
    bool Function(T) matches, {
    required String reason,
    Duration limit = _passLimit,
  }) async {
    final actual = await poll(read, matches, limit);
    expect(actual, predicate<T>(matches), reason: reason);
    return actual;
  }

  Future<T> poll<T>(
    Future<T> Function() read,
    bool Function(T) matches,
    Duration limit,
  ) async {
    final clock = Stopwatch()..start();
    var actual = await read().timeout(limit);
    while (!matches(actual)) {
      final remaining = limit - clock.elapsed;
      if (remaining <= Duration.zero) break;
      await Future<void>.delayed(const Duration(milliseconds: 20));
      if (clock.elapsed >= limit) break;
      final previous = actual;
      actual = await read().timeout(
        limit - clock.elapsed,
        onTimeout: () => previous,
      );
    }
    return actual;
  }

  Future<_Row> expectRetry(
    _Job job, {
    required int attempt,
    required int backoffSeconds,
  }) async {
    final started = DateTime.timestamp();
    return withWorker((_) async {
      final retry = await waitForJob(
        job,
        (row) =>
            row['attempts'] == attempt &&
            row['last_error'] != null &&
            row['lease_owner'] == null,
        reason: 'The worker should preserve the error and release the lease.',
      );
      final observed = DateTime.timestamp();
      expect(retry, containsPair('state', 'queued'));
      expect(retry, containsPair('last_error', contains(_fault)));
      expect(retry, containsPair('lease_until', isNull));
      final delay = Duration(seconds: backoffSeconds);
      final due = retry['next_attempt_at']! as DateTime;
      expect(due.isBefore(started.add(delay)), isFalse);
      expect(due.isAfter(observed.add(delay)), isFalse);
      expect(due.isAfter(observed), isTrue);
      return retry;
    });
  }

  // Advance the fixture's eligibility without sleeping through the backoff.
  Future<void> makeDue(_Job job) =>
      updateJob(job, "next_attempt_at = now() - interval '1 second'");

  Future<DateTime> releaseScheduledRetry(_Job job, DateTime scheduledAt) async {
    final rows = await sql(
      '''
UPDATE public.phantom_merge_job
SET next_attempt_at = clock_timestamp()
WHERE id = @id AND state = 'queued' AND attempts = 1 AND lease_owner IS NULL
  AND next_attempt_at = @scheduledAt::timestamptz
  AND next_attempt_at > clock_timestamp()
RETURNING next_attempt_at
''',
      {
        'id': job.id,
        'scheduledAt': TypedValue(Type.timestampTz, scheduledAt),
      },
    );
    expect(
      rows,
      hasLength(1),
      reason:
          'The scheduled retry must still be waiting at the fixture deadline.',
    );
    return rows.single.single! as DateTime;
  }

  Future<void> rejectMerge() async {
    await sql('''
CREATE FUNCTION test_reject_merge() RETURNS trigger LANGUAGE plpgsql AS
\$\$
BEGIN
  RAISE EXCEPTION '$_fault';
END;
\$\$
''');
    await sql('''
CREATE TRIGGER test_reject_merge BEFORE INSERT ON public.phantom_merge
FOR EACH ROW EXECUTE FUNCTION test_reject_merge()
''');
  }

  Future<void> allowMerge() =>
      sql('DROP TRIGGER test_reject_merge ON public.phantom_merge');

  Future<void> rejectCompletion() async {
    await sql('CREATE SEQUENCE test_merge_completion_attempts');
    await sql(r'''
CREATE FUNCTION test_reject_completion() RETURNS trigger LANGUAGE plpgsql AS
$$
BEGIN
  PERFORM nextval('test_merge_completion_attempts');
  RETURN NULL;
END;
$$
''');
    await sql('''
CREATE TRIGGER test_reject_completion BEFORE UPDATE ON public.phantom_merge_job
FOR EACH ROW WHEN (NEW.state = 'done') EXECUTE FUNCTION test_reject_completion()
''');
  }

  Future<bool> completionWasAttempted() async =>
      (await sql(
            'SELECT is_called FROM test_merge_completion_attempts',
          )).single.single!
          as bool;
}

class _RunningWorker {
  _RunningWorker(this._isolate, this._events);

  final Isolate _isolate;
  final ReceivePort _events;
  final _ready = Completer<void>();
  final _exited = Completer<void>();
  final severe = <String>[];
  late final SendPort _stop;
  Object? _error;
  bool _closed = false;

  static Future<_RunningWorker> start(Env env) async {
    final events = ReceivePort();
    final isolate = await Isolate.spawn(
      _serveObservedWorker,
      (sendPort: events.sendPort, env: env),
      onError: events.sendPort,
      onExit: events.sendPort,
    );
    final worker = _RunningWorker(isolate, events);
    events.listen(worker._receive);
    try {
      await worker._ready.future.timeout(_passLimit);
      return worker;
    } on Object {
      isolate.kill(priority: Isolate.immediate);
      events.close();
      rethrow;
    }
  }

  void _receive(Object? message) {
    switch (message) {
      case SendPort():
        _stop = message;
      case 'worker-ready':
        _ready.complete();
      case ('severe', final String text):
        severe.add(text);
      case [final String error, final String stack]:
        _error = RemoteError(error, stack);
        if (!_ready.isCompleted) _ready.completeError(_error!);
      case null:
        if (!_exited.isCompleted) _exited.complete();
    }
  }

  Future<void> close() async {
    if (_closed) return;
    _closed = true;
    try {
      _stop.send(null);
      await _exited.future.timeout(_passLimit);
      expect(_error, isNull, reason: 'The task worker must shut down cleanly.');
    } finally {
      _isolate.kill(priority: Isolate.immediate);
      _events.close();
    }
  }
}

Future<void> _serveObservedWorker(({SendPort sendPort, Env env}) args) async {
  final logs = Logger.root.onRecord.listen((record) {
    if (record.level == Level.SEVERE) {
      args.sendPort.send(('severe', record.message));
    }
  });
  try {
    await runZoned(
      () => serveTask(args),
      zoneSpecification: ZoneSpecification(
        print: (_, _, _, line) {
          if (line.contains(' started at ')) args.sendPort.send('worker-ready');
        },
      ),
    );
  } finally {
    await logs.cancel();
  }
}
