@Tags(['pg'])
library;

import 'dart:async';
import 'dart:io';

import 'package:injectable/injectable.dart' show Environment;
import 'package:postgres/postgres.dart';
import 'package:test/test.dart';

import 'package:tentura_server/data/database/migration/_migrations.dart';
import 'package:tentura_server/data/database/tentura_db.dart'
    hide isNotNull, isNull;
import 'package:tentura_server/data/repository/forward_edge_repository.dart';
import 'package:tentura_server/data/repository/user_availability_repository.dart';
import 'package:tentura_server/domain/entity/forward_batch_create_result.dart';
import 'package:tentura_server/env.dart';

import '../../support/pg_test_public_keys.dart';

Future<void> main() async {
  final target = _DisposablePgTarget.fromEnvironment();
  final reachable = await _canConnect(target.adminEnv);
  final skipReason = reachable
      ? false
      : 'Postgres admin database not reachable for disposable test target';

  group('ForwardEdgeRepository.createBatch — availability linearization', () {
    late Connection writer;
    late TenturaDb db;
    late ForwardEdgeRepository forwardRepo;
    late UserAvailabilityRepository availabilityRepo;

    const beaconId = 'Bfwdaavail01';
    const authorId = 'Ufwdaauth01';
    const senderId = 'Ufwdasend01';
    const recipientId = 'Ufwdarecip01';
    final futureResumeOn = DateTime.utc(2026, 9, 15);

    setUpAll(() async {
      if (skipReason != false) {
        return;
      }
      await target.recreate();
      writer = await Connection.open(
        target.databaseEnv.pgEndpoint,
        settings: target.databaseEnv.pgEndpointSettings,
      );
      await writer.execute('SET check_function_bodies = false');
      await migrateDbSchema(writer);

      db = TenturaDb(target.databaseEnv);
      forwardRepo = ForwardEdgeRepository(db);
      availabilityRepo = UserAvailabilityRepository(db);
    });

    setUp(() async {
      if (skipReason != false) {
        return;
      }
      await writer.execute(
        "DELETE FROM public.beacon_forward_edge WHERE beacon_id = '$beaconId'",
      );
      await writer.execute(
        "DELETE FROM public.user_availability WHERE user_id LIKE 'Ufwda%'",
      );
      await writer.execute(
        "DELETE FROM public.beacon WHERE id = '$beaconId'",
      );
      await writer.execute(
        '''DELETE FROM public."user" WHERE id LIKE 'Ufwda%' ''',
      );
      await _seedFixture(writer);
    });

    tearDownAll(() async {
      if (skipReason != false) {
        return;
      }
      await db.close();
      await writer.close();
      await target.drop();
    });

    Future<int> activeEdgeCount({
      required String sender,
      required String recipient,
    }) async {
      final rows = await writer.execute(
        Sql.named(r'''
SELECT COUNT(*)::int
FROM public.beacon_forward_edge
WHERE beacon_id = @beaconId
  AND sender_id = @senderId
  AND recipient_id = @recipientId
  AND cancelled_at IS NULL
'''),
        parameters: {
          'beaconId': beaconId,
          'senderId': sender,
          'recipientId': recipient,
        },
      );
      return rows.single.single! as int;
    }

    test(
      'pause linearizes before forward: forward is availability-skipped with no edge',
      () async {
        final blockerDb = TenturaDb(target.databaseEnv);
        final pauseDb = TenturaDb(target.databaseEnv);
        final forwardDb = TenturaDb(target.databaseEnv);
        final pauseRepo = UserAvailabilityRepository(pauseDb);
        final raceForwardRepo = ForwardEdgeRepository(forwardDb);

        final blockerReady = Completer<void>();
        final releaseBlocker = Completer<void>();
        final pauseDone = Completer<void>();
        final forwardDone = Completer<void>();
        Object? pauseError;
        Object? forwardError;
        ForwardBatchCreateResult? forwardResult;

        try {
          unawaited(
            blockerDb.transaction(() async {
              await blockerDb.customStatement(
                r"SELECT pg_advisory_xact_lock(hashtextextended('user_availability:' || $1, 4242))",
                [recipientId],
              );
              blockerReady.complete();
              await releaseBlocker.future;
            }),
          );
          await blockerReady.future;

          unawaited(
            pauseRepo
                .pause(userId: recipientId, resumeOn: futureResumeOn)
                .then((_) => pauseDone.complete())
                .catchError((Object e, StackTrace _) {
                  pauseError = e;
                  pauseDone.complete();
                }),
          );

          await _waitUntil(
            () async =>
                await _ungrantedAvailabilityLockCount(writer, recipientId) >= 1,
            timeout: const Duration(seconds: 5),
          );

          unawaited(
            raceForwardRepo
                .createBatch(
                  beaconId: beaconId,
                  senderId: senderId,
                  recipientIds: [recipientId],
                  batchId: 'batch-fwda-pause-first',
                  noteForRecipient: (_) => 'should not insert',
                )
                .then((result) {
                  forwardResult = result;
                  forwardDone.complete();
                })
                .catchError((Object e, StackTrace _) {
                  forwardError = e;
                  forwardDone.complete();
                }),
          );

          await _waitUntil(
            () async =>
                await _ungrantedAvailabilityLockCount(writer, recipientId) == 2,
            timeout: const Duration(seconds: 5),
          );
          expect(
            await _ungrantedAvailabilityLockCount(writer, recipientId),
            2,
          );

          releaseBlocker.complete();
          await pauseDone.future.timeout(const Duration(seconds: 5));
          await forwardDone.future.timeout(const Duration(seconds: 5));

          expect(pauseError, isNull);
          expect(forwardError, isNull);
          expect(
            forwardResult,
            const ForwardBatchCreateResult(
              createdEdges: [],
              availabilitySkippedRecipientIds: [recipientId],
            ),
          );
          expect(
            await activeEdgeCount(sender: senderId, recipient: recipientId),
            0,
          );

          final pauseRows = await writer.execute(
            Sql.named('''
SELECT resume_on
FROM public.user_availability
WHERE user_id = @userId
'''),
            parameters: {'userId': recipientId},
          );
          expect(pauseRows, hasLength(1));
        } finally {
          if (!releaseBlocker.isCompleted) {
            releaseBlocker.complete();
          }
          await blockerDb.close();
          await pauseDb.close();
          await forwardDb.close();
        }
      },
      skip: skipReason,
    );

    test(
      'forward linearizes before pause: edge exists and pause commits after it',
      () async {
        final blockerDb = TenturaDb(target.databaseEnv);
        final pauseDb = TenturaDb(target.databaseEnv);
        final forwardDb = TenturaDb(target.databaseEnv);
        final pauseRepo = UserAvailabilityRepository(pauseDb);
        final raceForwardRepo = ForwardEdgeRepository(forwardDb);

        final blockerReady = Completer<void>();
        final releaseBlocker = Completer<void>();
        final pauseDone = Completer<void>();
        final forwardDone = Completer<void>();
        Object? pauseError;
        Object? forwardError;
        ForwardBatchCreateResult? forwardResult;

        try {
          unawaited(
            blockerDb.transaction(() async {
              await blockerDb.customStatement(
                r"SELECT pg_advisory_xact_lock(hashtextextended('user_availability:' || $1, 4242))",
                [recipientId],
              );
              blockerReady.complete();
              await releaseBlocker.future;
            }),
          );
          await blockerReady.future;

          unawaited(
            raceForwardRepo
                .createBatch(
                  beaconId: beaconId,
                  senderId: senderId,
                  recipientIds: [recipientId],
                  batchId: 'batch-fwda-forward-first',
                  noteForRecipient: (_) => 'forward wins race',
                )
                .then((result) {
                  forwardResult = result;
                  forwardDone.complete();
                })
                .catchError((Object e, StackTrace _) {
                  forwardError = e;
                  forwardDone.complete();
                }),
          );

          await _waitUntil(
            () async =>
                await _ungrantedAvailabilityLockCount(writer, recipientId) >= 1,
            timeout: const Duration(seconds: 5),
          );

          unawaited(
            pauseRepo
                .pause(userId: recipientId, resumeOn: futureResumeOn)
                .then((_) => pauseDone.complete())
                .catchError((Object e, StackTrace _) {
                  pauseError = e;
                  pauseDone.complete();
                }),
          );

          await _waitUntil(
            () async =>
                await _ungrantedAvailabilityLockCount(writer, recipientId) == 2,
            timeout: const Duration(seconds: 5),
          );
          expect(
            await _ungrantedAvailabilityLockCount(writer, recipientId),
            2,
          );

          releaseBlocker.complete();
          await forwardDone.future.timeout(const Duration(seconds: 5));

          expect(forwardError, isNull);
          expect(forwardResult!.createdEdges, hasLength(1));
          expect(forwardResult!.createdEdges.single.recipientId, recipientId);
          expect(
            await activeEdgeCount(sender: senderId, recipient: recipientId),
            1,
          );

          await pauseDone.future.timeout(const Duration(seconds: 5));
          expect(pauseError, isNull);

          final pauseRows = await writer.execute(
            Sql.named('''
SELECT resume_on
FROM public.user_availability
WHERE user_id = @userId
'''),
            parameters: {'userId': recipientId},
          );
          expect(pauseRows, hasLength(1));
          expect(
            await activeEdgeCount(sender: senderId, recipient: recipientId),
            1,
          );
        } finally {
          if (!releaseBlocker.isCompleted) {
            releaseBlocker.complete();
          }
          await blockerDb.close();
          await pauseDb.close();
          await forwardDb.close();
        }
      },
      skip: skipReason,
    );

    test(
      'mixed batch returns delivered and availability-skipped IDs in requested order',
      () async {
        const openRecipient = 'Ufwdarecip02';
        const pausedRecipient = 'Ufwdarecip03';
        const limitedRecipient = 'Ufwdarecip04';
        const secondPausedRecipient = 'Ufwdarecip05';

        await availabilityRepo.pause(
          userId: pausedRecipient,
          resumeOn: futureResumeOn,
        );
        await availabilityRepo.pause(
          userId: secondPausedRecipient,
          resumeOn: futureResumeOn,
        );
        await availabilityRepo.setLimited(
          userId: limitedRecipient,
          isLimited: true,
        );

        final result = await forwardRepo.createBatch(
          beaconId: beaconId,
          senderId: senderId,
          recipientIds: [
            openRecipient,
            pausedRecipient,
            openRecipient,
            limitedRecipient,
            secondPausedRecipient,
          ],
          batchId: 'batch-fwda-mixed',
          noteForRecipient: (id) => 'note-$id',
        );

        expect(
          result.createdEdges.map((edge) => edge.recipientId).toList(),
          [openRecipient, limitedRecipient],
        );
        expect(
          result.availabilitySkippedRecipientIds,
          [pausedRecipient, secondPausedRecipient],
        );
        expect(
          await activeEdgeCount(sender: senderId, recipient: openRecipient),
          1,
        );
        expect(
          await activeEdgeCount(sender: senderId, recipient: limitedRecipient),
          1,
        );
        expect(
          await activeEdgeCount(sender: senderId, recipient: pausedRecipient),
          0,
        );
        expect(
          await activeEdgeCount(
            sender: senderId,
            recipient: secondPausedRecipient,
          ),
          0,
        );
      },
      skip: skipReason,
    );

    test(
      'in-batch dedupe is silent and does not become an availability skip',
      () async {
        const openRecipient = 'Ufwdarecip02';

        final result = await forwardRepo.createBatch(
          beaconId: beaconId,
          senderId: senderId,
          recipientIds: [openRecipient, openRecipient],
          batchId: 'batch-fwda-dedup',
          noteForRecipient: (_) => 'dedup note',
        );

        expect(result.createdEdges, hasLength(1));
        expect(result.createdEdges.single.recipientId, openRecipient);
        expect(result.availabilitySkippedRecipientIds, isEmpty);
        expect(
          await activeEdgeCount(sender: senderId, recipient: openRecipient),
          1,
        );

        final repeat = await forwardRepo.createBatch(
          beaconId: beaconId,
          senderId: senderId,
          recipientIds: [openRecipient],
          batchId: 'batch-fwda-dedup-repeat',
          noteForRecipient: (_) => 'would duplicate',
        );
        expect(
          repeat,
          const ForwardBatchCreateResult(
            createdEdges: [],
            availabilitySkippedRecipientIds: [],
          ),
        );
      },
      skip: skipReason,
    );

    test(
      'is_limited recipient without future pause remains deliverable',
      () async {
        await availabilityRepo.setLimited(
          userId: recipientId,
          isLimited: true,
        );

        final result = await forwardRepo.createBatch(
          beaconId: beaconId,
          senderId: senderId,
          recipientIds: [recipientId],
          batchId: 'batch-fwda-limited',
          noteForRecipient: (_) => 'limited but open',
        );

        expect(result.createdEdges, hasLength(1));
        expect(result.createdEdges.single.recipientId, recipientId);
        expect(result.availabilitySkippedRecipientIds, isEmpty);
        expect(
          await activeEdgeCount(sender: senderId, recipient: recipientId),
          1,
        );
      },
      skip: skipReason,
    );
  });
}

Future<void> _seedFixture(Connection writer) async {
  final keyAuthor = pgTestPublicKey('fwdaavail', 1);
  final keySender = pgTestPublicKey('fwdaavail', 2);
  final keyRecip01 = pgTestPublicKey('fwdaavail', 3);
  final keyRecip02 = pgTestPublicKey('fwdaavail', 4);
  final keyRecip03 = pgTestPublicKey('fwdaavail', 5);
  final keyRecip04 = pgTestPublicKey('fwdaavail', 6);
  final keyRecip05 = pgTestPublicKey('fwdaavail', 7);

  await writer.execute(
    Sql.named(r'''
INSERT INTO public."user" (id, display_name, public_key, created_at, updated_at)
VALUES
  ('Ufwdaauth01', 'Author', @keyAuthor, '2026-01-01T00:00:00Z', '2026-01-01T00:00:00Z'),
  ('Ufwdasend01', 'Sender', @keySender, '2026-01-01T00:00:00Z', '2026-01-01T00:00:00Z'),
  ('Ufwdarecip01', 'Recipient 1', @keyRecip01, '2026-01-01T00:00:00Z', '2026-01-01T00:00:00Z'),
  ('Ufwdarecip02', 'Recipient 2', @keyRecip02, '2026-01-01T00:00:00Z', '2026-01-01T00:00:00Z'),
  ('Ufwdarecip03', 'Recipient 3', @keyRecip03, '2026-01-01T00:00:00Z', '2026-01-01T00:00:00Z'),
  ('Ufwdarecip04', 'Recipient 4', @keyRecip04, '2026-01-01T00:00:00Z', '2026-01-01T00:00:00Z'),
  ('Ufwdarecip05', 'Recipient 5', @keyRecip05, '2026-01-01T00:00:00Z', '2026-01-01T00:00:00Z')
ON CONFLICT (id) DO UPDATE SET
  display_name = EXCLUDED.display_name,
  public_key = EXCLUDED.public_key
'''),
    parameters: {
      'keyAuthor': keyAuthor,
      'keySender': keySender,
      'keyRecip01': keyRecip01,
      'keyRecip02': keyRecip02,
      'keyRecip03': keyRecip03,
      'keyRecip04': keyRecip04,
      'keyRecip05': keyRecip05,
    },
  );
  await writer.execute(r'''
INSERT INTO public.beacon (id, user_id, title, description, created_at, updated_at)
VALUES (
  'Bfwdaavail01',
  'Ufwdaauth01',
  'Forward availability linearization',
  '',
  '2026-01-01T00:00:00Z',
  '2026-01-01T00:00:00Z'
)
ON CONFLICT (id) DO NOTHING
''');
}

Future<int> _ungrantedAvailabilityLockCount(
  Connection writer,
  String userId,
) async {
  final rows = await writer.execute(
    Sql.named(r'''
WITH lock_key AS (
  SELECT hashtextextended('user_availability:' || @userId, 4242) AS key
)
SELECT count(*)::int
FROM pg_locks l
CROSS JOIN lock_key k
WHERE l.locktype = 'advisory'
  AND l.granted = false
  AND ((l.classid::bigint << 32) | (l.objid::bigint & 4294967295)) = k.key
'''),
    parameters: {'userId': userId},
  );
  return rows.single.single! as int;
}

Future<void> _waitUntil(
  Future<bool> Function() predicate, {
  required Duration timeout,
  Duration interval = const Duration(milliseconds: 25),
}) async {
  final deadline = DateTime.now().add(timeout);
  while (DateTime.now().isBefore(deadline)) {
    if (await predicate()) {
      return;
    }
    await Future<void>.delayed(interval);
  }
  throw TimeoutException('predicate not satisfied', timeout);
}

Future<bool> _canConnect(Env env) async {
  try {
    final connection = await Connection.open(
      env.pgEndpoint,
      settings: env.pgEndpointSettings,
    );
    await connection.close();
    return true;
  } on Object {
    return false;
  }
}

class _DisposablePgTarget {
  const _DisposablePgTarget({
    required this.adminEnv,
    required this.databaseEnv,
    required this.databaseName,
  });

  factory _DisposablePgTarget.fromEnvironment() {
    final host = Platform.environment['POSTGRES_HOST'] ?? '127.0.0.1';
    final port =
        int.tryParse(Platform.environment['POSTGRES_PORT'] ?? '') ?? 5432;
    final username = Platform.environment['POSTGRES_USERNAME'] ?? 'postgres';
    final password = Platform.environment['POSTGRES_PASSWORD'] ?? 'password';
    final adminDatabase =
        Platform.environment['POSTGRES_ADMIN_DBNAME'] ?? 'postgres';
    final databaseName =
        Platform.environment['TENTURA_FORWARD_EDGE_AVAILABILITY_TEST_DB'] ??
        'tentura_test_fwdaavail_${pid}_${DateTime.timestamp().microsecondsSinceEpoch}';
    if (!RegExp(r'^tentura_test_[a-z0-9_]+$').hasMatch(databaseName) ||
        databaseName.length > 63) {
      throw ArgumentError.value(
        databaseName,
        'TENTURA_FORWARD_EDGE_AVAILABILITY_TEST_DB',
        'must match tentura_test_[a-z0-9_]+ and be at most 63 characters',
      );
    }

    Env envFor(String database) => Env(
      environment: Environment.test,
      pgHost: host,
      pgPort: port,
      pgDatabase: database,
      pgUsername: username,
      pgPassword: password,
      printEnv: false,
      isDebugModeOn: false,
    );

    return _DisposablePgTarget(
      adminEnv: envFor(adminDatabase),
      databaseEnv: envFor(databaseName),
      databaseName: databaseName,
    );
  }

  final Env adminEnv;
  final Env databaseEnv;
  final String databaseName;

  Future<void> recreate() async {
    final connection = await Connection.open(
      adminEnv.pgEndpoint,
      settings: adminEnv.pgEndpointSettings,
    );
    try {
      await connection.execute(
        'DROP DATABASE IF EXISTS "$databaseName" WITH (FORCE)',
      );
      await connection.execute('CREATE DATABASE "$databaseName"');
    } finally {
      await connection.close();
    }
  }

  Future<void> drop() async {
    final connection = await Connection.open(
      adminEnv.pgEndpoint,
      settings: adminEnv.pgEndpointSettings,
    );
    try {
      await connection.execute(
        'DROP DATABASE IF EXISTS "$databaseName" WITH (FORCE)',
      );
    } finally {
      await connection.close();
    }
  }
}
