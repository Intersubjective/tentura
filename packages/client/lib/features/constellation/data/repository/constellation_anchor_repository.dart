import 'package:injectable/injectable.dart';

import 'package:tentura/data/gql/_g/schema.schema.gql.dart';
import 'package:tentura/data/service/remote_api_service.dart';

import 'package:tentura_root/domain/constellation/constellation_anchor.dart';
import '../../domain/entity/constellation_anchor_projection.dart';
import '../../domain/port/constellation_anchor_repository_port.dart';
import '../gql/_g/constellation_anchors_apply.data.gql.dart';
import '../gql/_g/constellation_anchors_apply.req.gql.dart';
import '../gql/_g/constellation_anchors_reset.req.gql.dart';
import '../gql/_g/constellation_layout_snapshot_restore.req.gql.dart';
import '../gql/_g/constellation_layout_snapshot_save.req.gql.dart';
import '../gql/_g/constellation_layout_snapshots.req.gql.dart';
import '../model/constellation_field_mapper.dart';

@LazySingleton(
  as: ConstellationAnchorRepositoryPort,
  env: [Environment.dev, Environment.prod],
  order: 1,
)
final class ConstellationAnchorRepository
    implements ConstellationAnchorRepositoryPort {
  ConstellationAnchorRepository(this._remoteApiService);

  final RemoteApiService _remoteApiService;

  /// Whole-number [double]s serialize as JSON integers on Flutter web; V2
  /// `Float!` variables reject those values at parse time.
  static double _graphQlFloatVariable(double value) =>
      value == value.roundToDouble() ? value + 1e-9 : value;

  @override
  Future<ConstellationAnchorApplyResult> apply({
    required List<ConstellationAnchorApplyOp> ops,
    required ConstellationFieldMembershipFilters params,
  }) => _remoteApiService
      .request(
        GConstellationAnchorsApplyReq((b) {
          b.vars.ops.replace([for (final op in ops) _opToWire(op)]);
        }),
      )
      .firstWhere((response) => response.dataSource == DataSource.Link)
      .then((response) {
        final payload = response
            .dataOrThrow(label: 'ConstellationAnchorsApply')
            .constellationAnchorsApply;
        return mapApplyResult(payload, ops);
      });

  @override
  Future<ConstellationAnchorResetResult> reset({
    required String clientOpId,
    bool saveHistory = false,
  }) => _remoteApiService
      .request(
        GConstellationAnchorsResetReq((b) {
          b.vars
            ..clientOpId = clientOpId
            ..saveHistory = saveHistory;
        }),
      )
      .firstWhere((response) => response.dataSource == DataSource.Link)
      .then((response) {
        final payload = response
            .dataOrThrow(label: 'ConstellationAnchorsReset')
            .constellationAnchorsReset;
        return ConstellationAnchorResetResult(
          beforeRevision: _parseRevision(payload.beforeRevision),
          afterRevision: _parseRevision(payload.afterRevision),
          clearedCount: payload.clearedCount,
          replayed: payload.replayed,
        );
      });

  /// Wire values of the server's `ConstellationLayoutSnapshotReason` enum.
  static const _snapshotReasons = ['manual', 'restore', 'reset', 'rebuild'];

  /// Kind 1 is history (kind 0 is the single favourite).
  @override
  Future<String> saveLayoutSnapshot({
    required String reason,
    required String clientOpId,
  }) => _remoteApiService
      .request(
        GConstellationLayoutSnapshotSaveReq((b) {
          b.vars
            ..kind = 1
            ..reason = _snapshotReasons.indexOf(reason)
            ..clientOpId = clientOpId;
        }),
      )
      .firstWhere((response) => response.dataSource == DataSource.Link)
      .then(
        (response) => response
            .dataOrThrow(label: 'ConstellationLayoutSnapshotSave')
            .constellationLayoutSnapshotSave
            .id,
      );

  /// The server returns the layout it put back; the one it saved of the
  /// layout it replaced is the newest history snapshot, whose id undoes it.
  @override
  Future<String> restoreLayoutSnapshot({
    required String snapshotId,
    required String clientOpId,
  }) async {
    final source = snapshotId == kLatestLayoutSnapshotId
        ? await _newestHistorySnapshotId()
        : snapshotId;
    await _remoteApiService
        .request(
          GConstellationLayoutSnapshotRestoreReq((b) {
            b.vars
              ..snapshotId = source
              ..clientOpId = clientOpId;
          }),
        )
        .firstWhere((response) => response.dataSource == DataSource.Link)
        .then(
          (response) => response.dataOrThrow(
            label: 'ConstellationLayoutSnapshotRestore',
          ),
        );
    return _newestHistorySnapshotId();
  }

  /// Favourite first, then history newest first (kind 1 is history).
  Future<String> _newestHistorySnapshotId() => _remoteApiService
      .request(GConstellationLayoutSnapshotsReq())
      .firstWhere((response) => response.dataSource == DataSource.Link)
      .then((response) {
        final snapshots = response
            .dataOrThrow(label: 'ConstellationLayoutSnapshots')
            .constellationLayoutSnapshots;
        return snapshots.firstWhere((snapshot) => snapshot.kind == 1).id;
      });

  static Gv2_ConstellationAnchorOpInput _opToWire(
    ConstellationAnchorApplyOp op,
  ) => Gv2_ConstellationAnchorOpInput((b) {
    b
      ..clientOpId = op.clientOpId
      ..kind = switch (op.kind) {
        ConstellationAnchorOpKind.upsert =>
          Gv2_ConstellationAnchorOpKind.UPSERT,
        ConstellationAnchorOpKind.delete =>
          Gv2_ConstellationAnchorOpKind.DELETE,
      }
      ..targetKind = targetKindToWire(op.target.kind)
      ..targetId = op.target.id
      ..ifRevision = op.ifRevision?.toDecimalString()
      ..baseRevision = op.baseRevision?.toDecimalString();
    final position = op.position;
    if (position != null) {
      b.position
        ..xUnits = _graphQlFloatVariable(position.xUnits)
        ..yUnits = _graphQlFloatVariable(position.yUnits)
        ..coordinateSpaceVersion = position.coordinateSpaceVersion;
    }
  });

  static ConstellationAnchorApplyResult mapApplyResult(
    GConstellationAnchorsApplyData_constellationAnchorsApply payload,
    List<ConstellationAnchorApplyOp> ops,
  ) {
    final targets = {for (final op in ops) op.clientOpId: op.target};
    return ConstellationAnchorApplyResult(
      beforeRevision: _parseRevision(payload.beforeRevision),
      afterRevision: _parseRevision(payload.afterRevision),
      results: [
        for (final result in payload.results)
          ConstellationAnchorOpResult(
            clientOpId: result.clientOpId,
            status: switch (result.status) {
              Gv2_ConstellationAnchorOpStatus.OK =>
                ConstellationAnchorOpStatus.ok,
              _ => ConstellationAnchorOpStatus.rejected,
            },
            reason: result.reason,
            resultingTargetRevision: result.resultingTargetRevision == null
                ? null
                : _parseRevision(result.resultingTargetRevision!),
            target: targets[result.clientOpId],
            anchor: result.anchor == null
                ? null
                : mapApplyAnchor(result.anchor!),
            replayed: result.replayed,
          ),
      ],
    );
  }

  static ConstellationAnchorRevision _parseRevision(String wire) {
    final parsed = ConstellationAnchorRevision.parseDecimalString(wire);
    if (parsed is! ConstellationAnchorRevisionParsed) {
      throw FormatException('Malformed constellation anchor revision: $wire');
    }
    return parsed.revision;
  }
}
