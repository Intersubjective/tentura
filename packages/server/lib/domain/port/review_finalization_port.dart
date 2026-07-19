abstract interface class ReviewFinalizationPort {
  Future<bool> closeAndFinalize(
    String beaconId, {
    required String reason,
    String? actorUserId,
  });
}
