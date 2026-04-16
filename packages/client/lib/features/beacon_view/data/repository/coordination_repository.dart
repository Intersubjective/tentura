import 'package:injectable/injectable.dart';

import 'package:tentura/data/model/image_model.dart';
import 'package:tentura/data/service/remote_api_service.dart';
import 'package:tentura/domain/entity/coordination_status.dart';
import 'package:tentura/domain/entity/profile.dart';
import 'package:tentura_root/domain/enums.dart';

import '../gql/_g/commitments_with_coordination.data.gql.dart';
import '../gql/_g/commitments_with_coordination.req.gql.dart';
import '../gql/_g/set_beacon_coordination_status.req.gql.dart';
import '../gql/_g/set_coordination_response.req.gql.dart';

@Singleton(env: [Environment.dev, Environment.prod])
class CoordinationRepository {
  CoordinationRepository(this._remoteApiService);

  final RemoteApiService _remoteApiService;

  static const _label = 'Coordination';

  Future<
    List<
      ({
        String beaconId,
        String userId,
        Profile user,
        String message,
        String? helpType,
        int status,
        String? uncommitReason,
        DateTime createdAt,
        DateTime updatedAt,
        int? responseType,
        DateTime? responseUpdatedAt,
        String? responseAuthorUserId,
      })
    >
  >
  fetchCommitmentsWithCoordination({
    required String beaconId,
  }) => _remoteApiService
      .request(
        GCommitmentsWithCoordinationReq((r) => r..vars.beaconId = beaconId),
      )
      .firstWhere((e) => e.dataSource == DataSource.Link)
      .then((r) {
        final rows = r.dataOrThrow(label: _label).commitmentsWithCoordination;
        if (rows == null) {
          return [];
        }
        return rows
            .map(
              (e) => (
                beaconId: e.beaconId,
                userId: e.userId,
                user: _profileFromCommitmentUser(e.user),
                message: e.message,
                helpType: e.helpType,
                status: e.status,
                uncommitReason: e.uncommitReason,
                createdAt: DateTime.parse(e.createdAt),
                updatedAt: DateTime.parse(e.updatedAt),
                responseType: e.responseType,
                responseUpdatedAt: e.responseUpdatedAt == null
                    ? null
                    : DateTime.parse(e.responseUpdatedAt!),
                responseAuthorUserId: e.responseAuthorUserId,
              ),
            )
            .toList();
      });

  Future<({BeaconCoordinationStatus status, DateTime? updatedAt})>
  setCoordinationResponse({
    required String beaconId,
    required String commitUserId,
    required int responseType,
  }) => _remoteApiService
      .request(
        GSetCoordinationResponseReq(
          (r) => r
            ..vars.beaconId = beaconId
            ..vars.commitUserId = commitUserId
            ..vars.responseType = responseType,
        ),
      )
      .firstWhere((e) => e.dataSource == DataSource.Link)
      .then((r) {
        final res = r.dataOrThrow(label: _label).setCoordinationResponse;
        return (
          status: BeaconCoordinationStatus.fromSmallint(
            res.coordinationStatus,
          ),
          updatedAt: res.coordinationStatusUpdatedAt == null
              ? null
              : DateTime.tryParse(res.coordinationStatusUpdatedAt!),
        );
      });

  Future<void> setBeaconCoordinationStatus({
    required String beaconId,
    required int coordinationStatus,
  }) => _remoteApiService
      .request(
        GSetBeaconCoordinationStatusReq(
          (r) => r
            ..vars.beaconId = beaconId
            ..vars.coordinationStatus = coordinationStatus,
        ),
      )
      .firstWhere((e) => e.dataSource == DataSource.Link)
      .then((r) => r.dataOrThrow(label: _label));
}

Profile _profileFromCommitmentUser(
  GCommitmentsWithCoordinationData_commitmentsWithCoordination_user user,
) {
  UserPresenceStatus? presenceStatus;
  DateTime? presenceLastSeenAt;
  final p = user.user_presence;
  if (p != null) {
    presenceStatus = _userPresenceStatusFromSmallint(p.status);
    presenceLastSeenAt = p.last_seen_at;
  }
  return Profile(
    id: user.id,
    title: user.title,
    description: user.description,
    myVote: user.my_vote ?? 0,
    image: user.image == null ? null : ImageModel(user.image!).asEntity,
    presenceStatus: presenceStatus,
    presenceLastSeenAt: presenceLastSeenAt,
  );
}

UserPresenceStatus _userPresenceStatusFromSmallint(int value) =>
    switch (value) {
      0 => UserPresenceStatus.unknown,
      1 => UserPresenceStatus.online,
      2 => UserPresenceStatus.offline,
      3 => UserPresenceStatus.inactive,
      _ => UserPresenceStatus.unknown,
    };
