import 'package:tentura_server/domain/port/beacon_access_guard.dart';

class FakeBeaconAccessGuard implements BeaconAccessGuard {
  FakeBeaconAccessGuard({
    this.contentAllowed = true,
    this.involvementAllowed = true,
    this.tombstoneAllowed = false,
  });

  bool contentAllowed;
  bool involvementAllowed;
  bool tombstoneAllowed;

  @override
  Future<bool> canReadContent({
    required String beaconId,
    required String viewerId,
  }) async =>
      contentAllowed;

  @override
  Future<Set<String>> readableContentIds({
    required Iterable<String> beaconIds,
    required String viewerId,
  }) async => contentAllowed ? beaconIds.toSet() : {};

  @override
  Future<Set<String>> readableContentViewerIds({
    required String beaconId,
    required Iterable<String> viewerIds,
  }) async => contentAllowed ? viewerIds.toSet() : {};

  @override
  Future<bool> canReadInvolvement({
    required String beaconId,
    required String viewerId,
  }) async =>
      involvementAllowed;

  @override
  Future<bool> canReadTombstone({
    required String beaconId,
    required String viewerId,
  }) async =>
      tombstoneAllowed;
}
