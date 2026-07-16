abstract interface class AttentionAckPort {
  Future<int> markSeen({
    required String accountId,
    required List<String> ids,
  });

  Future<int> markAllSeen(String accountId);

  Future<int> bridgeRoomWatermark({
    required String accountId,
    required String beaconId,
    required String? threadItemId,
    required DateTime lastSeenAt,
  });
}
