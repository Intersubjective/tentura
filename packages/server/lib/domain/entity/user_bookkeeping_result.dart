class UserBookkeepingResult {
  const UserBookkeepingResult({
    required this.coordinationRepairedCount,
    required this.inboxRowsRepairedCount,
    required this.inboxRowsInsertedCount,
    required this.affectedBeaconIds,
  });

  final int coordinationRepairedCount;
  final int inboxRowsRepairedCount;
  final int inboxRowsInsertedCount;
  final List<String> affectedBeaconIds;

  Map<String, Object?> asJson() => {
    'coordinationRepairedCount': coordinationRepairedCount,
    'inboxRowsRepairedCount': inboxRowsRepairedCount,
    'inboxRowsInsertedCount': inboxRowsInsertedCount,
    'affectedBeaconIds': affectedBeaconIds,
  };
}

class AdmittedOfferCoordinationGap {
  const AdmittedOfferCoordinationGap({
    required this.beaconId,
    required this.offerUserId,
    required this.authorUserId,
  });

  final String beaconId;
  final String offerUserId;
  final String authorUserId;
}

class InboxReconcileResult {
  const InboxReconcileResult({
    required this.repairedCount,
    required this.insertedCount,
    required this.beaconIds,
  });

  final int repairedCount;
  final int insertedCount;
  final List<String> beaconIds;
}
