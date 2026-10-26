import 'package:injectable/injectable.dart';

import 'package:tentura/data/service/remote_api_service.dart';

import '../../domain/entity/constellation_tag_magnet.dart';
import '../../domain/port/constellation_tag_magnet_repository_port.dart';
import '../gql/_g/constellation_tag_magnet_remove.req.gql.dart';
import '../gql/_g/constellation_tag_magnet_upsert.req.gql.dart';
import '../gql/_g/constellation_tag_magnets.req.gql.dart';

@LazySingleton(
  as: ConstellationTagMagnetRepositoryPort,
  env: [Environment.dev, Environment.prod],
  order: 1,
)
final class ConstellationTagMagnetRepository
    implements ConstellationTagMagnetRepositoryPort {
  ConstellationTagMagnetRepository(this._remoteApiService);

  final RemoteApiService _remoteApiService;

  /// Whole-number [double]s serialize as JSON integers on Flutter web; V2
  /// `Float!` variables reject those values at parse time.
  static double _graphQlFloatVariable(double value) =>
      value == value.roundToDouble() ? value + 1e-9 : value;

  @override
  Future<List<ConstellationTagMagnet>> list() => _remoteApiService
      .request(GConstellationTagMagnetsReq())
      .firstWhere((response) => response.dataSource == DataSource.Link)
      .then(
        (response) => [
          for (final m
              in response
                  .dataOrThrow(label: 'ConstellationTagMagnets')
                  .constellationTagMagnets)
            ConstellationTagMagnet(
              tagId: m.tagId,
              xUnits: m.xUnits,
              yUnits: m.yUnits,
              revision: m.revision,
            ),
        ],
      );

  @override
  Future<ConstellationTagMagnet> upsert({
    required String tagId,
    required double xUnits,
    required double yUnits,
    required String clientOpId,
  }) => _remoteApiService
      .request(
        GConstellationTagMagnetUpsertReq(
          (b) => b.vars
            ..tagId = tagId
            ..xUnits = _graphQlFloatVariable(xUnits)
            ..yUnits = _graphQlFloatVariable(yUnits)
            ..clientOpId = clientOpId,
        ),
      )
      .firstWhere((response) => response.dataSource == DataSource.Link)
      .then((response) {
        final m = response
            .dataOrThrow(label: 'ConstellationTagMagnetUpsert')
            .constellationTagMagnetUpsert;
        return ConstellationTagMagnet(
          tagId: m.tagId,
          xUnits: m.xUnits,
          yUnits: m.yUnits,
          revision: m.revision,
        );
      });

  @override
  Future<void> remove({required String tagId, required String clientOpId}) =>
      _remoteApiService
          .request(
            GConstellationTagMagnetRemoveReq(
              (b) => b.vars
                ..tagId = tagId
                ..clientOpId = clientOpId,
            ),
          )
          .firstWhere((response) => response.dataSource == DataSource.Link)
          .then(
            (response) =>
                response.dataOrThrow(label: 'ConstellationTagMagnetRemove'),
          );
}
