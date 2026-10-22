import 'package:injectable/injectable.dart';

import 'package:tentura/data/service/remote_api_service.dart';

import '../../domain/entity/beacon_lobby.dart';
import '../../domain/port/beacon_lobby_port.dart';
import '../gql/_g/beacon_lobby.req.gql.dart';

/// Request Questions (internally the lobby, U088) over the existing
/// item-thread room API (`RoomMessageList` / `RoomMessageCreate` /
/// `MarkThreadSeen` with the Questions scope id). A denial arrives as
/// `BeaconLobbyUnavailableException` (error link, 1347).
@LazySingleton(as: BeaconLobbyPort, env: [Environment.dev, Environment.prod])
class BeaconLobbyRepository implements BeaconLobbyPort {
  BeaconLobbyRepository(this._remoteApiService);

  final RemoteApiService _remoteApiService;

  @override
  Future<BeaconLobbyAccess> access(String beaconId) async {
    final r = await _remoteApiService
        .request(GBeaconLobbyAccessReq((b) => b..vars.beaconId = beaconId))
        .firstWhere((e) => e.dataSource == DataSource.Link);
    final a = r.dataOrThrow(label: 'BeaconLobbyAccess').BeaconLobbyAccess;
    return BeaconLobbyAccess(
      canRead: a.canRead,
      canPost: a.canPost,
      messageCount: a.messageCount,
      limitReason: BeaconLobbyLimitReason.fromWire(a.readOnlyReason),
    );
  }

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
  Future<List<BeaconLobbyMessage>> messages({
    required String beaconId,
    required String lobbyId,
    DateTime? before,
  }) async {
    final r = await _remoteApiService
        .request(
          GBeaconLobbyMessagesReq(
            (b) => b
              ..vars.beaconId = beaconId
              ..vars.lobbyId = lobbyId
              ..vars.beforeIso = before?.toUtc().toIso8601String(),
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
  Future<void> markSeen({
    required String beaconId,
    required String lobbyId,
  }) async {
    final r = await _remoteApiService
        .request(
          GBeaconLobbyMarkSeenReq(
            (b) => b
              ..vars.beaconId = beaconId
              ..vars.lobbyId = lobbyId,
          ),
        )
        .firstWhere((e) => e.dataSource == DataSource.Link);
    r.dataOrThrow(label: 'BeaconLobbyMarkSeen');
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
