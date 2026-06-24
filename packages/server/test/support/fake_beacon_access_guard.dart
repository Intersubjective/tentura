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
