import 'package:injectable/injectable.dart';

import 'package:tentura/data/service/remote_api_service.dart';

import '../gql/_g/beacon_room_message_need_info.req.gql.dart';
import '../gql/_g/room_message_mark_done.req.gql.dart';

@lazySingleton
class BeaconBlockerRepository {
  BeaconBlockerRepository(this._remote);

  static const _label = 'BeaconBlocker';

  final RemoteApiService _remote;

  Future<bool> needInfo({
    required String beaconId,
    required String messageId,
    required String targetUserId,
    required String requestText,
  }) =>
      _remote
          .request(
            GBeaconRoomMessageNeedInfoReq(
              (b) => b.vars
                ..beaconId = beaconId
                ..messageId = messageId
                ..targetUserId = targetUserId
                ..requestText = requestText,
            ),
          )
          .firstWhere((e) => e.dataSource == DataSource.Link)
          .then(
            (r) => r.dataOrThrow(label: _label).BeaconRoomMessageNeedInfo,
          );

  Future<bool> markDone({
    required String beaconId,
    required String messageId,
    required bool resolveBlocker,
  }) =>
      _remote
          .request(
            GRoomMessageMarkDoneReq(
              (b) => b.vars
                ..beaconId = beaconId
                ..messageId = messageId
                ..resolveBlocker = resolveBlocker,
            ),
          )
          .firstWhere((e) => e.dataSource == DataSource.Link)
          .then((r) => r.dataOrThrow(label: _label).RoomMessageMarkDone);
}
