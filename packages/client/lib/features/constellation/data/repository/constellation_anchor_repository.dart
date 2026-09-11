import 'package:injectable/injectable.dart';

import 'package:tentura/data/service/remote_api_service.dart';

import '../../domain/entity/constellation_anchor.dart';
import '../../domain/port/constellation_anchor_repository_port.dart';
import '../gql/_g/constellation_anchor_delete.data.gql.dart';
import '../gql/_g/constellation_anchor_delete.req.gql.dart';
import '../gql/_g/constellation_anchor_upsert.data.gql.dart';
import '../gql/_g/constellation_anchor_upsert.req.gql.dart';
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

  @override
  Future<ConstellationAnchorUpsertResult> upsert({
    required ConstellationAnchorTarget target,
    required ConstellationAnchorPosition position,
  }) =>
      _remoteApiService
          .request(
            GConstellationAnchorUpsertReq((b) {
              b.vars
                ..targetKind = targetKindToWire(target.kind)
                ..targetId = target.id
                ..xUnits = position.xUnits
                ..yUnits = position.yUnits
                ..coordinateSpaceVersion = position.coordinateSpaceVersion;
            }),
          )
          .firstWhere((response) => response.dataSource == DataSource.Link)
          .then((response) {
            final payload = response
                .dataOrThrow(label: 'ConstellationAnchorUpsert')
                .constellationAnchorUpsert;
            return mapUpsertResult(payload);
          });

  @override
  Future<ConstellationAnchorDeleteResult> delete({
    required ConstellationAnchorTarget target,
  }) =>
      _remoteApiService
          .request(
            GConstellationAnchorDeleteReq((b) {
              b.vars
                ..targetKind = targetKindToWire(target.kind)
                ..targetId = target.id;
            }),
          )
          .firstWhere((response) => response.dataSource == DataSource.Link)
          .then((response) {
            final payload = response
                .dataOrThrow(label: 'ConstellationAnchorDelete')
                .constellationAnchorDelete;
            return mapDeleteResult(payload);
          });

  static ConstellationAnchorUpsertResult mapUpsertResult(
    GConstellationAnchorUpsertData_constellationAnchorUpsert payload,
  ) =>
      ConstellationAnchorUpsertResult(
        anchor: mapWireAnchor(
          targetKind: payload.anchor.targetKind,
          targetId: payload.anchor.targetId,
          xUnits: payload.anchor.xUnits,
          yUnits: payload.anchor.yUnits,
          coordinateSpaceVersion: payload.anchor.coordinateSpaceVersion,
          revision: payload.anchor.revision,
          placedAt: payload.anchor.placedAt,
        ),
        revision: _parseRevision(payload.revision),
      );

  static ConstellationAnchorDeleteResult mapDeleteResult(
    GConstellationAnchorDeleteData_constellationAnchorDelete payload,
  ) {
    final target = ConstellationAnchorTarget.tryFromWire(
      kindWire: payload.targetKind.name,
      targetId: payload.targetId,
    );
    if (target == null) {
      throw FormatException(
        'Malformed constellation anchor target kind: ${payload.targetKind.name}',
      );
    }
    return ConstellationAnchorDeleteResult(
      target: target,
      revision: _parseRevision(payload.revision),
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
