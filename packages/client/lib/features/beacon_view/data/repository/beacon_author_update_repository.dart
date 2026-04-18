import 'package:injectable/injectable.dart';

import 'package:tentura/data/model/user_model.dart';
import 'package:tentura/data/service/remote_api_service.dart';
import 'package:tentura/domain/entity/profile.dart';

import '../gql/_g/beacon_update_edit.req.gql.dart';
import '../gql/_g/beacon_update_post.req.gql.dart';

typedef BeaconAuthorUpdatePayload = ({
  String id,
  String beaconId,
  int number,
  String content,
  DateTime createdAt,
  Profile author,
});

@lazySingleton
class BeaconAuthorUpdateRepository {
  BeaconAuthorUpdateRepository(this._remoteApiService);

  final RemoteApiService _remoteApiService;

  static const _label = 'BeaconAuthorUpdateRepository';

  Future<BeaconAuthorUpdatePayload> post({
    required String beaconId,
    required String content,
  }) =>
      _remoteApiService
          .request(
            GBeaconUpdatePostReq(
              (r) => r
                ..vars.beaconId = beaconId
                ..vars.content = content,
            ),
          )
          .firstWhere((e) => e.dataSource == DataSource.Link)
          .then((r) {
            final d = r.dataOrThrow(label: _label).beaconUpdatePost;
            return (
              id: d.id,
              beaconId: d.beaconId,
              number: d.number,
              content: d.content,
              createdAt: d.createdAt,
              author: UserModel(d.author).toEntity(),
            );
          });

  Future<BeaconAuthorUpdatePayload> edit({
    required String id,
    required String content,
  }) =>
      _remoteApiService
          .request(
            GBeaconUpdateEditReq(
              (r) => r
                ..vars.id = id
                ..vars.content = content,
            ),
          )
          .firstWhere((e) => e.dataSource == DataSource.Link)
          .then((r) {
            final d = r.dataOrThrow(label: _label).beaconUpdateEdit;
            return (
              id: d.id,
              beaconId: d.beaconId,
              number: d.number,
              content: d.content,
              createdAt: d.createdAt,
              author: UserModel(d.author).toEntity(),
            );
          });
}
