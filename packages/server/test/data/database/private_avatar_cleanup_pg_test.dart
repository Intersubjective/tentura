@Tags(['pg'])
@TestOn('vm')
library;

import 'package:mockito/mockito.dart';
import 'package:postgres/postgres.dart';
import 'package:test/test.dart';
import 'package:uuid/uuid.dart';

import 'package:tentura_server/app/di.dart';
import 'package:tentura_server/data/database/tentura_db.dart'
    show driftRuntimeOptions;
import 'package:tentura_server/domain/port/private_object_gc_port.dart';
import 'package:tentura_server/domain/port/remote_storage_port.dart';
import 'package:tentura_server/domain/use_case/phantom_case.dart';
import 'package:tentura_server/domain/use_case/task_worker_case.dart';
import 'package:tentura_server/domain/use_case/user_erasure_case.dart';
import 'package:tentura_server/utils/id.dart';

import '../../support/disposable_pg_target.dart';
import '../../support/session_database_di_harness.dart';

const _leaseDuration = Duration(minutes: 2);
const _firstRetryDelay = Duration(seconds: 30);
const _lastAttempt = 10;

Future<void> main() async {
  final target = DisposablePgTarget.fromNamedEnvironment(
    envVarName: 'TENTURA_PRIVATE_AVATAR_CLEANUP_TEST_DB',
    defaultNamePrefix: 'tentura_test_private_avatar_gc',
    useDevBindings: true,
  );
  final skip = await pgSkipReason(target);

  group('Private avatar storage', () {
    late _Fixture db;
    final remote = _RecordingStorage();

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
      getIt.registerSingleton<RemoteStoragePort>(remote);
      await configureSessionDatabaseTestGraph(target.databaseEnv);
      expect(getIt<RemoteStoragePort>(), same(remote));
      db = _Fixture(session.writer);
    });

    test('requires a subject', () async {
      final owner = await db.user();
      await db.requireTable('person_private_avatar');
      await expectLater(
        db.insertAvatar(owner),
        _sqlState('23514'),
      );
    });

    test('rejects a row naming both kinds of subject', () async {
      final owner = await db.user();
      final subject = await db.user();
      final phantom = await db.phantom(owner);
      await db.requireTable('person_private_avatar');
      await expectLater(
        db.insertAvatar(owner, subject: subject, phantom: phantom),
        _sqlState('23514'),
      );
    });

    test('rejects an avatar on the owner’s own account', () async {
      final owner = await db.user();
      await db.requireTable('person_private_avatar');
      await expectLater(
        db.insertAvatar(owner, subject: owner),
        _sqlState('23514'),
      );
    });

    for (final onPhantom in [false, true]) {
      test(
        onPhantom
            ? 'allows one private avatar per owner and phantom'
            : 'allows one private avatar per owner and account',
        () async {
          final owner = await db.user();
          final subject = onPhantom ? null : await db.user();
          final phantom = onPhantom ? await db.phantom(owner) : null;
          final first = await db.insertAvatar(
            owner,
            subject: subject,
            phantom: phantom,
          );
          await expectLater(
            db.insertAvatar(owner, subject: subject, phantom: phantom),
            _sqlState('23505'),
          );
          expect(await db.avatarOwners(first), [owner]);
        },
      );
    }

    test(
      'avatars with different owners or subjects can share a stored image',
      () async {
        final owner = await db.user();
        final secondOwner = await db.user();
        final subject = await db.user();
        final secondSubject = await db.user();
        final key = await db.insertAvatar(owner, subject: subject);
        await db.insertAvatar(secondOwner, subject: subject, key: key);
        await db.insertAvatar(owner, subject: secondSubject, key: key);
        final references = await db.query(
          '''
SELECT owner_id, subject_user_id, subject_phantom_id
FROM public.person_private_avatar WHERE object_key = @key
''',
          {'key': key},
        );
        expect(
          references,
          unorderedEquals([
            [owner, subject, null],
            [secondOwner, subject, null],
            [owner, secondSubject, null],
          ]),
        );
      },
    );

    test('replacing an avatar key queues only the previous key', () async {
      final owner = await db.user();
      final oldKey = await db.insertAvatar(owner, subject: await db.user());
      final newKey = _key(owner);
      expect(await db.queue(oldKey), isEmpty);
      final changed = await db.writer.executeWithOwnerScopes(
        [owner],
        Sql.named('''
UPDATE public.person_private_avatar SET object_key = @new
WHERE object_key = @old RETURNING object_key
'''),
        parameters: {'old': oldKey, 'new': newKey},
      );
      expect(changed.single.single, newKey);
      expect(await db.queue(oldKey), hasLength(1));
      expect(await db.queue(newKey), isEmpty);
    });

    test(
      'changing image metadata leaves the object out of the queue',
      () async {
        final owner = await db.user();
        final key = await db.insertAvatar(owner, subject: await db.user());
        final changed = await db.writer.executeWithOwnerScopes(
          [owner],
          Sql.named('''
UPDATE public.person_private_avatar
SET blurhash = 'LKO2?U%2Tw=w]~RBVZRi};RPxuwH', width = 96, height = 64
WHERE object_key = @key RETURNING object_key, blurhash, width, height
'''),
          parameters: {'key': key},
        );
        expect(changed.single, [key, 'LKO2?U%2Tw=w]~RBVZRi};RPxuwH', 96, 64]);
        expect(await db.queue(key), isEmpty);
      },
    );

    test('deleting an avatar queues an immediately eligible job', () async {
      final owner = await db.user();
      final key = await db.insertAvatar(owner, subject: await db.user());
      expect(await db.queue(key), isEmpty);
      await db.deleteAvatar(owner, key);
      expect(await db.avatarOwners(key), isEmpty);
      expect((await db.queue(key)).single, {
        'enqueued_at': isA<DateTime>(),
        'attempts': 0,
        'lease_owner': null,
        'lease_until': null,
        'next_attempt_at': isA<DateTime>().having(
          (due) => due.isAfter(DateTime.timestamp()),
          'is in the future',
          isFalse,
        ),
        'last_error': null,
      });
    });

    test(
      'deleting a second reference preserves existing queue progress',
      () async {
        final owner = await db.user();
        final secondOwner = await db.user();
        final subject = await db.user();
        final key = await db.insertAvatar(owner, subject: subject);
        await db.insertAvatar(secondOwner, subject: subject, key: key);
        await db.deleteAvatar(owner, key);
        final originalEnqueueTime = (await db.queue(key)).single['enqueued_at'];
        expect(originalEnqueueTime, isA<DateTime>());
        await db.query(
          '''
UPDATE public.private_object_gc
SET attempts = 3
WHERE object_key = @key
''',
          {'key': key},
        );
        final beforeSecondDelete = (await db.queue(key)).single;
        expect(beforeSecondDelete['attempts'], 3);
        expect(beforeSecondDelete['enqueued_at'], originalEnqueueTime);

        await db.deleteAvatar(secondOwner, key);

        expect(await db.avatarOwners(key), isEmpty);
        final remaining = await db.queue(key);
        expect(remaining, [beforeSecondDelete]);
        expect(remaining.single['enqueued_at'], originalEnqueueTime);
        expect(remaining.single['attempts'], 3);
      },
    );

    test('deleting a phantom queues its private avatar', () async {
      final owner = await db.user();
      final phantom = await db.phantom(owner);
      final key = await db.insertAvatar(owner, phantom: phantom);
      expect(await db.queue(key), isEmpty);
      expect(
        await getIt<PhantomCase>().delete(ownerId: owner, id: phantom),
        isTrue,
      );
      expect(await db.avatarOwners(key), isEmpty);
      expect(await db.queue(key), hasLength(1));
    });

    for (final eraseOwner in [true, false]) {
      test(
        eraseOwner
            ? 'erasing the owner queues their private avatar'
            : 'erasing the subject queues the private avatar on their account',
        () async {
          final owner = await db.user();
          final subject = await db.user();
          final key = await db.insertAvatar(owner, subject: subject);
          expect(await db.queue(key), isEmpty);
          final erased = eraseOwner ? owner : subject;
          expect(
            await getIt<AccountErasureCase>().deleteById(id: erased),
            isTrue,
          );
          expect(
            await db.query(
              'SELECT id FROM public."user" WHERE id = @id',
              {'id': erased},
            ),
            isEmpty,
          );
          expect(await db.avatarOwners(key), isEmpty);
          expect(await db.queue(key), hasLength(1));
        },
      );
    }

    group('Private object cleanup repository', () {
      final now = DateTime.utc(2030, 1, 1, 12);
      final expiry = now.add(_leaseDuration);

      test('only leases a key again at or after its lease expires', () async {
        final repository = getIt<PrivateObjectGcPort>();
        await db.clearQueue();
        final key = _key(await db.user());
        await db.enqueue(key, due: now);

        final first = await repository.claim(leaseOwner: 'w1', now: now);
        expect(first.map(_leaseDetails), [(objectKey: key, attempts: 1)]);
        final originalLease = (await db.queue(key)).single;
        expect(originalLease, containsPair('lease_owner', 'w1'));
        expect(originalLease, containsPair('lease_until', expiry));
        expect(originalLease, containsPair('attempts', 1));

        expect(await repository.claim(leaseOwner: 'w2', now: now), isEmpty);
        expect(
          await repository.claim(
            leaseOwner: 'w2',
            now: expiry.subtract(const Duration(microseconds: 1)),
          ),
          isEmpty,
        );
        expect(await db.queue(key), [originalLease]);

        final reclaimed = await repository.claim(leaseOwner: 'w2', now: expiry);
        expect(reclaimed.map(_leaseDetails), [(objectKey: key, attempts: 2)]);
        final replacementLease = (await db.queue(key)).single;
        expect(replacementLease, containsPair('lease_owner', 'w2'));
        expect(
          replacementLease,
          containsPair('lease_until', expiry.add(_leaseDuration)),
        );
        expect(replacementLease, containsPair('attempts', 2));
      });

      test('returns only due keys with attempts below the cap', () async {
        final repository = getIt<PrivateObjectGcPort>();
        await db.clearQueue();
        final owner = await db.user();
        final eligible = _key(owner);
        final future = _key(owner);
        final exhausted = _key(owner);
        await db.enqueue(eligible, due: now, attempts: _lastAttempt - 1);
        await db.enqueue(future, due: now.add(const Duration(microseconds: 1)));
        await db.enqueue(exhausted, due: now, attempts: _lastAttempt);

        final found = await repository.claim(leaseOwner: 'w1', now: now);

        expect(found.map(_leaseDetails), [
          (objectKey: eligible, attempts: _lastAttempt),
        ]);
        expect((await db.queue(future)).single['attempts'], 0);
        expect((await db.queue(exhausted)).single['attempts'], _lastAttempt);
      });

      test('only the lease holder can reschedule a job', () async {
        final repository = getIt<PrivateObjectGcPort>();
        await db.clearQueue();
        final key = _key(await db.user());
        await db.enqueue(key, due: now);
        final claimed = await repository.claim(leaseOwner: 'w1', now: now);
        expect(claimed.map(_leaseDetails), [(objectKey: key, attempts: 1)]);
        final leased = (await db.queue(key)).single;
        final retryAt = now.add(const Duration(minutes: 3));
        final error = 'storage timeout: ${'x' * 1000} trailing text';

        expect(
          await repository.fail(
            objectKey: key,
            leaseOwner: 'w2',
            retryAt: retryAt,
            error: error,
          ),
          isFalse,
        );
        expect(await db.queue(key), [leased]);

        expect(
          await repository.fail(
            objectKey: key,
            leaseOwner: 'w1',
            retryAt: retryAt,
            error: error,
          ),
          isTrue,
        );
        expect((await db.queue(key)).single, {
          'enqueued_at': leased['enqueued_at'],
          'attempts': 1,
          'lease_owner': null,
          'lease_until': null,
          'next_attempt_at': retryAt,
          'last_error': error.substring(0, 1000),
        });
      });

      test('only the lease holder can complete a job', () async {
        final repository = getIt<PrivateObjectGcPort>();
        await db.clearQueue();
        final key = _key(await db.user());
        await db.enqueue(key, due: now);
        final claimed = await repository.claim(leaseOwner: 'w1', now: now);
        expect(claimed.map(_leaseDetails), [(objectKey: key, attempts: 1)]);
        final leased = (await db.queue(key)).single;

        expect(
          await repository.complete(objectKey: key, leaseOwner: 'w2'),
          isFalse,
        );
        expect(await db.queue(key), [leased]);
        expect(
          await repository.complete(objectKey: key, leaseOwner: 'w1'),
          isTrue,
        );
        expect(await db.queue(key), isEmpty);
      });
    });

    group('Object cleanup worker', () {
      late TaskWorkerCase worker;

      setUp(() async {
        remote
          ..removed.clear()
          ..onRemove = null;
        await getIt.resetLazySingleton<TaskWorkerCase>();
        worker = await getIt.getAsync<TaskWorkerCase>();
      });

      test('removes an unreferenced object using its stored key', () async {
        await db.clearQueue();
        final key = _key(await db.user());
        await db.enqueue(key);
        await worker.tick();
        expect(remote.removed, [key]);
        expect(await db.queue(key), isEmpty);
      });

      test(
        'collects available work while another queue row is locked',
        () async {
          await db.clearQueue();
          final owner = await db.user();
          final locked = _key(owner);
          final available = _key(owner);
          await db.enqueue(locked);
          await db.enqueue(available);
          final before = await db.queue(locked);

          const limit = Duration(seconds: 10);
          Future<void>? sweep;
          try {
            await db.writer.runTx((tx) async {
              await tx.execute(
                Sql.named('''
SELECT object_key FROM public.private_object_gc
WHERE object_key = @key FOR UPDATE
'''),
                parameters: {'key': locked},
              );
              final running = worker.tick();
              sweep = running;
              await running.timeout(limit);
            });
          } finally {
            // Release the lock before joining a sweep that timed out behind it.
            await sweep?.timeout(limit);
          }

          expect(remote.removed, [available]);
          expect(await db.queue(available), isEmpty);
          expect(await db.queue(locked), before);
        },
      );

      test(
        'keeps shared objects until the last reference is removed',
        () async {
          final owner = await db.user();
          final secondOwner = await db.user();
          final subject = await db.user();
          final key = await db.insertAvatar(owner, subject: subject);
          await db.insertAvatar(secondOwner, subject: subject, key: key);
          await db.clearQueue();
          await db.deleteAvatar(owner, key);
          expect(await db.queue(key), hasLength(1));

          await worker.tick();

          expect(remote.removed, isEmpty);
          expect(await db.avatarOwners(key), [secondOwner]);
          expect(await db.queue(key), isEmpty);
          await db.deleteAvatar(secondOwner, key);
          expect(await db.queue(key), hasLength(1));
        },
      );

      test(
        'reclaims expired leases and skips live, future and exhausted work',
        () async {
          await db.clearQueue();
          final owner = await db.user();
          final now = DateTime.timestamp();
          final expired = _key(owner);
          final live = _key(owner);
          final future = _key(owner);
          final exhausted = _key(owner);
          final overLimit = _key(owner);
          await db.enqueue(
            expired,
            attempts: 1,
            leaseOwner: 'previous-worker',
            leaseUntil: now.subtract(const Duration(minutes: 5)),
          );
          await db.enqueue(
            live,
            attempts: 1,
            leaseOwner: 'active-worker',
            leaseUntil: now.add(const Duration(hours: 1)),
          );
          await db.enqueue(future, due: now.add(const Duration(hours: 1)));
          await db.enqueue(exhausted, attempts: _lastAttempt);
          await db.enqueue(overLimit, attempts: _lastAttempt + 1);
          final deferred = [live, future, exhausted, overLimit];
          final before = {for (final key in deferred) key: await db.queue(key)};
          Map<String, Object?>? claimed;
          remote.onRemove = (key) async {
            if (key == expired) claimed = (await db.queue(key)).single;
          };

          final lowerBound = DateTime.timestamp();
          await worker.tick();
          final upperBound = DateTime.timestamp();

          expect(remote.removed, [expired]);
          expect(claimed, containsPair('attempts', 2));
          expect(
            claimed,
            containsPair(
              'lease_owner',
              allOf(
                isA<String>(),
                isNotEmpty,
                isNot('previous-worker'),
              ),
            ),
          );
          expect(
            claimed,
            containsPair(
              'lease_until',
              _timestampBetween(
                lowerBound.add(_leaseDuration),
                upperBound.add(_leaseDuration),
              ),
            ),
          );
          expect(await db.queue(expired), isEmpty);
          for (final key in deferred) {
            expect(await db.queue(key), before[key], reason: key);
          }
        },
      );

      for (final longError in [false, true]) {
        test(
          longError
              ? 'limits the persisted storage error to 1000 characters'
              : 'retries a failed storage deletion after the first backoff',
          () async {
            await db.clearQueue();
            final key = _key(await db.user());
            await db.enqueue(key);
            final error = StateError(
              longError
                  ? 'storage unavailable ${'x' * 1000} tail'
                  : 'storage unavailable',
            );
            DateTime? leaseUntil;
            remote.onRemove = (key) async {
              final leased = (await db.queue(key)).single;
              leaseUntil = leased['lease_until'] as DateTime?;
              throw error;
            };
            final text = error.toString();

            await worker.tick();

            expect(remote.removed, [key]);
            final row = (await db.queue(key)).single;
            expect(
              row['last_error'],
              longError ? text.substring(0, 1000) : text,
            );
            expect(row['attempts'], 1);
            expect(row['lease_owner'], isNull);
            expect(row['lease_until'], isNull);
            expect(leaseUntil, isNotNull);
            expect(
              row['next_attempt_at'],
              leaseUntil!.subtract(_leaseDuration).add(_firstRetryDelay),
            );
          },
        );
      }

      for (final storageError in [false, true]) {
        test(
          storageError
              ? 'a worker that lost its lease cannot reschedule a failed deletion'
              : 'a worker that lost its lease cannot complete the job',
          () async {
            await db.clearQueue();
            final key = _key(await db.user());
            await db.enqueue(key);
            List<Map<String, Object?>>? otherLease;
            remote.onRemove = (removedKey) async {
              await db.query(
                '''
UPDATE public.private_object_gc
SET lease_owner = 'other-worker', lease_until = now() + interval '2 minutes',
    attempts = attempts + 1
WHERE object_key = @key
''',
                {'key': removedKey},
              );
              otherLease = await db.queue(removedKey);
              if (storageError) throw StateError('storage unavailable');
            };

            await worker.tick();

            expect(remote.removed, [key]);
            expect(otherLease, [containsPair('lease_owner', 'other-worker')]);
            expect(await db.queue(key), otherLease);
          },
        );
      }
    });
  }, skip: skip);
}

String _key(String owner) => 'private/$owner/${const Uuid().v4()}.jpg';

Matcher _timestampBetween(DateTime start, DateTime end) =>
    isA<DateTime>().having(
      (time) => time.microsecondsSinceEpoch,
      'microseconds since epoch',
      inInclusiveRange(
        start.microsecondsSinceEpoch,
        end.microsecondsSinceEpoch,
      ),
    );

Matcher _sqlState(String code) => throwsA(
  isA<ServerException>().having((error) => error.code, 'SQLSTATE', code),
);

({String objectKey, int attempts}) _leaseDetails(PrivateObjectGcLease lease) =>
    (objectKey: lease.objectKey, attempts: lease.attempts);

final class _Fixture {
  _Fixture(this.writer);

  final Connection writer;

  Future<Result> query(String sql, Map<String, Object?> parameters) =>
      writer.execute(Sql.named(sql), parameters: parameters);

  Future<void> requireTable(String table) async {
    final rows = await query(
      'SELECT to_regclass(@table) IS NOT NULL',
      {'table': 'public.$table'},
    );
    expect(
      rows.single.single,
      isTrue,
      reason: 'The migrated schema must provide public.$table',
    );
  }

  Future<String> user() async {
    final id = generateId('U');
    await query(
      '''
INSERT INTO public."user" (id, display_name, public_key)
VALUES (@id, @id, @key)
''',
      {'id': id, 'key': 'pk-$id'},
    );
    return id;
  }

  Future<String> phantom(String owner) =>
      getIt<PhantomCase>().create(ownerId: owner, name: 'Anna');

  Future<String> insertAvatar(
    String owner, {
    String? subject,
    String? phantom,
    String? key,
  }) async {
    await requireTable('person_private_avatar');
    final objectKey = key ?? _key(owner);
    final rows = await writer.executeWithOwnerScopes(
      [owner],
      Sql.named('''
INSERT INTO public.person_private_avatar
  (owner_id, subject_user_id, subject_phantom_id, object_key, blurhash, width, height, created_at)
VALUES (@owner, @subject, @phantom, @key, 'LEHV6nWB2yk8pyo0adR*.7kCMdnj', 48, 48, now())
RETURNING object_key
'''),
      parameters: {
        'owner': owner,
        'subject': subject,
        'phantom': phantom,
        'key': objectKey,
      },
    );
    expect(rows.single.single, objectKey);
    return objectKey;
  }

  Future<List<Object?>> avatarOwners(String key) async {
    final rows = await query(
      'SELECT owner_id FROM public.person_private_avatar WHERE object_key = @key',
      {'key': key},
    );
    return [for (final row in rows) row.single];
  }

  Future<void> deleteAvatar(String owner, String key) async {
    final rows = await writer.executeWithOwnerScopes(
      [owner],
      Sql.named('''
DELETE FROM public.person_private_avatar
WHERE owner_id = @owner AND object_key = @key RETURNING object_key
'''),
      parameters: {'owner': owner, 'key': key},
    );
    expect(rows.single.single, key);
  }

  Future<List<Map<String, Object?>>> queue(String key) async {
    await requireTable('private_object_gc');
    final rows = await query(
      '''
SELECT enqueued_at, attempts, lease_owner, lease_until, next_attempt_at, last_error
FROM public.private_object_gc WHERE object_key = @key
''',
      {'key': key},
    );
    return [for (final row in rows) row.toColumnMap()];
  }

  Future<void> clearQueue() async {
    await requireTable('private_object_gc');
    await writer.execute('DELETE FROM public.private_object_gc');
  }

  Future<void> enqueue(
    String key, {
    int attempts = 0,
    String? leaseOwner,
    DateTime? leaseUntil,
    DateTime? due,
  }) async {
    await query(
      '''
INSERT INTO public.private_object_gc
  (object_key, attempts, lease_owner, lease_until, next_attempt_at)
VALUES (@key, @attempts, @owner, @lease_until, @due)
''',
      {
        'key': key,
        'attempts': attempts,
        'owner': leaseOwner,
        'lease_until': leaseUntil,
        'due': due ?? DateTime.timestamp().subtract(const Duration(minutes: 1)),
      },
    );
  }
}

final class _RecordingStorage extends Fake implements RemoteStoragePort {
  final removed = <String>[];
  Future<void> Function(String)? onRemove;

  @override
  Future<void> removeObject(String path) async {
    removed.add(path);
    await onRemove?.call(path);
  }
}
