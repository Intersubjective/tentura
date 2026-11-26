import 'dart:typed_data';

import 'package:image/image.dart' as img;
import 'package:injectable/injectable.dart';
import 'package:minio/minio.dart' show MinioS3Error;
import 'package:uuid/uuid.dart';

import 'package:tentura_server/domain/entity/person_subject.dart';
import 'package:tentura_server/domain/exception.dart';
import 'package:tentura_server/domain/port/owner_graph_transaction_port.dart';
import 'package:tentura_server/domain/port/private_avatar_repository_port.dart';
import 'package:tentura_server/domain/port/remote_storage_port.dart';
import 'package:tentura_server/domain/port/upload_quota_repository_port.dart';
import 'package:tentura_server/env.dart';
import 'package:tentura_server/utils/image_metadata.dart';
import 'package:tentura_server/utils/read_uint8_stream_with_limit.dart';

import '../database/tentura_db.dart' show TenturaDb, UpdateKind, Variable;

@LazySingleton(as: PrivateAvatarRepositoryPort)
final class PrivateAvatarRepository implements PrivateAvatarRepositoryPort {
  const PrivateAvatarRepository(
    this._database,
    this._ownerGraph,
    this._storage,
    this._quota,
    this._env,
  );

  final TenturaDb _database;
  final OwnerGraphTransactionPort _ownerGraph;
  final RemoteStoragePort _storage;
  final UploadQuotaRepositoryPort _quota;
  final Env _env;

  @override
  Future<void> put({
    required String ownerId,
    required PersonSubject subject,
    required Stream<Uint8List> bytes,
  }) async {
    if (subject.userId == ownerId) {
      throw const IdWrongException(
        description: 'Cannot add a private avatar for yourself',
      );
    }
    final buffered = await readUint8StreamCapped(bytes, kMaxImageUploadBytes);
    final (:hash, :height, :width) = describeImage(_decodeAvatar(buffered));
    final key = 'private/$ownerId/${const Uuid().v4()}.jpg';

    // Publish the reference before attempting storage, so a later replacement
    // or deletion can retire this key even if the process stops mid-upload.
    await _ownerGraph.run({ownerId}, ownerId, (_) async {
      await _quota.reserveUploadBytes(
        userId: ownerId,
        bytes: buffered.length,
        dailyCapBytes: _env.uploadDailyCapBytes,
      );
      final count = await _database.customUpdate(
        r'''
INSERT INTO public.person_private_avatar
  (owner_id, subject_user_id, subject_phantom_id, object_key, blurhash, width, height)
SELECT $1, $2, $3, $4, $5, $6, $7
WHERE EXISTS (SELECT 1 FROM public."user" WHERE id = $2)
   OR EXISTS (SELECT 1 FROM public.phantom WHERE id = $3 AND owner_id = $1)
ON CONFLICT (owner_id, subject_user_id, subject_phantom_id) DO UPDATE
SET object_key = EXCLUDED.object_key, blurhash = EXCLUDED.blurhash,
    width = EXCLUDED.width, height = EXCLUDED.height, created_at = now()
''',
        variables: [
          Variable.withString(ownerId),
          Variable<String>(subject.userId),
          Variable<String>(subject.phantomId),
          Variable.withString(key),
          Variable.withString(hash),
          Variable.withInt(width),
          Variable.withInt(height),
        ],
      );
      if (count == 0) throw IdNotFoundException(id: subject.id);
    });

    try {
      await _database.withTransaction(() async {
        // Coordinate only this key with retirement and GC. If another write
        // retired it before we got the lock, never put the object.
        await _database.customStatement(
          r'SELECT public.lock_private_object_gc_key($1)',
          [key],
        );
        if (!await _hasReference(ownerId, key)) {
          throw const IdNotFoundException(
            description: 'The private avatar is no longer current',
          );
        }
        await _storage.putObject(
          key,
          Stream.value(buffered),
          metadata: {
            kHeaderContentType: kContentTypeJpeg,
            if (_env.kS3PutObjectAclValue != null) 'x-amz-acl': 'private',
          },
        );
      }, actorUserId: ownerId);
    } catch (_) {
      // A concurrent replacement has a different key. Deleting this reference
      // lets the existing trigger queue the failed write for collection.
      await _ownerGraph.run(
        {ownerId},
        ownerId,
        (_) => _database.customUpdate(
          r'DELETE FROM public.person_private_avatar WHERE owner_id = $1 AND object_key = $2',
          variables: [Variable.withString(ownerId), Variable.withString(key)],
          updateKind: UpdateKind.delete,
        ),
      );
      rethrow;
    }
  }

  @override
  Future<void> remove({
    required String ownerId,
    required PersonSubject subject,
  }) => _ownerGraph.run({ownerId}, ownerId, (_) async {
    // The row trigger retires the object. An already absent row is success.
    await _database.customUpdate(
      r'''
DELETE FROM public.person_private_avatar
WHERE owner_id = $1
  AND subject_user_id IS NOT DISTINCT FROM $2
  AND subject_phantom_id IS NOT DISTINCT FROM $3
''',
      variables: [
        Variable.withString(ownerId),
        Variable<String>(subject.userId),
        Variable<String>(subject.phantomId),
      ],
      updateKind: UpdateKind.delete,
    );
  });

  @override
  Future<Uint8List> get({
    required String viewerId,
    required String objectKey,
  }) async {
    if (!await _hasReference(viewerId, objectKey)) {
      throw const UnauthorizedException();
    }
    try {
      return await _storage.getObject(objectKey);
    } on MinioS3Error catch (error) {
      if (error.error?.code == 'NoSuchKey') {
        throw const IdNotFoundException();
      }
      rethrow;
    }
  }

  Future<bool> _hasReference(String ownerId, String objectKey) async {
    final row = await _database
        .customSelect(
          r'''
SELECT 1 FROM public.person_private_avatar
WHERE owner_id = $1 AND object_key = $2 LIMIT 1
''',
          variables: [
            Variable.withString(ownerId),
            Variable.withString(objectKey),
          ],
        )
        .getSingleOrNull();
    return row != null;
  }
}

img.Image _decodeAvatar(Uint8List bytes) {
  const invalidJpeg = IdWrongException(description: 'Invalid JPEG image');
  final size = _readJpegFrameSize(bytes);
  if (size == null) throw invalidJpeg;
  if (size.width * size.height > kMaxPrivateAvatarPixels) {
    throw const IdWrongException(description: 'JPEG dimensions are too large');
  }
  try {
    return img.decodeJpg(bytes) ?? (throw invalidJpeg);
  } on img.ImageException {
    throw invalidJpeg;
  }
}

({int width, int height})? _readJpegFrameSize(Uint8List bytes) {
  if (bytes.length < 2 || bytes[0] != 0xff || bytes[1] != 0xd8) return null;
  final view = ByteData.sublistView(bytes);
  var offset = 2;

  // The image decoder allocates frame buffers even in startDecode. Read
  // the start-of-frame header directly, before reaching any scan data.
  while (offset < bytes.length && bytes[offset++] == 0xff) {
    while (offset < bytes.length && bytes[offset] == 0xff) {
      offset++;
    }
    if (offset + 2 >= bytes.length) return null;
    final marker = bytes[offset++];
    final length = view.getUint16(offset);
    if (length < 2 || offset + length > bytes.length) return null;

    switch (marker) {
      case 0xc0 || 0xc1 || 0xc2: // Baseline, extended sequential, progressive.
        if (length < 8) return null;
        final height = view.getUint16(offset + 3);
        final width = view.getUint16(offset + 5);
        final components = bytes[offset + 7];
        if (width == 0 ||
            height == 0 ||
            components < 1 ||
            components > 4 ||
            length != 8 + 3 * components) {
          return null;
        }
        for (var component = 0; component < components; component++) {
          final sampling = bytes[offset + 9 + 3 * component];
          final horizontal = sampling >> 4;
          final vertical = sampling & 0xf;
          if (horizontal < 1 ||
              horizontal > 4 ||
              vertical < 1 ||
              vertical > 4) {
            return null;
          }
        }
        return (width: width, height: height);
      case 0xc4 || 0xdb || 0xdd || >= 0xe0 && <= 0xef || 0xfe:
        offset += length;
      default:
        return null;
    }
  }
  return null;
}
