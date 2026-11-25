import 'package:injectable/injectable.dart';
import 'package:postgres/postgres.dart' show Type, TypedValue;

import 'package:tentura_server/domain/entity/leased_job_retry.dart';
import 'package:tentura_server/domain/port/private_object_gc_port.dart';
import 'package:tentura_server/domain/port/remote_storage_port.dart';

import '../database/tentura_db.dart';

@LazySingleton(as: PrivateObjectGcPort)
final class PrivateObjectGcRepository implements PrivateObjectGcPort {
  const PrivateObjectGcRepository(this._database, this._storage);

  final TenturaDb _database;
  final RemoteStoragePort _storage;

  @override
  Future<List<PrivateObjectGcLease>> claim({
    required String leaseOwner,
    required DateTime now,
    int limit = 32,
  }) async {
    final rows = await _database
        .customSelect(
          r'''
WITH due AS (
  SELECT object_key
  FROM public.private_object_gc
  WHERE attempts < $4
    AND next_attempt_at <= $1
    AND (lease_until IS NULL OR lease_until <= $1)
  ORDER BY next_attempt_at, enqueued_at, object_key
  FOR UPDATE SKIP LOCKED
  LIMIT $3
)
UPDATE public.private_object_gc AS gc
SET lease_owner = $2,
    lease_until = $1 + interval '2 minutes',
    attempts = gc.attempts + 1
FROM due
WHERE gc.object_key = due.object_key
RETURNING gc.object_key, gc.attempts
''',
          variables: [
            Variable(TypedValue(Type.timestampTz, now.toUtc())),
            Variable.withString(leaseOwner),
            Variable(TypedValue(Type.integer, limit)),
            Variable(TypedValue(Type.integer, kLeasedJobMaxAttempts)),
          ],
        )
        .get();
    return [
      for (final row in rows)
        PrivateObjectGcLease(
          objectKey: row.read<String>('object_key'),
          attempts: row.read<int>('attempts'),
        ),
    ];
  }

  @override
  Future<void> collect({
    required String objectKey,
    required String leaseOwner,
  }) async {
    final referenced = await _database.withTransaction(() async {
      // Use the enqueue trigger's lock so a concurrent removal of the last
      // reference cannot lose its enqueue while we acknowledge this lease.
      await _database.customStatement(
        r'SELECT public.lock_private_object_gc_key($1)',
        [objectKey],
      );
      final reference = await _database
          .customSelect(
            r'''
SELECT 1 FROM public.person_private_avatar WHERE object_key = $1 LIMIT 1
''',
            variables: [Variable.withString(objectKey)],
          )
          .getSingleOrNull();
      if (reference == null) return false;
      await complete(objectKey: objectKey, leaseOwner: leaseOwner);
      return true;
    });
    if (referenced) return;

    // Uploads get fresh keys and a merge only copies a live reference.
    // Keep object storage I/O outside the database transaction.
    await _storage.removeObject(objectKey);
    await complete(objectKey: objectKey, leaseOwner: leaseOwner);
  }

  @override
  Future<bool> complete({
    required String objectKey,
    required String leaseOwner,
  }) async {
    final affected = await _database.customUpdate(
      r'''
DELETE FROM public.private_object_gc
WHERE object_key = $1 AND lease_owner = $2
''',
      variables: [
        Variable.withString(objectKey),
        Variable.withString(leaseOwner),
      ],
      updateKind: UpdateKind.delete,
    );
    return affected > 0;
  }

  @override
  Future<bool> fail({
    required String objectKey,
    required String leaseOwner,
    required DateTime retryAt,
    required String error,
  }) async {
    final affected = await _database.customUpdate(
      r'''
UPDATE public.private_object_gc
SET last_error = left($4, 1000),
    next_attempt_at = $3,
    lease_owner = NULL,
    lease_until = NULL
WHERE object_key = $1 AND lease_owner = $2
''',
      variables: [
        Variable.withString(objectKey),
        Variable.withString(leaseOwner),
        Variable(TypedValue(Type.timestampTz, retryAt.toUtc())),
        Variable.withString(error),
      ],
    );
    return affected > 0;
  }
}
