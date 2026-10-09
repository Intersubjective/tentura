import 'dart:convert';

import 'package:crypto/crypto.dart';
import 'package:get_it/get_it.dart';
import 'package:injectable/injectable.dart';
import 'package:postgres/postgres.dart' show ServerException, Type, TypedValue;
import 'package:tentura_root/domain/constellation/constellation_anchor.dart';
import 'package:tentura_server/domain/port/constellation_anchor_repository_port.dart';
import 'package:tentura_server/domain/port/constellation_db_admission_port.dart';
import 'package:tentura_server/domain/port/user_profile_batch_lookup_port.dart';
import 'package:tentura_server/utils/id.dart';

import '../database/postgres_serialization_retry.dart';
import '../database/tentura_db.dart' hide ConstellationAnchor;
import 'constellation_anchor_projection_reader.dart';

@LazySingleton(as: ConstellationAnchorRepositoryPort)
class ConstellationAnchorRepository
    implements ConstellationAnchorRepositoryPort {
  /// Release order of `applyBatch` (ARCH §4.4), chosen by the U13 contention
  /// gate: 2/4/8 tabs of one viewer, lock-first if exhausted retries exceed
  /// 1 % or wasted preparation exceeds 20 % of DB time at 4 tabs.
  ///
  /// - false (prepare-first): visibility, trust edges and profiles are
  ///   prepared, then the cursor is locked. A writer that commits in between
  ///   makes the lock fail with 40001 and the preparation is wasted.
  /// - true (lock-first): the viewer's batch lock is taken first. A batch that
  ///   had to wait for it holds a snapshot older than the holder's commit, so
  ///   it fails right there, before any preparation, and retries. The cursor
  ///   row is still locked only for the write window, so its hold does not
  ///   grow with preparation.
  ///
  /// Both orders use the same repeatable-read transaction and bounded retry.
  static const bool lockFirst = true;

  /// Attempts of one `applyBatch` transaction (within the 5 s deadline). A
  /// same-viewer conflict costs one wait in lock-first order, and every
  /// commit of a competing tab can cost the waiters one attempt.
  static const int applyBatchMaxAttempts = 10;

  ConstellationAnchorRepository(this._db, [this._profiles, this._admission])
    : lockFirstOrder = lockFirst;

  /// Runs `applyBatch` in the given order whatever [lockFirst] says, for the
  /// contention measurement.
  ConstellationAnchorRepository.withLockOrder(
    this._db,
    UserProfileBatchLookup profiles, {
    required this.lockFirstOrder,
  }) : _profiles = profiles,
       _admission = null;

  @FactoryMethod()
  ConstellationAnchorRepository.injected(
    this._db,
    UserProfileBatchLookup profiles,
    ConstellationDbAdmissionPort admission,
  ) : _profiles = profiles,
      _admission = admission,
      lockFirstOrder = lockFirst;

  final TenturaDb _db;
  final UserProfileBatchLookup? _profiles;
  final ConstellationDbAdmissionPort? _admission;

  /// Whether this instance takes the viewer's batch lock before preparing.
  final bool lockFirstOrder;

  @override
  Future<AnchorApplyBatchResult> applyBatch({
    required String viewerId,
    required List<AnchorApplyOp> ops,
    required AnchorApplyParams params,
  }) => _admission == null
      ? _applyBatchInTx(viewerId: viewerId, ops: ops, params: params)
      : _admission.run(
          ConstellationDbWorkKind.apply,
          () => _applyBatchInTx(viewerId: viewerId, ops: ops, params: params),
        );

  Future<AnchorApplyBatchResult> _applyBatchInTx({
    required String viewerId,
    required List<AnchorApplyOp> ops,
    required AnchorApplyParams params,
  }) => _db.withMutatingRepeatableRead(
    viewerId,
    maxAttempts: applyBatchMaxAttempts,
    () async {
      if (lockFirstOrder) await _lockViewerBatch(viewerId);
      final visible = await _prepareBatchVisibility(viewerId, params.context);
      final reader = ConstellationAnchorProjectionReader(
        _db,
        _profiles ?? GetIt.I<UserProfileBatchLookup>(),
      );
      final prepared = await reader.prepare(
        viewerId: viewerId,
        context: params.context,
        filters: params.filters,
        upsertTargets: ops
            .where((op) => op.kind == AnchorOpKind.upsert)
            .map((op) => op.target),
        visiblePeerIds: visible,
      );
      final before = await _lockViewerCursor(viewerId);
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
          authorized: prepared.authorizes(op.target),
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
      await writes.flush(_db);
      final projection = await reader.readPrepared(
        viewerId: viewerId,
        context: params.context,
        filters: params.filters,
        prepared: prepared,
        revision: ConstellationAnchorRevision(revision),
      );
      return AnchorApplyBatchResult(
        beforeRevision: before.revision,
        afterRevision: projection.revision,
        results: results,
        projection: projection,
      );
    },
  );

  /// Freezes the transaction's visibility memo and seeds it from the service
  /// directly, returning the viewer's visible peers without blocks in either
  /// direction (as `block_hides`) — one statement and one MeritRank call.
  /// Unlike the fail-closed memo helper, a service error aborts the batch.
  Future<List<String>> _prepareBatchVisibility(
    String viewerId,
    String context,
  ) async {
    try {
      final row = await _db
          .customSelect(
            r'''
WITH s AS (
  SELECT coalesce(array_agg(v.peer_id ORDER BY v.peer_id), '{}'::text[]) AS ids
  FROM public.person_visible_peers_symmetric($1, $2) v
),
memo AS (
  SELECT
    set_config('tentura_visibility.frozen', 'on', true) AS frozen,
    set_config(
      'tentura_visibility.p' || md5(trim($1::text) || chr(31) || $2::text),
      coalesce((SELECT epoch FROM public.mr_publish_epoch WHERE id = true), 0)::text
        || ':' || public.direct_trust_current_version()::text || ':'
        || s.ids::text,
      true
    ) AS seeded
  FROM s
),
blocked AS (
  SELECT ub.blocked_id AS id FROM public.user_block ub WHERE ub.blocker_id = $1
  UNION
  SELECT ub.blocker_id FROM public.user_block ub WHERE ub.blocked_id = $1
)
SELECT ARRAY(
  SELECT p.peer_id
  FROM unnest(s.ids) AS p(peer_id)
  WHERE NOT EXISTS (SELECT 1 FROM blocked b WHERE b.id = p.peer_id)
  ORDER BY p.peer_id
) AS visible
FROM s, memo
WHERE memo.frozen = 'on' AND memo.seeded IS NOT NULL
''',
            variables: [Variable<String>(viewerId), Variable<String>(context)],
          )
          .getSingle();
      return row.read<List<dynamic>>('visible').cast<String>();
    } on ServerException catch (error) {
      if (isPostgresDeadlockOrSerializationFailure(error)) rethrow;
      // 57014: the transaction's request budget cancelled a stuck MeritRank call.
      if (error.code?.startsWith('08') != true &&
          error.code != '57014' &&
          error.code != 'XX000' &&
          error.code != 'P0001') {
        rethrow;
      }
      throw PostgresSnapshotUnavailableException(error);
    }
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
    required bool authorized,
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
      if (!authorized) {
        return _rejected(op, 'target_unavailable');
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
