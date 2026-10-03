import 'package:injectable/injectable.dart';

import 'package:tentura/data/repository/remote_repository.dart';

import '../gql/_g/beacon_mute_clear.req.gql.dart';
import '../gql/_g/beacon_mute_set.req.gql.dart';

/// The viewer's own mute of a Post's notifications.
@Singleton(env: [Environment.dev, Environment.prod])
class PostMuteRepository extends RemoteRepository {
  PostMuteRepository({
    required super.remoteApiService,
    required super.log,
  });

  /// Mutes [beaconId] until [mutedUntil]; `null` mutes it for good.
  Future<void> setMute({
    required String beaconId,
    DateTime? mutedUntil,
  }) async {
    await requestDataOnlineOrThrow(
      GBeaconMuteSetReq(
        (b) => b.vars
          ..beaconId = beaconId
          ..mutedUntil = mutedUntil?.toUtc().toIso8601String(),
      ),
      label: _label,
    );
  }

  Future<void> clearMute(String beaconId) async {
    await requestDataOnlineOrThrow(
      GBeaconMuteClearReq((b) => b.vars.beaconId = beaconId),
      label: _label,
    );
  }

  static const _label = 'PostMute';
}
