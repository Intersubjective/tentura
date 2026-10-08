import 'dart:convert';

import 'package:crypto/crypto.dart';
import 'package:get_it/get_it.dart';
import 'package:injectable/injectable.dart';
import 'package:tentura_root/domain/constellation/constellation_anchor.dart';
import 'package:tentura_server/domain/exception.dart';
import 'package:tentura_server/domain/exception_codes.dart';
import 'package:tentura_server/domain/port/constellation_anchor_repository_port.dart';
import 'package:tentura_server/domain/port/user_profile_batch_lookup_port.dart';
import 'package:tentura_server/utils/id.dart';

import '../database/postgres_serialization_retry.dart';
import '../database/tentura_db.dart' hide ConstellationAnchor;
import 'constellation_anchor_projection_reader.dart';
import 'constellation_anchor_upsert_authorization.dart';

@LazySingleton(as: ConstellationAnchorRepositoryPort)
class ConstellationAnchorRepository
    implements ConstellationAnchorRepositoryPort {
  ConstellationAnchorRepository(this._db, [this._profiles]);

  @FactoryMethod()
  ConstellationAnchorRepository.injected(
    this._db,
    UserProfileBatchLookup profiles,
  ) : _profiles = profiles;

  final TenturaDb _db;
  final UserProfileBatchLookup? _profiles;

  @override
  Future<AnchorApplyBatchResult> applyBatch({
    required String viewerId,
    required List<AnchorApplyOp> ops,
    required AnchorApplyParams params,
  }) => _db.withMutatingRepeatableRead(viewerId, () async {
    final before = await _lockViewerCursor(viewerId);
    await _prepareBatchVisibility(viewerId, params.context);
    final results = <AnchorApplyOpResult>[];
    for (final op in ops) {
      final fingerprint = _opFingerprint(op);
      final recorded = await _db
          .customSelect(
            r'''
SELECT fingerprint = decode($3, 'hex') AS same_fingerprint,
       result::text AS result
FROM public.constellation_anchor_op_log
WHERE viewer_id = $1 AND client_op_id = $2
''',
            variables: [
              Variable<String>(viewerId),
              Variable<String>(op.clientOpId),
              Variable<String>(fingerprint),
            ],
          )
          .getSingleOrNull();
      if (recorded != null) {
        results.add(
          recorded.read<bool>('same_fingerprint')
              ? _recordedResult(op.clientOpId, recorded.read<String>('result'))
              : _rejected(op, 'op_id_reused'),
        );
        continue;
      }
      final result = await _applyBatchOp(viewerId, params.context, op);
      await _recordBatchOp(viewerId, op, fingerprint, result);
      results.add(result);
    }
    final projection =
        await ConstellationAnchorProjectionReader(
          _db,
          _profiles ?? GetIt.I<UserProfileBatchLookup>(),
        ).read(
          viewerId: viewerId,
          context: params.context,
          filters: params.filters,
        );
    return AnchorApplyBatchResult(
      beforeRevision: before.revision,
      afterRevision: projection.revision,
      results: results,
      projection: projection,
    );
  });

  Future<void> _prepareBatchVisibility(String viewerId, String context) async {
    await _db.freezeVisibilityMemo();
    // Seed the existing frozen memo from the service directly. Unlike the
    // fail-closed read helper, a service error must abort the entire batch.
    await _db.customStatement(
      r'''
SELECT set_config(
  'tentura_visibility.p' || md5(trim($1::text) || chr(31) || $2::text),
  coalesce((SELECT epoch FROM public.mr_publish_epoch WHERE id = true), 0)::text
    || ':' || public.direct_trust_current_version()::text || ':'
    || coalesce(array_agg(s.peer_id ORDER BY s.peer_id), '{}'::text[])::text,
  true
)
FROM public.person_visible_peers_symmetric($1, $2) s
''',
      [viewerId, context],
    );
  }

  String _opFingerprint(AnchorApplyOp op) {
    final position = op.position;
    return sha256
        .convert(
          utf8.encode(
            jsonEncode([
              op.kind.wireValue,
              op.target.kind.wireValue,
              op.target.id,
              if (position == null)
                null
              else
                [
                  position.xUnits.toString(),
                  position.yUnits.toString(),
                  position.coordinateSpaceVersion,
                ],
              op.ifRevision?.toDecimalString(),
            ]),
          ),
        )
        .toString();
  }

  AnchorApplyOpResult _rejected(AnchorApplyOp op, String reason) =>
      AnchorApplyOpResult(
        clientOpId: op.clientOpId,
        status: AnchorOpStatus.rejected,
        reason: reason,
      );

  Future<AnchorApplyOpResult> _applyBatchOp(
    String viewerId,
    String context,
    AnchorApplyOp op,
  ) async {
    if (validateConstellationAnchorTarget(target: op.target, viewerId: viewerId)
        is! ConstellationAnchorTargetValid) {
      return _rejected(op, 'invalid_target');
    }
    final position = op.position;
    if (op.kind == AnchorOpKind.upsert) {
      if (position == null) return _rejected(op, 'invalid_coordinates');
      final validation = ConstellationAnchorPosition.validate(
        xUnits: position.xUnits,
        yUnits: position.yUnits,
        coordinateSpaceVersion: position.coordinateSpaceVersion,
      );
      if (validation is ConstellationAnchorPositionInvalid) {
        final reason = switch (validation.reason) {
          ConstellationAnchorPositionInvalidReason.unsupportedCoordinateSpace =>
            'unsupported_coordinate_space',
          ConstellationAnchorPositionInvalidReason.nonFinite ||
          ConstellationAnchorPositionInvalidReason.outOfRange =>
            'invalid_coordinates',
        };
        return _rejected(op, reason);
      }
      if (!await isConstellationAnchorUpsertAuthorized(
        _db,
        viewerId: viewerId,
        context: context,
        target: op.target,
      )) {
        return _rejected(op, 'target_unavailable');
      }
    }
    if (op.ifRevision != null) {
      final row = await _db
          .customSelect(
            r'''
SELECT revision FROM public.constellation_anchor_target_watermark
WHERE viewer_id = $1 AND target_kind = $2 AND target_id = $3
''',
            variables: [
              Variable<String>(viewerId),
              Variable<String>(op.target.kind.wireValue),
              Variable<String>(op.target.id),
            ],
          )
          .getSingleOrNull();
      final revision = row == null
          ? ConstellationAnchorRevision.zero
          : ConstellationAnchorRevision(row.read<BigInt>('revision'));
      if (op.ifRevision != revision) return _rejected(op, 'conflict');
    }
    if (op.kind == AnchorOpKind.upsert) {
      final updated = await _updateExistingAnchor(
        viewerId: viewerId,
        target: op.target,
        position: position!,
      );
      if (updated == null) {
        await _insertAnchor(
          viewerId: viewerId,
          target: op.target,
          position: position,
        );
      }
    } else {
      final deleted = await _deleteExistingAnchor(
        viewerId: viewerId,
        target: op.target,
      );
      if (deleted == null) await _incrementCursor(viewerId);
    }
    final watermark = await _readLockedWatermark(viewerId);
    await _db.customStatement(
      r'''
INSERT INTO public.constellation_anchor_target_watermark
  (viewer_id, target_kind, target_id, revision)
VALUES ($1, $2, $3, $4)
ON CONFLICT (viewer_id, target_kind, target_id)
DO UPDATE SET revision = EXCLUDED.revision
''',
      [
        viewerId,
        op.target.kind.wireValue,
        op.target.id,
        watermark.revision.value,
      ],
    );
    return AnchorApplyOpResult(
      clientOpId: op.clientOpId,
      status: AnchorOpStatus.ok,
      resultingTargetRevision: watermark.revision,
      position: op.kind == AnchorOpKind.upsert ? position : null,
    );
  }

  Future<void> _recordBatchOp(
    String viewerId,
    AnchorApplyOp op,
    String fingerprint,
    AnchorApplyOpResult result,
  ) async {
    final position = result.position;
    final revision = result.resultingTargetRevision;
    final payload = jsonEncode({
      'status': result.status.wireValue,
      if (result.reason != null) 'reason': result.reason,
      if (revision != null) 'revision': revision.toDecimalString(),
      if (position != null)
        'position': [
          position.xUnits,
          position.yUnits,
          position.coordinateSpaceVersion,
        ],
    });
    await _db.customStatement(
      r'''
INSERT INTO public.constellation_anchor_op_log
  (viewer_id, client_op_id, fingerprint, result, revision)
VALUES ($1, $2, decode($3, 'hex'), $4::jsonb, $5)
''',
      [
        viewerId,
        op.clientOpId,
        fingerprint,
        payload,
        (revision ?? await readWatermark(viewerId)).value,
      ],
    );
  }

  AnchorApplyOpResult _recordedResult(String clientOpId, String payload) {
    final result = jsonDecode(payload) as Map<String, dynamic>;
    final position = result['position'] as List<dynamic>?;
    final revision = result['revision'] as String?;
    return AnchorApplyOpResult(
      clientOpId: clientOpId,
      status: result['status'] == AnchorOpStatus.ok.wireValue
          ? AnchorOpStatus.ok
          : AnchorOpStatus.rejected,
      reason: result['reason'] as String?,
      resultingTargetRevision: revision == null
          ? null
          : ConstellationAnchorRevision(BigInt.parse(revision)),
      position: position == null
          ? null
          : ConstellationAnchorPosition(
              xUnits: (position[0] as num).toDouble(),
              yUnits: (position[1] as num).toDouble(),
              coordinateSpaceVersion: position[2] as int,
            ),
    );
  }

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

    await _db.freezeVisibilityMemo();
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

    final watermark = await _incrementCursor(viewerId);
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

  Future<ConstellationAnchorWatermark> _incrementCursor(
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
