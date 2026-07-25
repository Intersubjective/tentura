@Tags(['pg'])
library;

import 'dart:async';
import 'dart:io';
import 'dart:typed_data';

import 'package:injectable/injectable.dart' show Environment;
import 'package:logging/logging.dart';
import 'package:postgres/postgres.dart';
import 'package:test/test.dart';

import 'package:tentura_server/data/database/migration/_migrations.dart';
import 'package:tentura_server/data/database/tentura_db.dart'
    hide isNotNull, isNull;
import 'package:tentura_server/data/repository/image_object_gc_repository.dart';
import 'package:tentura_server/data/repository/image_repository.dart';
import 'package:tentura_server/domain/exception.dart';
import 'package:tentura_server/domain/port/remote_storage_port.dart';
import 'package:tentura_server/domain/port/upload_quota_repository_port.dart';
import 'package:tentura_server/env.dart';

class _FakeRemoteStorage implements RemoteStoragePort {
  final putPaths = <String>[];
  final removedPaths = <String>[];
  Object? failNextPut;

  @override
  Future<Uint8List> getObject(String path) async => Uint8List(0);

  @override
  Future<String> putObject(
    String path,
    Stream<Uint8List> bytes, {
    Map<String, String>? metadata,
  }) async {
    if (failNextPut != null) {
      final error = failNextPut!;
      failNextPut = null;
      throw error;
    }
    putPaths.add(path);
    return path;
  }

  @override
  Future<void> removeObject(String path) async {
    removedPaths.add(path);
  }
}

class _AllowAllQuota implements UploadQuotaRepositoryPort {
  @override
  Future<bool> tryReserveDailyBytes({
    required String userId,
    required int bytes,
    required int dailyCapBytes,
  }) async => true;

  @override
  Future<int> usedBytesToday(String userId) async => 0;
}

Future<void> main() async {
  final target = _DisposablePgTarget.fromEnvironment();
  final reachable = await _canConnect(target.adminEnv);
  final skipReason = reachable
      ? false
      : 'Postgres admin database not reachable for disposable test target';

  group('ImageRepository compensation', () {
    late Connection writer;
    late TenturaDb database;
    late _FakeRemoteStorage storage;
    late ImageRepository repo;
    var seq = 0;

    String nextAuthorId() {
      seq++;
      return 'Uauthor$seq';
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
      repo = ImageRepository(
        database,
        storage,
        _AllowAllQuota(),
        ImageObjectGcRepository(database, storage),
        Env(environment: Environment.test, printEnv: false),
        Logger('ImageRepositoryCompensationTest'),
      );
    });

    setUp(() async {
      storage.putPaths.clear();
      storage.removedPaths.clear();
      storage.failNextPut = null;
    });

    tearDownAll(() async {
      await database.close();
      await writer.close();
      await target.drop();
    });

    Future<void> insertUser(String id) => writer.execute(
      Sql.named(
        'INSERT INTO public."user" (id, display_name, public_key) '
        'VALUES (@id, @id, @key) ON CONFLICT DO NOTHING',
      ),
      parameters: {'id': id, 'key': '$id-key'},
    );

    test('a successful put creates exactly one row and one object', () async {
      final authorId = nextAuthorId();
      await insertUser(authorId);

      final imageId = await repo.put(
        authorId: authorId,
        bytes: Stream.value(Uint8List.fromList([1, 2, 3])),
      );

      expect(storage.putPaths, ['images/$authorId/$imageId.jpg']);
      final rows = await writer.execute(
        Sql.named(
          'SELECT count(*)::int FROM public.image WHERE id = @id::uuid',
        ),
        parameters: {'id': imageId},
      );
      expect(rows.single.single, 1);
    });

    test(
      'a remote put failure compensates: row deleted, object GC-enqueued, original error rethrown',
      () async {
        final authorId = nextAuthorId();
        await insertUser(authorId);
        storage.failNextPut = StateError('remote write failed');

        await expectLater(
          repo.put(
            authorId: authorId,
            bytes: Stream.value(Uint8List.fromList([1, 2, 3])),
          ),
          throwsA(isA<StateError>()),
        );

        final rows = await writer.execute(
          Sql.named(
            'SELECT count(*)::int FROM public.image WHERE author_id = @id',
          ),
          parameters: {'id': authorId},
        );
        expect(rows.single.single, 0);

        final gcRows = await writer.execute(
          Sql.named(
            'SELECT count(*)::int FROM public.image_object_gc '
            'WHERE author_id = @id',
          ),
          parameters: {'id': authorId},
        );
        expect(gcRows.single.single, 1);

        // Compensation never talks to remote storage directly (§3.4): the
        // worker removes the object only after this commit.
        expect(storage.removedPaths, isEmpty);
      },
    );

    test(
      'a partial-write failure (object may exist) still compensates via GC, never a direct delete',
      () async {
        final authorId = nextAuthorId();
        await insertUser(authorId);
        // Simulate an ambiguous partial write: putObject throws after some
        // bytes may already be on the wire.
        storage.failNextPut = Exception('connection reset mid-upload');

        await expectLater(
          repo.put(
            authorId: authorId,
            bytes: Stream.value(Uint8List.fromList([4, 5, 6])),
          ),
          throwsA(isA<Exception>()),
        );

        expect(storage.removedPaths, isEmpty);
        final gcRows = await writer.execute(
          Sql.named(
            'SELECT count(*)::int FROM public.image_object_gc '
            'WHERE author_id = @id',
          ),
          parameters: {'id': authorId},
        );
        expect(gcRows.single.single, 1);
      },
    );

    test(
      'compensateOrphanedUpload is atomic and idempotent on retry',
      () async {
        final authorId = nextAuthorId();
        await insertUser(authorId);
        final imageId = await repo.put(
          authorId: authorId,
          bytes: Stream.value(Uint8List.fromList([7, 8, 9])),
        );

        await repo.compensateOrphanedUpload(
          imageId: imageId,
          authorId: authorId,
        );
        final firstPass = await writer.execute(
          Sql.named(
            'SELECT count(*)::int FROM public.image WHERE id = @id::uuid',
          ),
          parameters: {'id': imageId},
        );
        expect(firstPass.single.single, 0);

        // Retrying after the row is already gone must not throw (swallowed
        // and logged internally); the GC row stays enqueued exactly once.
        await repo.compensateOrphanedUpload(
          imageId: imageId,
          authorId: authorId,
        );
        final gcRows = await writer.execute(
          Sql.named(
            'SELECT count(*)::int FROM public.image_object_gc '
            'WHERE image_id = @id::uuid',
          ),
          parameters: {'id': imageId},
        );
        expect(gcRows.single.single, 1);
      },
    );

    test(
      'deleteAllOf enqueues every owned image for GC and deletes every row, never touching remote storage',
      () async {
        final authorId = nextAuthorId();
        await insertUser(authorId);
        final id1 = await repo.put(
          authorId: authorId,
          bytes: Stream.value(Uint8List.fromList([1])),
        );
        final id2 = await repo.put(
          authorId: authorId,
          bytes: Stream.value(Uint8List.fromList([2])),
        );
        storage.putPaths.clear();

        await repo.deleteAllOf(userId: authorId);

        expect(storage.removedPaths, isEmpty);
        final remainingRows = await writer.execute(
          Sql.named(
            'SELECT count(*)::int FROM public.image WHERE author_id = @id',
          ),
          parameters: {'id': authorId},
        );
        expect(remainingRows.single.single, 0);

        final gcRows = await writer.execute(
          Sql.named(
            'SELECT image_id::text FROM public.image_object_gc '
            'WHERE author_id = @id',
          ),
          parameters: {'id': authorId},
        );
        expect(
          gcRows.map((r) => r.single as String).toSet(),
          {id1, id2},
        );
      },
    );
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
        Platform.environment['TENTURA_IMAGE_REPOSITORY_COMPENSATION_TEST_DB'] ??
        'tentura_test_imgcomp_${pid}_${DateTime.timestamp().microsecondsSinceEpoch}';
    if (!RegExp(r'^tentura_test_[a-z0-9_]+$').hasMatch(databaseName) ||
        databaseName.length > 63) {
      throw ArgumentError.value(
        databaseName,
        'TENTURA_IMAGE_REPOSITORY_COMPENSATION_TEST_DB',
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
