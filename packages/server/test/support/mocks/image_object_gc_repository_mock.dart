import 'package:injectable/injectable.dart';

import 'package:tentura_server/domain/port/image_object_gc_port.dart';

@Injectable(
  as: ImageObjectGcPort,
  env: [Environment.test],
  order: 1,
)
class ImageObjectGcRepositoryMock implements ImageObjectGcPort {
  final rows = <String, ({String authorId, int attempts})>{};

  final removedObjects = <String>[];

  @override
  Future<void> enqueue({
    required String imageId,
    required String authorId,
  }) async {
    rows.putIfAbsent(imageId, () => (authorId: authorId, attempts: 0));
  }

  @override
  Future<void> removeObject({
    required String imageId,
    required String authorId,
  }) async {
    removedObjects.add(imageId);
  }

  @override
  Future<List<ImageObjectGcLease>> claim({
    required String leaseOwner,
    required DateTime now,
    int limit = 32,
  }) async => [
    for (final entry in rows.entries.take(limit))
      ImageObjectGcLease(
        imageId: entry.key,
        authorId: entry.value.authorId,
        attempts: entry.value.attempts + 1,
      ),
  ];

  @override
  Future<bool> complete({
    required String imageId,
    required String leaseOwner,
  }) async => rows.remove(imageId) != null;

  @override
  Future<bool> fail({
    required String imageId,
    required String leaseOwner,
    required DateTime retryAt,
    required String error,
  }) async {
    final existing = rows[imageId];
    if (existing == null) return false;
    rows[imageId] = (authorId: existing.authorId, attempts: existing.attempts);
    return true;
  }
}
