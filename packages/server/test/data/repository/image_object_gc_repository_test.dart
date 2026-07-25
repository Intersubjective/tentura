@Tags(['pg'])
library;

import 'dart:async';
import 'dart:io';
import 'dart:typed_data';

import 'package:injectable/injectable.dart' show Environment;
import 'package:postgres/postgres.dart';
import 'package:test/test.dart';

import 'package:tentura_server/data/database/migration/_migrations.dart';
import 'package:tentura_server/data/database/tentura_db.dart'
    hide isNotNull, isNull;
import 'package:tentura_server/data/repository/image_object_gc_repository.dart';
import 'package:tentura_server/domain/port/remote_storage_port.dart';
import 'package:tentura_server/env.dart';

class _FakeRemoteStorage implements RemoteStoragePort {
  final removedPaths = <String>[];
  Object? failNext;

  @override
  Future<Uint8List> getObject(String path) async => Uint8List(0);

  @override
  Future<String> putObject(
    String path,
    Stream<Uint8List> bytes, {
    Map<String, String>? metadata,
  }) async => path;

  @override
  Future<void> removeObject(String path) async {
    if (failNext != null) {
      final error = failNext!;
      failNext = null;
      throw error;
    }
    removedPaths.add(path);
  }
}

Future<void> main() async {
  final target = _DisposablePgTarget.fromEnvironment();
  final reachable = await _canConnect(target.adminEnv);
  final skipReason = reachable
      ? false
      : 'Postgres admin database not reachable for disposable test target';

  group('ImageObjectGcRepository', () {
    late Connection writer;
    late TenturaDb database;
    late ImageObjectGcRepository repo;
    late _FakeRemoteStorage storage;
    var seq = 0;

    String nextImageId() {
      seq++;
      return 'bbbbbbbb-bbbb-bbbb-bbbb-${seq.toString().padLeft(12, '0')}';
    }

    setUpAll(() async {
      await target.recreate();
      writer = await Connection.open(
        target.databaseEnv.pgEndpoint,
        settings: target.databaseEnv.pgEndpointSettings,
      );
      await writer.execute('SET check_function_bodies = false');
      await migrateDbSchema(writer);
      database = TenturaDb(target.databaseEnv);
      storage = _FakeRemoteStorage();
      repo = ImageObjectGcRepository(database, storage);
    });

    setUp(() async {
      await writer.execute('TRUNCATE TABLE public.image_object_gc');
      storage.removedPaths.clear();
      storage.failNext = null;
    });

    tearDownAll(() async {
      await database.close();
      await writer.close();
      await target.drop();
    });

    test('enqueue is a no-op retry that never resets attempts or steals a live lease',
        () async {
      final imageId = nextImageId();
      await repo.enqueue(imageId: imageId, authorId: 'Uauthor');

      final claimed = await repo.claim(
        leaseOwner: 'ownerA',
        now: DateTime.now().toUtc(),
      );
      expect(claimed, hasLength(1));
      expect(claimed.single.attempts, 1);

      // Retry enqueue while a lease is live must not touch attempts/lease.
      await repo.enqueue(imageId: imageId, authorId: 'Uauthor');
      final row = await writer.execute(
        Sql.named(
          'SELECT attempts, lease_owner FROM public.image_object_gc '
          'WHERE image_id = @id::uuid',
        ),
        parameters: {'id': imageId},
      );
      expect(row.single[0], 1);
      expect(row.single[1], 'ownerA');
    });

    test('two claimers under SKIP LOCKED never claim the same row', () async {
      final database2 = TenturaDb(target.databaseEnv);
      final repo2 = ImageObjectGcRepository(database2, storage);
      try {
        final ids = List.generate(20, (_) => nextImageId());
        for (final id in ids) {
          await repo.enqueue(imageId: id, authorId: 'Uauthor');
        }

        final now = DateTime.now().toUtc();
        final results = await Future.wait([
          repo.claim(leaseOwner: 'ownerA', now: now, limit: 20),
          repo2.claim(leaseOwner: 'ownerB', now: now, limit: 20),
        ]);

        final claimedIds = [
          ...results[0].map((l) => l.imageId),
          ...results[1].map((l) => l.imageId),
        ];
        expect(claimedIds.toSet(), ids.toSet());
        expect(claimedIds.length, ids.length);
      } finally {
        await database2.close();
      }
    });

    test('complete and fail are owner-checked', () async {
      final imageId = nextImageId();
      await repo.enqueue(imageId: imageId, authorId: 'Uauthor');
      final claimed = await repo.claim(
        leaseOwner: 'ownerA',
        now: DateTime.now().toUtc(),
      );
      expect(claimed.single.imageId, imageId);

      expect(
        await repo.complete(imageId: imageId, leaseOwner: 'ownerB'),
        isFalse,
      );
      expect(
        await repo.fail(
          imageId: imageId,
          leaseOwner: 'ownerB',
          retryAt: DateTime.now().toUtc(),
          error: 'nope',
        ),
        isFalse,
      );

      expect(
        await repo.complete(imageId: imageId, leaseOwner: 'ownerA'),
        isTrue,
      );
      final row = await writer.execute(
        Sql.named(
          'SELECT count(*)::int FROM public.image_object_gc '
          'WHERE image_id = @id::uuid',
        ),
        parameters: {'id': imageId},
      );
      expect(row.single.single, 0);
    });

    test('an expired lease is claimable again by a different owner', () async {
      final imageId = nextImageId();
      await repo.enqueue(imageId: imageId, authorId: 'Uauthor');
      final base = DateTime.now().toUtc();
      final firstClaim = await repo.claim(leaseOwner: 'ownerA', now: base);
      expect(firstClaim.single.attempts, 1);

      // Lease is held for 2 minutes; nothing else can claim it yet.
      final tooEarly = await repo.claim(
        leaseOwner: 'ownerB',
        now: base.add(const Duration(minutes: 1)),
      );
      expect(tooEarly, isEmpty);

      // After the lease window, a different owner can claim (attempts += 1).
      final afterExpiry = await repo.claim(
        leaseOwner: 'ownerB',
        now: base.add(const Duration(minutes: 3)),
      );
      expect(afterExpiry, hasLength(1));
      expect(afterExpiry.single.attempts, 2);
    });

    test('fail schedules exponential backoff and clears the lease', () async {
      final imageId = nextImageId();
      await repo.enqueue(imageId: imageId, authorId: 'Uauthor');
      final base = DateTime.now().toUtc();
      await repo.claim(leaseOwner: 'ownerA', now: base);

      final retryAt = base.add(const Duration(minutes: 5));
      expect(
        await repo.fail(
          imageId: imageId,
          leaseOwner: 'ownerA',
          retryAt: retryAt,
          error: 'remote timeout',
        ),
        isTrue,
      );

      // Not yet due before retryAt, even for the same owner (lease cleared).
      final tooEarly = await repo.claim(
        leaseOwner: 'ownerC',
        now: retryAt.subtract(const Duration(seconds: 1)),
      );
      expect(tooEarly, isEmpty);

      final due = await repo.claim(leaseOwner: 'ownerC', now: retryAt);
      expect(due, hasLength(1));
      expect(due.single.attempts, 2);

      final row = await writer.execute(
        Sql.named(
          'SELECT last_error FROM public.image_object_gc '
          'WHERE image_id = @id::uuid',
        ),
        parameters: {'id': imageId},
      );
      expect(row.single.single, 'remote timeout');
    });

    test(
      'a row at 10 attempts is retained but no longer claimable',
      () async {
        final imageId = nextImageId();
        await repo.enqueue(imageId: imageId, authorId: 'Uauthor');

        var now = DateTime.now().toUtc();
        for (var i = 0; i < 10; i++) {
          final claimed = await repo.claim(leaseOwner: 'owner$i', now: now);
          expect(claimed, hasLength(1));
          await repo.fail(
            imageId: imageId,
            leaseOwner: 'owner$i',
            retryAt: now,
            error: 'attempt $i',
          );
          now = now.add(const Duration(seconds: 1));
        }

        final exhausted = await repo.claim(leaseOwner: 'ownerFinal', now: now);
        expect(exhausted, isEmpty);

        final row = await writer.execute(
          Sql.named(
            'SELECT attempts FROM public.image_object_gc '
            'WHERE image_id = @id::uuid',
          ),
          parameters: {'id': imageId},
        );
        expect(row.single.single, 10);
      },
    );

    test('removing a missing object is idempotent success', () async {
      final imageId = nextImageId();
      await repo.enqueue(imageId: imageId, authorId: 'Uauthor');
      await repo.claim(leaseOwner: 'ownerA', now: DateTime.now().toUtc());

      await repo.removeObject(imageId: imageId, authorId: 'Uauthor');
      expect(storage.removedPaths, [
        'images/Uauthor/$imageId.jpg',
      ]);
      expect(
        await repo.complete(imageId: imageId, leaseOwner: 'ownerA'),
        isTrue,
      );
    });
  }, skip: skipReason);
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
        Platform.environment['TENTURA_IMAGE_OBJECT_GC_TEST_DB'] ??
        'tentura_test_imggc_${pid}_${DateTime.timestamp().microsecondsSinceEpoch}';
    if (!RegExp(r'^tentura_test_[a-z0-9_]+$').hasMatch(databaseName) ||
        databaseName.length > 63) {
      throw ArgumentError.value(
        databaseName,
        'TENTURA_IMAGE_OBJECT_GC_TEST_DB',
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
