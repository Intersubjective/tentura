import 'package:injectable/injectable.dart';

import 'package:tentura/data/service/remote_api_service.dart';

import '../../domain/entity/beacon_lobby.dart';
import '../../domain/port/beacon_lobby_port.dart';
import '../gql/_g/beacon_lobby.req.gql.dart';

/// Request Questions (internally the lobby, U088): the viewer's standing and
/// the author's removals. Its messages go through the room API with the
/// Questions scope id, like any thread's (#726). A denial arrives as
/// `BeaconLobbyUnavailableException` (error link, 1347).
@LazySingleton(as: BeaconLobbyPort, env: [Environment.dev, Environment.prod])
class BeaconLobbyRepository implements BeaconLobbyPort {
  BeaconLobbyRepository(this._remoteApiService);

  final RemoteApiService _remoteApiService;

  @override
  Future<BeaconLobbyAccess> access(String beaconId) async {
    final r = await _remoteApiService
        .request(GBeaconLobbyAccessReq((b) => b..vars.beaconId = beaconId))
        .firstLinkResponse(label: 'BeaconLobby');
    final a = r.dataOrThrow(label: 'BeaconLobbyAccess').BeaconLobbyAccess;
    return BeaconLobbyAccess(
      canRead: a.canRead,
      canPost: a.canPost,
      messageCount: a.messageCount,
      limitReason: BeaconLobbyLimitReason.fromWire(a.readOnlyReason),
      isHelper: a.isHelper,
      takesOffers: a.takesOffers,
    );
  }

  @override
  Future<BeaconLobbyInfo> open(String beaconId) async {
    final r = await _remoteApiService
        .request(GBeaconLobbyReq((b) => b..vars.beaconId = beaconId))
        .firstLinkResponse(label: 'BeaconLobby');
    final l = r.dataOrThrow(label: 'BeaconLobby').BeaconLobby;
    return BeaconLobbyInfo(
      beaconId: l.beaconId,
      lobbyId: l.lobbyId,
      isAuthor: l.isAuthor,
      isHelper: l.isHelper,
      takesOffers: l.takesOffers,
      canPost: l.canPost,
      authorId: l.authorId,
      readOnlyReason: BeaconLobbyLimitReason.fromWire(l.readOnlyReason),
      banned: [
        ...?l.banned?.map(
          (b) => BeaconLobbyBannedPerson(userId: b.userId, name: b.title),
        ),
      ],
    );
  }

  @override
  Future<void> ban({required String beaconId, required String userId}) async {
    final r = await _remoteApiService
        .request(
          GBeaconLobbyBanReq(
            (b) => b
              ..vars.beaconId = beaconId
              ..vars.userId = userId,
          ),
        )
        .firstLinkResponse(label: 'BeaconLobby');
    r.dataOrThrow(label: 'BeaconLobbyBan');
  }

  @override
  Future<void> unban({required String beaconId, required String userId}) async {
    final r = await _remoteApiService
        .request(
          GBeaconLobbyUnbanReq(
            (b) => b
              ..vars.beaconId = beaconId
              ..vars.userId = userId,
          ),
        )
        .firstLinkResponse(label: 'BeaconLobby');
    r.dataOrThrow(label: 'BeaconLobbyUnban');
  }
}
