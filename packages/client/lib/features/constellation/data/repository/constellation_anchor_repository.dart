import 'package:injectable/injectable.dart';

import 'package:tentura/data/gql/_g/schema.schema.gql.dart';
import 'package:tentura/data/service/remote_api_service.dart';

import 'package:tentura_root/domain/constellation/constellation_anchor.dart';
import '../../domain/entity/constellation_anchor_projection.dart';
import '../../domain/port/constellation_anchor_repository_port.dart';
import '../gql/_g/constellation_anchors_apply.data.gql.dart';
import '../gql/_g/constellation_anchors_apply.req.gql.dart';
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
          b.vars
            ..ops.replace([for (final op in ops) _opToWire(op)])
            ..showClosed = params.showClosed
            ..participatedOnly = params.participatedOnly;
        }),
      )
      .firstWhere((response) => response.dataSource == DataSource.Link)
      .then((response) {
        final payload = response
            .dataOrThrow(label: 'ConstellationAnchorsApply')
            .constellationAnchorsApply;
        return mapApplyResult(payload);
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
      ..ifRevision = op.ifRevision?.toDecimalString();
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
  ) => ConstellationAnchorApplyResult(
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
        ),
    ],
    anchorProjection: mapApplyAnchorProjection(payload.anchorProjection),
  );

  static ConstellationAnchorRevision _parseRevision(String wire) {
    final parsed = ConstellationAnchorRevision.parseDecimalString(wire);
    if (parsed is! ConstellationAnchorRevisionParsed) {
      throw FormatException('Malformed constellation anchor revision: $wire');
    }
    return parsed.revision;
  }
}
