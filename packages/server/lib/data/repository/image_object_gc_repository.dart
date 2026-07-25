import 'package:drift/drift.dart';
import 'package:drift_postgres/drift_postgres.dart' show UuidValue;
import 'package:injectable/injectable.dart';
import 'package:postgres/postgres.dart' show Type, TypedValue;

import 'package:tentura_server/consts.dart' show kImageExt, kImagesPath;
import 'package:tentura_server/domain/port/image_object_gc_port.dart';
import 'package:tentura_server/domain/port/remote_storage_port.dart';

import '../database/tentura_db.dart';

@Injectable(
  as: ImageObjectGcPort,
  env: [
    Environment.dev,
    Environment.prod,
  ],
  order: 1,
)
class ImageObjectGcRepository implements ImageObjectGcPort {
  const ImageObjectGcRepository(this._database, this._remoteStorageService);

  final TenturaDb _database;

  final RemoteStoragePort _remoteStorageService;

  @override
  Future<void> enqueue({
    required String imageId,
    required String authorId,
  }) => _database.customStatement(
    r'''
INSERT INTO public.image_object_gc (image_id, author_id)
VALUES ($1::uuid, $2)
ON CONFLICT (image_id) DO NOTHING
''',
    [imageId, authorId],
  );

  @override
  Future<void> removeObject({
    required String imageId,
    required String authorId,
  }) => _remoteStorageService.removeObject(
    '$kImagesPath/$authorId/$imageId.$kImageExt',
  );

  @override
  Future<List<ImageObjectGcLease>> claim({
    required String leaseOwner,
    required DateTime now,
    int limit = 32,
  }) async {
    final rows = await _database
        .customSelect(
          r'''
WITH due AS (
  SELECT image_id
  FROM public.image_object_gc
  WHERE attempts < 10
    AND next_attempt_at <= $2
    AND (lease_until IS NULL OR lease_until <= $2)
  ORDER BY next_attempt_at, enqueued_at, image_id
  FOR UPDATE SKIP LOCKED
  LIMIT $3
)
UPDATE public.image_object_gc AS gc
SET lease_owner = $1,
    lease_until = $2 + interval '2 minutes',
    attempts = gc.attempts + 1
FROM due
WHERE gc.image_id = due.image_id
RETURNING gc.*
''',
          variables: [
            Variable<String>(leaseOwner),
            Variable(TypedValue(Type.timestampTz, now.toUtc())),
            Variable(TypedValue(Type.integer, limit)),
          ],
        )
        .get();
    return [
      for (final row in rows)
        ImageObjectGcLease(
          imageId: _readUuid(row, 'image_id'),
          authorId: row.read<String>('author_id'),
          attempts: row.read<int>('attempts'),
        ),
    ];
  }

  static String _readUuid(QueryRow row, String column) {
    final value = row.data[column];
    return value is UuidValue ? value.uuid : value.toString();
  }

  @override
  Future<bool> complete({
    required String imageId,
    required String leaseOwner,
  }) async {
    final affected = await _database.customUpdate(
      r'''
DELETE FROM public.image_object_gc
WHERE image_id = $1::uuid AND lease_owner = $2
''',
      variables: [Variable<String>(imageId), Variable<String>(leaseOwner)],
      updateKind: UpdateKind.delete,
    );
    return affected > 0;
  }

  @override
  Future<bool> fail({
    required String imageId,
    required String leaseOwner,
    required DateTime retryAt,
    required String error,
  }) async {
    final affected = await _database.customUpdate(
      r'''
UPDATE public.image_object_gc
SET last_error = left($4, 1000),
    next_attempt_at = $3,
    lease_owner = NULL,
    lease_until = NULL
WHERE image_id = $1::uuid AND lease_owner = $2
''',
      variables: [
        Variable<String>(imageId),
        Variable<String>(leaseOwner),
        Variable(TypedValue(Type.timestampTz, retryAt.toUtc())),
        Variable<String>(error),
      ],
      updateKind: UpdateKind.update,
    );
    return affected > 0;
  }
}
