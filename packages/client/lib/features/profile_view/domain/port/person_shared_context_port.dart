typedef PersonSharedContext = ({String beaconId, String title});

abstract interface class PersonSharedContextPort {
  /// Active Requests the viewer shares with [userId] (co-participant bond).
  Future<List<PersonSharedContext>> fetchSharedContexts(String userId);
}
