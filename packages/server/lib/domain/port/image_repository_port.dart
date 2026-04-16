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

  Future<void> deleteAllOf({required String userId});
}
