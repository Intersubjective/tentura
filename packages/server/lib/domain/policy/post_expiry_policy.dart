import 'package:tentura_root/domain/entity/beacon_post_lifetime.dart';
import 'package:tentura_server/domain/entity/beacon_entity.dart';
import 'package:tentura_server/domain/entity/beacon_kind.dart';
import 'package:tentura_server/domain/port/beacon_repository_port.dart';

/// Checks a Post's lifetime after the caller has locked its mutable state.
Future<bool> isExpiredPost(
  BeaconRepositoryPort repository,
  BeaconEntity beacon,
) async {
  if (beacon.kind != BeaconKind.post) return false;
  return BeaconPostLifetime.isExpired(
    kind: beacon.kind.value,
    status: beacon.status,
    expiresAt: await repository.postExpiresAt(beacon.id),
    now: DateTime.timestamp(),
  );
}
