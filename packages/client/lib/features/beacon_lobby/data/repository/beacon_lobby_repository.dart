import 'package:injectable/injectable.dart';

import 'package:tentura/data/service/remote_api_service.dart';

import '../../domain/entity/beacon_lobby.dart';
import '../../domain/port/beacon_lobby_port.dart';
import '../gql/_g/beacon_lobby.req.gql.dart';

/// U088 — the lobby over the existing item-thread room API
/// (`RoomMessageList` / `RoomMessageCreate` with `threadItemId` = lobby id).
/// A denial arrives as `BeaconLobbyUnavailableException` (error link, 1347).
@LazySingleton(as: BeaconLobbyPort, env: [Environment.dev, Environment.prod])
class BeaconLobbyRepository implements BeaconLobbyPort {
  BeaconLobbyRepository(this._remoteApiService);

  final RemoteApiService _remoteApiService;

  @override
  Future<BeaconLobbyInfo> open(String beaconId) async {
    final r = await _remoteApiService
        .request(GBeaconLobbyReq((b) => b..vars.beaconId = beaconId))
        .firstWhere((e) => e.dataSource == DataSource.Link);
    final l = r.dataOrThrow(label: 'BeaconLobby').BeaconLobby;
    return BeaconLobbyInfo(
      beaconId: l.beaconId,
      lobbyId: l.lobbyId,
      isAuthor: l.isAuthor,
      canPost: l.canPost,
      bannedUserIds: l.bannedUserIds?.toList() ?? const [],
    );
  }

  @override
  Future<List<BeaconLobbyMessage>> messages({
    required String beaconId,
    required String lobbyId,
  }) async {
    final r = await _remoteApiService
        .request(
          GBeaconLobbyMessagesReq(
            (b) => b
              ..vars.beaconId = beaconId
              ..vars.lobbyId = lobbyId,
          ),
        )
        .firstWhere((e) => e.dataSource == DataSource.Link);
    final rows =
        r.dataOrThrow(label: 'BeaconLobbyMessages').RoomMessageList?.toList() ??
        const [];
    final out = [
      for (final m in rows)
        BeaconLobbyMessage(
          id: m.id,
          authorId: m.authorId,
          authorName: m.authorTitle,
          body: m.body,
          createdAt: DateTime.tryParse(m.createdAt)?.toLocal(),
        ),
    ];
    return out..sort((a, b) {
      final at = a.createdAt;
      final bt = b.createdAt;
      if (at == null || bt == null) return 0;
      return at.compareTo(bt);
    });
  }

  @override
  Future<void> post({
    required String beaconId,
    required String lobbyId,
    required String body,
  }) async {
    final r = await _remoteApiService
        .request(
          GBeaconLobbyPostReq(
            (b) => b
              ..vars.beaconId = beaconId
              ..vars.lobbyId = lobbyId
              ..vars.body = body,
          ),
        )
        .firstWhere((e) => e.dataSource == DataSource.Link);
    r.dataOrThrow(label: 'BeaconLobbyPost');
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
        .firstWhere((e) => e.dataSource == DataSource.Link);
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
        .firstWhere((e) => e.dataSource == DataSource.Link);
    r.dataOrThrow(label: 'BeaconLobbyUnban');
  }
}
