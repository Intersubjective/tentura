import 'package:injectable/injectable.dart';

import 'package:tentura/data/repository/remote_repository.dart';

import '../../domain/port/post_lifecycle_port.dart';
import '../gql/_g/post_close.req.gql.dart';
import '../gql/_g/post_leave.req.gql.dart';
import '../gql/_g/post_return.req.gql.dart';
import '../gql/_g/post_shorten.req.gql.dart';

/// Post conversation membership and author lifetime operations.
@Singleton(env: [Environment.dev, Environment.prod])
class PostMembershipRepository extends RemoteRepository
    implements PostLifecyclePort {
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

  @override
  Future<void> postShorten(
    String beaconId, {
    required DateTime expiresAt,
  }) async {
    await requestDataOnlineOrThrow(
      GPostShortenReq(
        (b) => b.vars
          ..id = beaconId
          ..expiresAt = expiresAt.toUtc().toIso8601String(),
      ),
      label: _label,
    );
  }

  @override
  Future<void> postClose(String beaconId) async {
    await requestDataOnlineOrThrow(
      GPostCloseReq((b) => b.vars.id = beaconId),
      label: _label,
    );
  }

  static const _label = 'PostMembership';
}
