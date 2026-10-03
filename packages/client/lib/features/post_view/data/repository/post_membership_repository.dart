import 'package:injectable/injectable.dart';

import 'package:tentura/data/repository/remote_repository.dart';

import '../gql/_g/post_leave.req.gql.dart';
import '../gql/_g/post_return.req.gql.dart';

/// A recipient's leaving a Post's conversation and coming back to it.
@Singleton(env: [Environment.dev, Environment.prod])
class PostMembershipRepository extends RemoteRepository {
  PostMembershipRepository({
    required super.remoteApiService,
    required super.log,
  });

  Future<void> postLeave(String beaconId) async {
    await requestDataOnlineOrThrow(
      GPostLeaveReq((b) => b.vars.id = beaconId),
      label: _label,
    );
  }

  Future<void> postReturn(String beaconId) async {
    await requestDataOnlineOrThrow(
      GPostReturnReq((b) => b.vars.id = beaconId),
      label: _label,
    );
  }

  static const _label = 'PostMembership';
}
