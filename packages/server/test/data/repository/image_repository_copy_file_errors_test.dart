import 'dart:async';
import 'dart:io';

import 'package:injectable/injectable.dart' show Environment;
import 'package:logging/logging.dart';
import 'package:minio/minio.dart';
import 'package:test/test.dart';

import 'package:tentura_server/data/database/tentura_db.dart'
    hide isNotNull, isNull;
import 'package:tentura_server/data/repository/image_repository.dart';
import 'package:tentura_server/domain/exception.dart';
import 'package:tentura_server/domain/port/image_object_gc_port.dart';
import 'package:tentura_server/domain/port/remote_storage_port.dart';
import 'package:tentura_server/domain/port/upload_quota_repository_port.dart';
import 'package:tentura_server/env.dart';

import '../../support/s3_errors.dart';

class _FakeStorage implements RemoteStoragePort {
  Exception? getError;
  final putPaths = <String>[];

  @override
  Future<Uint8List> getObject(String path) async {
    if (getError != null) throw getError!;
    return Uint8List.fromList([1, 2, 3]);
  }

  @override
  Future<String> putObject(
    String path,
    Stream<Uint8List> bytes, {
    Map<String, String>? metadata,
  }) async {
    putPaths.add(path);
    return path;
  }

  @override
  Future<void> removeObject(String path) async {}
}

class _NoDb implements TenturaDb {
  @override
  dynamic noSuchMethod(Invocation invocation) =>
      throw UnsupportedError('database not used by copyFile');
}

class _NoQuota implements UploadQuotaRepositoryPort {
  @override
  dynamic noSuchMethod(Invocation invocation) =>
      throw UnsupportedError('quota not used by copyFile');
}

class _NoGc implements ImageObjectGcPort {
  @override
  dynamic noSuchMethod(Invocation invocation) =>
      throw UnsupportedError('gc not used by copyFile');
}

void main() {
  late _FakeStorage storage;
  late ImageRepository repo;

  setUp(() {
    storage = _FakeStorage();
    repo = ImageRepository(
      _NoDb(),
      storage,
      _NoQuota(),
      _NoGc(),
      Env(environment: Environment.test, printEnv: false),
      Logger('ImageRepositoryCopyFileErrorsTest'),
    );
  });

  Future<String> copy() => repo.copyFile(path: 'a/b', mime: 'image/png');

  test('copyFile of a missing object (NoSuchKey) reports the attachment as '
      'no longer available under its own code, not 1352', () async {
    storage.getError = noSuchKeyError();
    final error = await copy().then<Object?>((_) => null, onError: (Object e) => e);
    expect(error, isA<ExceptionBase>());
    final base = error! as ExceptionBase;
    expect(base, isNot(isA<FactCopySourceUnavailableException>()));
    expect(base.toMap['extensions'], containsPair('code', '1354'));
    expect(
      base.description,
      isNot(const FactCopySourceUnavailableException().description),
      reason: 'says an attachment, not that the whole fact is gone',
    );
    expect(base.description.toLowerCase(), contains('attachment'));
    expect(storage.putPaths, isEmpty);
  });

  final rethrown = <String, Exception>{
    'timeout': TimeoutException('slow'),
    'server error InternalError': s3CodeError('InternalError'),
    '503 response': MinioError('503 Service Unavailable'),
    'AccessDenied': s3CodeError('AccessDenied'),
    'InvalidAccessKeyId': s3CodeError('InvalidAccessKeyId'),
    'socket failure': const SocketException('unreachable'),
  };
  for (final entry in rethrown.entries) {
    test('copyFile rethrows ${entry.key} unchanged', () async {
      storage.getError = entry.value;
      await expectLater(copy(), throwsA(same(entry.value)));
      expect(storage.putPaths, isEmpty);
    });
  }
}
