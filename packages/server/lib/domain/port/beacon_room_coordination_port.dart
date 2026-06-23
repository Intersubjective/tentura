/// Room admission and steward checks used by coordination use cases.
abstract interface class BeaconRoomCoordinationPort {
  Future<bool> isBeaconSteward({
    required String beaconId,
    required String userId,
  });

  Future<void> inviteOfferUserToBeaconRoom({
    required String beaconId,
    required String offerUserId,
    required String authorUserId,
  });

  Future<void> revokeOfferUserBeaconRoomAccess({
    required String beaconId,
    required String offerUserId,
    required String authorUserId,
  });
}
