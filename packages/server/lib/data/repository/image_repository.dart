
import 'package:drift_postgres/drift_postgres.dart';
import 'package:injectable/injectable.dart';
import 'package:logging/logging.dart';

import 'package:tentura_server/env.dart';
import 'package:tentura_server/domain/exception.dart';
import 'package:tentura_server/domain/port/image_object_gc_port.dart';
import 'package:tentura_server/domain/port/image_repository_port.dart';
import 'package:tentura_server/domain/port/upload_quota_repository_port.dart';
import 'package:tentura_server/utils/read_uint8_stream_with_limit.dart';

import '../database/tentura_db.dart';
import 'package:tentura_server/domain/port/remote_storage_port.dart';

@Injectable(
  as: ImageRepositoryPort,
  env: [
    Environment.dev,
    Environment.prod,
  ],
  order: 1,
)
class ImageRepository implements ImageRepositoryPort {
  ImageRepository(
    this._database,
    this._remoteStorageService,
    this._uploadQuota,
    this._imageObjectGc,
    this._env,
    this._logger,
  );

  final TenturaDb _database;

  final RemoteStoragePort _remoteStorageService;

  final UploadQuotaRepositoryPort _uploadQuota;

  final ImageObjectGcPort _imageObjectGc;

  final Env _env;

  final Logger _logger;

  @override
  Future<Uint8List> get({required String id}) async {
    final image = await _database.managers.images
        .filter((e) => e.id(UuidValue.fromString(id)))
        .getSingle();
    return _remoteStorageService.getObject(
      _getImagePath(authorId: image.authorId, imageId: id),
    );
  }

  @override
  Future<String> put({
    required String authorId,
    required Stream<Uint8List> bytes,
  }) async {
    // Enforce the upload cap before creating the image row, so an oversized
    // upload fails fast and never leaves an orphan row or partial object.
    final buffered = await readUint8StreamCapped(bytes, kMaxImageUploadBytes);
    final withinDailyCap = await _uploadQuota.tryReserveDailyBytes(
      userId: authorId,
      bytes: buffered.length,
      dailyCapBytes: _env.uploadDailyCapBytes,
    );
    if (!withinDailyCap) {
      throw const RateLimitedException(
        description: 'Daily upload limit reached, try again tomorrow',
      );
    }
    final imageModel = await _database.managers.images.createReturning(
      (o) => o(authorId: authorId),
    );
    final imageId = imageModel.id.uuid;
    try {
      await _remoteStorageService.putObject(
        _getImagePath(authorId: authorId, imageId: imageId),
        Stream.value(buffered),
      );
    } catch (_) {
      // The remote write failed or may have partially written; never leave
      // an orphan row pointing at an unknown/partial object.
      await _compensateFailedPut(imageId: imageId, authorId: authorId);
      rethrow;
    }
    return imageId;
  }

  Future<void> _compensateFailedPut({
    required String imageId,
    required String authorId,
  }) async {
    try {
      await _database.transaction(() async {
        await _imageObjectGc.enqueue(imageId: imageId, authorId: authorId);
        await deleteOwnedRow(imageId: imageId, authorId: authorId);
      });
    } catch (compensationError, compensationStackTrace) {
      _logger.severe(
        'ImageRepository.put compensation failed for image $imageId',
        compensationError,
        compensationStackTrace,
      );
    }
  }

  @override
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

  @override
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

  @override
  Future<int> deleteOwnedRow({
    required String imageId,
    required String authorId,
  }) => _database.customUpdate(
    r'DELETE FROM public.image WHERE id = $1::uuid AND author_id = $2',
    variables: [Variable<String>(imageId), Variable<String>(authorId)],
    updateKind: UpdateKind.delete,
  );

  @override
  Future<void> deleteAllOf({required String userId}) =>
      _remoteStorageService.removeObject(
        '$kImagesPath/$userId',
      );

  static String _getImagePath({
    required String authorId,
    required String imageId,
  }) => '$kImagesPath/$authorId/$imageId.$kImageExt';
}
