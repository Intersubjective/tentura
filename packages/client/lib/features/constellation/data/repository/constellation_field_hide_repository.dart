import 'package:injectable/injectable.dart';

import 'package:tentura/data/service/remote_api_service.dart';

import '../../domain/port/constellation_field_hide_port.dart';
import '../gql/_g/field_hide.req.gql.dart';

@LazySingleton(
  as: ConstellationFieldHidePort,
  env: [Environment.dev, Environment.prod],
  order: 1,
)
final class ConstellationFieldHideRepository implements ConstellationFieldHidePort {
  ConstellationFieldHideRepository(this._remoteApiService);

  final RemoteApiService _remoteApiService;

  @override
  Future<void> hide({
    required int targetKind,
    required String targetId,
  }) async {
    await _remoteApiService
        .request(
          GFieldHideReq(
            (b) => b.vars
              ..targetKind = targetKind
              ..targetId = targetId,
          ),
        )
        .firstWhere((response) => response.dataSource == DataSource.Link)
        .then(
          (response) => response.dataOrThrow(label: 'FieldHide').fieldHide,
        );
  }

  @override
  Future<void> unhide({
    required int targetKind,
    required String targetId,
  }) async {
    await _remoteApiService
        .request(
          GFieldUnhideReq(
            (b) => b.vars
              ..targetKind = targetKind
              ..targetId = targetId,
          ),
        )
        .firstWhere((response) => response.dataSource == DataSource.Link)
        .then(
          (response) => response.dataOrThrow(label: 'FieldUnhide').fieldUnhide,
        );
  }
}
