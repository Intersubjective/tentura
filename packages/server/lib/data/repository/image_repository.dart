import 'package:drift_postgres/drift_postgres.dart';
import 'package:injectable/injectable.dart';

import 'package:tentura_server/env.dart';

import '../database/tentura_db.dart';
import '../storage/remote_storage.dart';

@Injectable(
  env: [
    Environment.dev,
    Environment.prod,
  ],
  order: 1,
)
class ImageRepository {
  const ImageRepository(
    this._database,
    this._remoteStorageService,
  );

  final TenturaDb _database;

  final RemoteStorage _remoteStorageService;

  Future<Uint8List> get({required String id}) async {
    final image = await _database.managers.images
        .filter((e) => e.id(UuidValue.fromString(id)))
        .getSingle();
    return _remoteStorageService.getObject(
      _getImagePath(authorId: image.authorId, imageId: id),
    );
  }

  Future<String> put({
    required String authorId,
    required Stream<Uint8List> bytes,
  }) async {
    final imageModel = await _database.managers.images.createReturning(
      (o) => o(authorId: authorId),
    );
    await _remoteStorageService.putObject(
      _getImagePath(
        authorId: authorId,
        imageId: imageModel.id.uuid,
      ),
      bytes,
    );
    return imageModel.id.uuid;
  }

  Future<void> update({
    required String id,
    required String blurHash,
    required int height,
    required int width,
  }) => _database.managers.images
      .filter((e) => e.id(UuidValue.fromString(id)))
      .update(
        (o) => o(
          hash: Value(blurHash),
          height: Value(height),
          width: Value(width),
        ),
      );

  Future<void> delete({
    required String authorId,
    required String imageId,
  }) async {
    await _database.managers.images
        .filter((e) => e.id(UuidValue.fromString(imageId)))
        .delete();
    await _remoteStorageService.removeObject(
      _getImagePath(authorId: authorId, imageId: imageId),
    );
  }

  Future<void> deleteAllOf({required String userId}) =>
      _remoteStorageService.removeObject(
        '$kImagesPath/$userId',
      );

  static String _getImagePath({
    required String authorId,
    required String imageId,
  }) => '$kImagesPath/$authorId/$imageId.$kImageExt';
}
