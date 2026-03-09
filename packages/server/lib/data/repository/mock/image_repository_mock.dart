import 'dart:typed_data';

import 'package:injectable/injectable.dart';

import '../image_repository.dart';

@Injectable(
  as: ImageRepository,
  env: [Environment.test],
  order: 1,
)
class ImageRepositoryMock implements ImageRepository {
  @override
  Future<void> delete({
    required String authorId,
    required String imageId,
  }) {
    throw UnimplementedError();
  }

  @override
  Future<void> deleteAllOf({required String userId}) {
    throw UnimplementedError();
  }

  @override
  Future<Uint8List> get({required String id}) {
    throw UnimplementedError();
  }

  @override
  Future<String> put({
    required String authorId,
    required Stream<Uint8List> bytes,
  }) {
    throw UnimplementedError();
  }

  @override
  Future<void> update({
    required String id,
    required String blurHash,
    required int height,
    required int width,
  }) {
    throw UnimplementedError();
  }
}
