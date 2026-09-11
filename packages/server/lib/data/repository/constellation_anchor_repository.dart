import 'package:drift/drift.dart' show Variable;
import 'package:injectable/injectable.dart';
import 'package:tentura_server/domain/entity/constellation_anchor.dart';
import 'package:tentura_server/domain/exception.dart';
import 'package:tentura_server/domain/exception_codes.dart';
import 'package:tentura_server/domain/port/constellation_anchor_repository_port.dart';
import 'package:tentura_server/utils/id.dart';

import '../database/postgres_serialization_retry.dart';
import '../database/tentura_db.dart' hide ConstellationAnchor;
import 'constellation_anchor_upsert_authorization.dart';

@LazySingleton(as: ConstellationAnchorRepositoryPort)
class ConstellationAnchorRepository implements ConstellationAnchorRepositoryPort {
  ConstellationAnchorRepository(this._db);

  final TenturaDb _db;

  @override
  Future<ConstellationAnchorUpsertResult> upsertAnchor({
    required String viewerId,
    required String context,
    required ConstellationAnchorTarget target,
    required ConstellationAnchorPosition position,
  }) =>
      withPostgresDeadlockOrSerializationRetry(
        () => _db.withMutatingUser(
          viewerId,
          () => _upsertAnchor(
            viewerId: viewerId,
            context: context,
            target: target,
            position: position,
          ),
        ),
      );

  @override
  Future<ConstellationAnchorDeleteResult> deleteAnchor({
    required String viewerId,
    required ConstellationAnchorTarget target,
  }) =>
      withPostgresDeadlockOrSerializationRetry(
        () => _db.withMutatingUser(
          viewerId,
          () => _deleteAnchor(viewerId: viewerId, target: target),
        ),
      );

  @override
  Future<ConstellationAnchorRevision> readWatermark(String viewerId) async {
    final row = await _db
        .customSelect(
          r'''
SELECT revision
FROM public.constellation_anchor_cursor
WHERE viewer_id = $1
''',
          variables: [Variable<String>(viewerId)],
        )
        .getSingleOrNull();
    if (row == null) {
      return ConstellationAnchorRevision.zero;
    }
    final revision = row.read<BigInt>('revision');
    return ConstellationAnchorRevision(revision);
  }

  Future<ConstellationAnchorUpsertResult> _upsertAnchor({
    required String viewerId,
    required String context,
    required ConstellationAnchorTarget target,
    required ConstellationAnchorPosition position,
  }) async {
    _assertValidMutationTarget(viewerId, target);
    _assertValidPosition(position);

    await _lockViewerCursor(viewerId);

    final authorized = await isConstellationAnchorUpsertAuthorized(
      _db,
      viewerId: viewerId,
      context: context,
      target: target,
    );
    if (!authorized) {
      throw ConstellationException(
        constellationCode: ConstellationExceptionCode.targetUnavailable,
      );
    }

    final updated = await _updateExistingAnchor(
      viewerId: viewerId,
      target: target,
      position: position,
    );
    if (updated != null) {
      final refreshedWatermark = await _readLockedWatermark(viewerId);
      return ConstellationAnchorUpsertResult(
        anchor: updated,
        watermark: refreshedWatermark,
      );
    }

    final inserted = await _insertAnchor(
      viewerId: viewerId,
      target: target,
      position: position,
    );
    final refreshedWatermark = await _readLockedWatermark(viewerId);
    return ConstellationAnchorUpsertResult(
      anchor: inserted,
      watermark: refreshedWatermark,
    );
  }

  Future<ConstellationAnchorDeleteResult> _deleteAnchor({
    required String viewerId,
    required ConstellationAnchorTarget target,
  }) async {
    _assertValidMutationTarget(viewerId, target);

    await _lockViewerCursor(viewerId);

    final deleted = await _deleteExistingAnchor(viewerId: viewerId, target: target);
    if (deleted != null) {
      final watermark = await _readLockedWatermark(viewerId);
      return ConstellationAnchorDeleteResult(
        target: target,
        watermark: watermark,
      );
    }

    final watermark = await _incrementCursorAndPublishAbsentDelete(viewerId);
    return ConstellationAnchorDeleteResult(
      target: target,
      watermark: watermark,
    );
  }

  void _assertValidMutationTarget(String viewerId, ConstellationAnchorTarget target) {
    final validation = validateConstellationAnchorTarget(
      target: target,
      viewerId: viewerId,
    );
    if (validation is! ConstellationAnchorTargetValid) {
      throw ConstellationException(
        constellationCode: ConstellationExceptionCode.invalidTarget,
      );
    }
  }

  void _assertValidPosition(ConstellationAnchorPosition position) {
    final validation = ConstellationAnchorPosition.validate(
      xUnits: position.xUnits,
      yUnits: position.yUnits,
      coordinateSpaceVersion: position.coordinateSpaceVersion,
    );
    switch (validation) {
      case ConstellationAnchorPositionValid():
        return;
      case ConstellationAnchorPositionInvalid(:final reason):
        throw ConstellationException(
          constellationCode: switch (reason) {
            ConstellationAnchorPositionInvalidReason.unsupportedCoordinateSpace =>
              ConstellationExceptionCode.unsupportedCoordinateSpace,
            ConstellationAnchorPositionInvalidReason.nonFinite ||
            ConstellationAnchorPositionInvalidReason.outOfRange =>
              ConstellationExceptionCode.invalidCoordinates,
          },
        );
    }
  }

  Future<ConstellationAnchorWatermark> _lockViewerCursor(String viewerId) async {
    await _ensureViewerCursor(viewerId);
    await _db.customStatement(
      r'''
SELECT viewer_id
FROM public.constellation_anchor_cursor
WHERE viewer_id = $1
FOR UPDATE
''',
      [viewerId],
    );
    return _readLockedWatermark(viewerId);
  }

  Future<void> _ensureViewerCursor(String viewerId) async {
    await _db.customStatement(
      r'''
INSERT INTO public.constellation_anchor_cursor (viewer_id)
VALUES ($1)
ON CONFLICT (viewer_id) DO NOTHING
''',
      [viewerId],
    );
  }

  Future<ConstellationAnchorWatermark> _readLockedWatermark(String viewerId) async {
    final row = await _db
        .customSelect(
          r'''
SELECT revision
FROM public.constellation_anchor_cursor
WHERE viewer_id = $1
''',
          variables: [Variable<String>(viewerId)],
        )
        .getSingle();
    return ConstellationAnchorWatermark(
      ConstellationAnchorRevision(row.read<BigInt>('revision')),
    );
  }

  Future<ConstellationAnchor?> _updateExistingAnchor({
    required String viewerId,
    required ConstellationAnchorTarget target,
    required ConstellationAnchorPosition position,
  }) async {
    final personId = target.kind == ConstellationAnchorTargetKind.person
        ? target.id
        : null;
    final beaconId = target.kind == ConstellationAnchorTargetKind.beacon
        ? target.id
        : null;

    final row = await _db
        .customSelect(
          r'''
UPDATE public.constellation_anchor
SET
  x_units = $4,
  y_units = $5,
  coordinate_space_version = $6
WHERE viewer_id = $1
  AND (
    ($2::text IS NOT NULL AND person_id = $2)
    OR ($3::text IS NOT NULL AND beacon_id = $3)
  )
RETURNING
  id,
  viewer_id,
  person_id,
  beacon_id,
  x_units,
  y_units,
  coordinate_space_version,
  revision,
  placed_at
''',
          variables: [
            Variable<String>(viewerId),
            Variable<String>(personId),
            Variable<String>(beaconId),
            Variable<double>(position.xUnits),
            Variable<double>(position.yUnits),
            Variable<int>(position.coordinateSpaceVersion),
          ],
        )
        .getSingleOrNull();
    if (row == null) {
      return null;
    }
    return _rowToAnchor(row);
  }

  Future<ConstellationAnchor> _insertAnchor({
    required String viewerId,
    required ConstellationAnchorTarget target,
    required ConstellationAnchorPosition position,
  }) async {
    final id = generateId('CA');
    final personId = target.kind == ConstellationAnchorTargetKind.person
        ? target.id
        : null;
    final beaconId = target.kind == ConstellationAnchorTargetKind.beacon
        ? target.id
        : null;

    final row = await _db
        .customSelect(
          r'''
INSERT INTO public.constellation_anchor (
  id,
  viewer_id,
  person_id,
  beacon_id,
  x_units,
  y_units,
  coordinate_space_version,
  revision,
  placed_at
) VALUES (
  $1, $2, $3, $4, $5, $6, $7, 0, 'epoch'::timestamptz
)
RETURNING
  id,
  viewer_id,
  person_id,
  beacon_id,
  x_units,
  y_units,
  coordinate_space_version,
  revision,
  placed_at
''',
          variables: [
            Variable<String>(id),
            Variable<String>(viewerId),
            Variable<String>(personId),
            Variable<String>(beaconId),
            Variable<double>(position.xUnits),
            Variable<double>(position.yUnits),
            Variable<int>(position.coordinateSpaceVersion),
          ],
        )
        .getSingle();
    return _rowToAnchor(row);
  }

  Future<ConstellationAnchorTarget?> _deleteExistingAnchor({
    required String viewerId,
    required ConstellationAnchorTarget target,
  }) async {
    final personId = target.kind == ConstellationAnchorTargetKind.person
        ? target.id
        : null;
    final beaconId = target.kind == ConstellationAnchorTargetKind.beacon
        ? target.id
        : null;

    final row = await _db
        .customSelect(
          r'''
DELETE FROM public.constellation_anchor
WHERE viewer_id = $1
  AND (
    ($2::text IS NOT NULL AND person_id = $2)
    OR ($3::text IS NOT NULL AND beacon_id = $3)
  )
RETURNING person_id, beacon_id
''',
          variables: [
            Variable<String>(viewerId),
            Variable<String>(personId),
            Variable<String>(beaconId),
          ],
        )
        .getSingleOrNull();
    if (row == null) {
      return null;
    }
    return target;
  }

  Future<ConstellationAnchorWatermark> _incrementCursorAndPublishAbsentDelete(
    String viewerId,
  ) async {
    final row = await _db
        .customSelect(
          r'''
UPDATE public.constellation_anchor_cursor
SET revision = revision + 1
WHERE viewer_id = $1
RETURNING revision
''',
          variables: [Variable<String>(viewerId)],
        )
        .getSingle();
    await _db.customStatement(
      r'''
SELECT public.emit_realtime_entity_change_strict(
  'constellation_anchor',
  $1,
  'delete',
  ARRAY[$1]::text[]
)
''',
      [viewerId],
    );
    return ConstellationAnchorWatermark(
      ConstellationAnchorRevision(row.read<BigInt>('revision')),
    );
  }

  ConstellationAnchor _rowToAnchor(QueryRow row) {
    final personId = row.read<String?>('person_id');
    final beaconId = row.read<String?>('beacon_id');
    final target = personId != null
        ? ConstellationAnchorTarget.person(personId)
        : ConstellationAnchorTarget.beacon(beaconId!);
    final placedAt = DateTime.parse(row.read<String>('placed_at'));
    return ConstellationAnchor(
      target: target,
      position: ConstellationAnchorPosition(
        xUnits: row.read<double>('x_units'),
        yUnits: row.read<double>('y_units'),
        coordinateSpaceVersion: row.read<int>('coordinate_space_version'),
      ),
      revision: ConstellationAnchorRevision(row.read<BigInt>('revision')),
      placedAt: placedAt.toUtc(),
    );
  }

}
