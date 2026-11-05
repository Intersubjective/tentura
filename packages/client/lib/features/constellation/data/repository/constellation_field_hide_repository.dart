import 'package:injectable/injectable.dart';

import 'package:tentura/data/service/remote_api_service.dart';

import '../../domain/port/constellation_field_hide_port.dart';
import '../gql/_g/field_hide.req.gql.dart';
import '../gql/_g/field_hidden_items.req.gql.dart';
import '../../domain/entity/constellation_field_hidden_item.dart';
import '../../domain/entity/constellation_field_target_kind.dart';

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

  @override
  Future<List<ConstellationFieldHiddenItem>> fetchHiddenItems({
    String? cursor,
  }) async {
    final rows = await _remoteApiService
        .request(
          GFieldHiddenItemsReq(
            (b) => b.vars..cursor = cursor,
          ),
        )
        .firstWhere((response) => response.dataSource == DataSource.Link)
        .then(
          (response) =>
              response.dataOrThrow(label: 'FieldHiddenItems').fieldHiddenItems,
        );
    final list = rows?.toList() ?? const [];
    return [
      for (final row in list)
          ConstellationFieldHiddenItem(
            targetKind: ConstellationFieldTargetKind.fromWireValue(
              row.targetKind,
            ),
            targetId: row.targetId,
            title: row.title,
            authorId: row.authorId,
            hiddenAt: DateTime.parse(row.hiddenAt).toUtc(),
          ),
    ];
  }
}
