import 'dart:convert';

import 'package:crypto/crypto.dart';
import 'package:injectable/injectable.dart';
import 'package:postgres/postgres.dart' show ServerException, Type, TypedValue;
import 'package:tentura_root/domain/constellation/constellation_anchor.dart';
import 'package:tentura_server/domain/port/constellation_anchor_repository_port.dart';
import 'package:tentura_server/domain/port/constellation_db_admission_port.dart';
import 'package:tentura_server/utils/id.dart';

import '../database/postgres_serialization_retry.dart';
import '../database/tentura_db.dart' hide ConstellationAnchor;

@LazySingleton(as: ConstellationAnchorRepositoryPort)
class ConstellationAnchorRepository
    implements ConstellationAnchorRepositoryPort {
  /// Attempts within the existing five-second transaction retry budget.
  static const int applyBatchMaxAttempts = 10;

  ConstellationAnchorRepository(
    this._db, [
    @ignoreParam ConstellationDbAdmissionPort? _,
  ]);

  @FactoryMethod()
  ConstellationAnchorRepository.injected(
    this._db, [
    @ignoreParam ConstellationDbAdmissionPort? _,
  ]);

  final TenturaDb _db;

  @override
  Future<AnchorApplyBatchResult> applyBatch({
    required String viewerId,
    required List<AnchorApplyOp> ops,
  }) => _applyBatchInTx(viewerId: viewerId, ops: ops);

  Future<AnchorApplyBatchResult> _applyBatchInTx({
    required String viewerId,
    required List<AnchorApplyOp> ops,
  }) => _db.withMutatingRepeatableRead(
    viewerId,
    maxAttempts: applyBatchMaxAttempts,
    () async {
      await _lockViewerBatch(viewerId);
      final before = await _lockViewerCursor(viewerId);
      final existingTargets = await _existingUpsertTargets(ops);
      final recordedRows = await _db
          .customSelect(
            r'''
SELECT client_op_id, encode(fingerprint, 'hex') AS fingerprint,
       result::text AS result
FROM public.constellation_anchor_op_log
WHERE viewer_id = $1 AND client_op_id = ANY($2::text[])
''',
            variables: [
              Variable<String>(viewerId),
              Variable(
                TypedValue(
                  Type.textArray,
                  ops.map((op) => op.clientOpId).toList(),
                ),
              ),
            ],
          )
          .get();
      final recordedById = {
        for (final row in recordedRows) row.read<String>('client_op_id'): row,
      };
      final watermarkRows = await _db
          .customSelect(
            r'''
SELECT target_kind, target_id, revision
FROM public.constellation_anchor_target_watermark
WHERE viewer_id = $1 AND (target_kind, target_id) IN (
  SELECT * FROM unnest($2::text[], $3::text[])
)
''',
            variables: [
              Variable<String>(viewerId),
              Variable(
                TypedValue(
                  Type.textArray,
                  ops.map((op) => op.target.kind.wireValue).toList(),
                ),
              ),
              Variable(
                TypedValue(
                  Type.textArray,
                  ops.map((op) => op.target.id).toList(),
                ),
              ),
            ],
          )
          .get();
      final watermarks = {
        for (final row in watermarkRows)
          (row.read<String>('target_kind'), row.read<String>('target_id')):
              ConstellationAnchorRevision(row.read<BigInt>('revision')),
      };
      // Decide every operation in input order. The cursor is locked, so each
      // accepted write advances it by exactly one: the resulting revisions are
      // known before any write, and the writes, watermarks and op-log rows go
      // to the server in one round trip (m0231 verifies the predicted revisions).
      final results = <AnchorApplyOpResult>[];
      final writes = _BatchWrites(viewerId);
      var revision = before.revision.value;
      for (final op in ops) {
        final fingerprint = _opFingerprint(op);
        final recorded = recordedById[op.clientOpId];
        if (recorded != null) {
          results.add(
            recorded.read<String>('fingerprint') == fingerprint
                ? _recordedResult(
                    op.clientOpId,
                    recorded.read<String>('result'),
                  )
                : _rejected(op, 'op_id_reused'),
          );
          continue;
        }
        final rejection = _batchOpRejection(
          viewerId,
          op,
          targetExists: existingTargets.contains(op.target),
          targetRevision:
              watermarks[(op.target.kind.wireValue, op.target.id)] ??
              ConstellationAnchorRevision.zero,
        );
        final AnchorApplyOpResult result;
        if (rejection != null) {
          result = rejection;
        } else {
          revision += BigInt.one;
          result = AnchorApplyOpResult(
            clientOpId: op.clientOpId,
            status: AnchorOpStatus.ok,
            resultingTargetRevision: ConstellationAnchorRevision(revision),
            position: op.kind == AnchorOpKind.upsert ? op.position : null,
          );
        }
        writes.add(
          op,
          fingerprint: fingerprint,
          result: result,
          payload: _resultPayload(result),
          revision: revision,
          anchorId: rejection == null && op.kind == AnchorOpKind.upsert
              ? generateId('CA')
              : '',
        );
        results.add(result);
      }
      try {
        await writes.flush(_db);
      } on ServerException catch (error) {
        // A target deleted after our snapshot may fail the FK check. Roll
        // back the whole batch and recheck existence in a fresh snapshot.
        if (error.code != '23503' ||
            !const {
              'constellation_anchor_person_id_fkey',
              'constellation_anchor_beacon_id_fkey',
            }.contains(error.constraintName)) {
          rethrow;
        }
        throw PostgresSnapshotUnavailableException(error);
      }
      final anchors = await _storedAnchors(viewerId, [
        for (final (i, result) in results.indexed)
          if (result.status == AnchorOpStatus.ok &&
              ops[i].kind == AnchorOpKind.upsert)
            ops[i].target,
      ]);
      return AnchorApplyBatchResult(
        beforeRevision: before.revision,
        afterRevision: ConstellationAnchorRevision(revision),
        results: [
          for (final (i, result) in results.indexed)
            AnchorApplyOpResult(
              clientOpId: result.clientOpId,
              status: result.status,
              reason: result.reason,
              resultingTargetRevision: result.resultingTargetRevision,
              position: result.position,
              replayed: result.replayed,
              anchor:
                  result.status == AnchorOpStatus.ok &&
                      ops[i].kind == AnchorOpKind.upsert
                  ? anchors[ops[i].target]
                  : null,
            ),
        ],
      );
    },
  );

  Future<Set<ConstellationAnchorTarget>> _existingUpsertTargets(
    List<AnchorApplyOp> ops,
  ) async {
    final targets = [
      for (final op in ops)
        if (op.kind == AnchorOpKind.upsert) op.target,
    ];
    if (targets.isEmpty) return {};
    final rows = await _db
        .customSelect(
          r'''
        WITH targets AS (
          SELECT * FROM unnest($1::text[], $2::text[]) AS t(kind, id)
        )
        SELECT t.kind, t.id FROM targets t
        JOIN public."user" u ON u.id = t.id WHERE t.kind = 'PERSON'
        UNION ALL
        SELECT t.kind, t.id FROM targets t
        JOIN public.beacon b ON b.id = t.id WHERE t.kind = 'BEACON'
      ''',
          variables: [
            Variable(
              TypedValue(
                Type.textArray,
                targets.map((t) => t.kind.wireValue).toList(),
              ),
            ),
            Variable(
              TypedValue(Type.textArray, targets.map((t) => t.id).toList()),
            ),
          ],
        )
        .get();
    return {
      for (final row in rows)
        if (row.read<String>('kind') == 'PERSON')
          ConstellationAnchorTarget.person(row.read<String>('id'))
        else
          ConstellationAnchorTarget.beacon(row.read<String>('id')),
    };
  }

  Future<Map<ConstellationAnchorTarget, ConstellationAnchor>> _storedAnchors(
    String viewerId,
    List<ConstellationAnchorTarget> targets,
  ) async {
    if (targets.isEmpty) return {};
    final rows = await _db
        .customSelect(
          r'''
        SELECT person_id, beacon_id, x_units, y_units,
               coordinate_space_version, revision::text AS revision,
               placed_at::text AS placed_at
        FROM public.constellation_anchor
        WHERE viewer_id = $1
          AND (person_id = ANY($2::text[]) OR beacon_id = ANY($3::text[]))
      ''',
          variables: [
            Variable<String>(viewerId),
            Variable(
              TypedValue(Type.textArray, [
                for (final t in targets)
                  if (t.kind == ConstellationAnchorTargetKind.person) t.id,
              ]),
            ),
            Variable(
              TypedValue(Type.textArray, [
                for (final t in targets)
                  if (t.kind == ConstellationAnchorTargetKind.beacon) t.id,
              ]),
            ),
          ],
        )
        .get();
    final anchors = <ConstellationAnchorTarget, ConstellationAnchor>{};
    for (final row in rows) {
      final personId = row.readNullable<String>('person_id');
      final target = personId != null
          ? ConstellationAnchorTarget.person(personId)
          : ConstellationAnchorTarget.beacon(row.read<String>('beacon_id'));
      anchors[target] = ConstellationAnchor(
        target: target,
        position: ConstellationAnchorPosition(
          xUnits: row.read<double>('x_units'),
          yUnits: row.read<double>('y_units'),
          coordinateSpaceVersion: row.read<int>('coordinate_space_version'),
        ),
        revision: switch (ConstellationAnchorRevision.parseDecimalString(
          row.read<String>('revision'),
        )) {
          ConstellationAnchorRevisionParsed(:final revision) => revision,
          ConstellationAnchorRevisionMalformed() =>
            ConstellationAnchorRevision.zero,
        },
        placedAt: DateTime.parse(row.read<String>('placed_at')).toUtc(),
      );
    }
    return anchors;
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

  /// The rejection of [op], or null when it is accepted and must be written.
  AnchorApplyOpResult? _batchOpRejection(
    String viewerId,
    AnchorApplyOp op, {
    required bool targetExists,
    required ConstellationAnchorRevision targetRevision,
  }) {
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
      if (!targetExists) {
        return _rejected(op, 'target_not_found');
      }
    }
    if (op.ifRevision != null && op.ifRevision != targetRevision) {
      return _rejected(op, 'conflict');
    }
    return null;
  }

  /// The minimal op-log result: status, reason, revision and position.
  String _resultPayload(AnchorApplyOpResult result) {
    final position = result.position;
    final revision = result.resultingTargetRevision;
    return jsonEncode({
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
  }

  AnchorApplyOpResult _recordedResult(String clientOpId, String payload) {
    final result = jsonDecode(payload) as Map<String, dynamic>;
    final position = result['position'] as List<dynamic>?;
    final revision = result['revision'] as String?;
    return AnchorApplyOpResult(
      clientOpId: clientOpId,
      replayed: true,
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

  /// Serializes this viewer's batches (lock-first order). Waiting means the
  /// previous holder committed after this transaction's snapshot, so the
  /// cursor lock would fail with 40001 after a wasted preparation: fail now.
  Future<void> _lockViewerBatch(String viewerId) async {
    const key = r"hashtextextended('constellation_anchor_apply:' || $1, 4242)";
    final acquired = await _db
        .customSelect(
          'SELECT pg_try_advisory_xact_lock($key) AS acquired',
          variables: [Variable<String>(viewerId)],
        )
        .getSingle();
    if (acquired.read<bool>('acquired')) return;
    await _db
        .customSelect(
          'SELECT pg_advisory_xact_lock($key) IS NULL AS waited',
          variables: [Variable<String>(viewerId)],
        )
        .getSingle();
    throw PostgresSnapshotUnavailableException(
      StateError('waited for the viewer batch lock; snapshot predates it'),
    );
  }

  Future<ConstellationAnchorWatermark> _lockViewerCursor(
    String viewerId,
  ) async {
    Future<QueryRow?> lock() => _db
        .customSelect(
          r'''
SELECT revision
FROM public.constellation_anchor_cursor
WHERE viewer_id = $1
FOR UPDATE
''',
          variables: [Variable<String>(viewerId)],
        )
        .getSingleOrNull();
    // The cursor row exists after the viewer's first write; create it once.
    var row = await lock();
    if (row == null) {
      await _ensureViewerCursor(viewerId);
      row = await lock();
    }
    return ConstellationAnchorWatermark(
      ConstellationAnchorRevision(row!.read<BigInt>('revision')),
    );
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
}

/// The decided operations of one batch, sent to
/// `constellation_anchor_apply_ops` (m0231) in input order.
final class _BatchWrites {
  _BatchWrites(this.viewerId);

  final String viewerId;
  final _write = <bool>[];
  final _delete = <bool>[];
  final _targetKinds = <String>[];
  final _targetIds = <String>[];
  final _anchorIds = <String>[];
  final _x = <double>[];
  final _y = <double>[];
  final _coordinateSpaceVersions = <int>[];
  final _clientOpIds = <String>[];
  final _fingerprints = <String>[];
  final _payloads = <String>[];
  final _revisions = <String>[];

  void add(
    AnchorApplyOp op, {
    required String fingerprint,
    required AnchorApplyOpResult result,
    required String payload,
    required BigInt revision,
    required String anchorId,
  }) {
    final position = op.position;
    _write.add(result.status == AnchorOpStatus.ok);
    _delete.add(op.kind == AnchorOpKind.delete);
    _targetKinds.add(op.target.kind.wireValue);
    _targetIds.add(op.target.id);
    _anchorIds.add(anchorId);
    _x.add(position?.xUnits ?? 0);
    _y.add(position?.yUnits ?? 0);
    _coordinateSpaceVersions.add(position?.coordinateSpaceVersion ?? 0);
    _clientOpIds.add(op.clientOpId);
    _fingerprints.add(fingerprint);
    _payloads.add(payload);
    _revisions.add(revision.toString());
  }

  Future<void> flush(TenturaDb db) async {
    if (_clientOpIds.isEmpty) return;
    await db
        .customSelect(
          r'''
SELECT public.constellation_anchor_apply_ops(
  $1, $2::boolean[], $3::boolean[], $4::text[], $5::text[], $6::text[],
  $7::double precision[], $8::double precision[], $9::integer[],
  $10::text[], $11::text[], $12::text[]::jsonb[], $13::text[]::bigint[]
)
''',
          variables: [
            Variable<String>(viewerId),
            Variable(TypedValue(Type.booleanArray, _write)),
            Variable(TypedValue(Type.booleanArray, _delete)),
            Variable(TypedValue(Type.textArray, _targetKinds)),
            Variable(TypedValue(Type.textArray, _targetIds)),
            Variable(TypedValue(Type.textArray, _anchorIds)),
            Variable(TypedValue(Type.doubleArray, _x)),
            Variable(TypedValue(Type.doubleArray, _y)),
            Variable(TypedValue(Type.integerArray, _coordinateSpaceVersions)),
            Variable(TypedValue(Type.textArray, _clientOpIds)),
            Variable(TypedValue(Type.textArray, _fingerprints)),
            Variable(TypedValue(Type.textArray, _payloads)),
            Variable(TypedValue(Type.textArray, _revisions)),
          ],
        )
        .get();
  }
}
