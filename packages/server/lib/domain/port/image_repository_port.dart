import 'dart:typed_data';

abstract class ImageRepositoryPort {
  Future<Uint8List> get({required String id});

  Future<String> put({
    required String authorId,
    required Stream<Uint8List> bytes,
  });

  Future<void> update({
    required String id,
    required String blurHash,
    required int height,
    required int width,
  });

  Future<void> delete({
    required String authorId,
    required String imageId,
  });

  /// Deletes the image row iff owned by [authorId]; returns the affected-row
  /// count (0 or 1) so callers can detect an ownership/attachment mismatch.
  /// Does not touch remote object storage; pair with [ImageObjectGcPort] to
  /// enqueue removal before/around this call.
  Future<int> deleteOwnedRow({
    required String imageId,
    required String authorId,
  });

  Future<void> deleteAllOf({required String userId});

  /// Ids of every image row owned by [authorId] (no ordering guarantee).
  Future<List<String>> listOwnedIds({required String authorId});

  /// Enqueues [imageId] for object GC and deletes its owned row, atomically,
  /// to clean up an upload that will never be attached (failed stage/attach
  /// transaction, create/fork cleanup). Never touches remote storage itself.
  Future<void> compensateOrphanedUpload({
    required String imageId,
    required String authorId,
  });
}
