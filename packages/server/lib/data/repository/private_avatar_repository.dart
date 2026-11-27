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
import 'package:tentura_server/domain/request_context.dart';
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
    final request = RequestContext.current;
    final avatarIdentity = [
      Variable.withString(ownerId),
      Variable<String>(subject.userId),
      Variable<String>(subject.phantomId),
      Variable.withString(key),
    ];

    // Record the candidate before PUT so a crash leaves a collectible key.
    // The grace period keeps normal uploads out of the collector's way.
    await _ownerGraph.run({ownerId}, ownerId, (_) async {
      await _quota.reserveUploadBytes(
        userId: ownerId,
        bytes: buffered.length,
        dailyCapBytes: _env.uploadDailyCapBytes,
      );
      final count = await _database.customUpdate(
        r'''
INSERT INTO public.private_object_gc (object_key, next_attempt_at)
SELECT $4, clock_timestamp() + interval '10 minutes'
'''
        '$_eligibleSubject',
        variables: avatarIdentity,
      );
      if (count == 0) throw IdNotFoundException(id: subject.id);
    });

    try {
      request?.check();
      await _storage.putObject(
        key,
        Stream.value(buffered),
        metadata: {
          kHeaderContentType: kContentTypeJpeg,
          if (_env.kS3PutObjectAclValue != null) 'x-amz-acl': 'private',
        },
      );
      request?.check();

      await _ownerGraph.run({ownerId}, ownerId, (_) async {
        // Claim and publication compete for the queue row. Once a collector
        // has claimed it, this upload must never publish the key.
        final pending = await _database.customUpdate(
          r'''
DELETE FROM public.private_object_gc
WHERE object_key = $1 AND attempts = 0 AND lease_owner IS NULL
''',
          variables: [Variable.withString(key)],
          updateKind: UpdateKind.delete,
        );
        if (pending == 0) {
          throw const IdNotFoundException(
            description: 'The private avatar upload is no longer pending',
          );
        }
        final count = await _database.customUpdate(
          r'''
INSERT INTO public.person_private_avatar
  (owner_id, subject_user_id, subject_phantom_id, object_key, blurhash, width, height)
SELECT $1, $2, $3, $4, $5, $6, $7
'''
          '$_eligibleSubject'
          '''
ON CONFLICT (owner_id, subject_user_id, subject_phantom_id) DO UPDATE
SET object_key = EXCLUDED.object_key, blurhash = EXCLUDED.blurhash,
    width = EXCLUDED.width, height = EXCLUDED.height, created_at = now()
''',
          variables: [
            ...avatarIdentity,
            Variable.withString(hash),
            Variable.withInt(width),
            Variable.withInt(height),
          ],
        );
        if (count == 0) throw IdNotFoundException(id: subject.id);
      });
    } catch (_) {
      await _retireAttempt(key, request);
      rethrow;
    }
  }

  static const _eligibleSubject = r'''
WHERE EXISTS (SELECT 1 FROM public."user" WHERE id = $2)
   OR EXISTS (SELECT 1 FROM public.phantom WHERE id = $3 AND owner_id = $1)
''';

  Future<void> _retireAttempt(String key, RequestContext? request) async {
    // Make even a late PUT collectible again. Invalidate an earlier GC
    // lease so its acknowledgement cannot discard this cleanup.
    Future<void> enqueue() => _database.customStatement(
      r'''
INSERT INTO public.private_object_gc (object_key) VALUES ($1)
ON CONFLICT (object_key) DO UPDATE
SET next_attempt_at = clock_timestamp(), attempts = 0,
    lease_owner = NULL, lease_until = NULL, last_error = NULL
''',
      [key],
    );
    if (request == null) return enqueue();
    // Cleanup gets its own budget even if the uploader disconnected.
    final cleanup = RequestContext(requestId: request.requestId)
      ..actor = request.actor;
    try {
      await cleanup.run(enqueue);
    } finally {
      cleanup.dispose();
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
