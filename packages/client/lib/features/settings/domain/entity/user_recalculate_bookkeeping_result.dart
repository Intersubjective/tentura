class UserRecalculateBookkeepingResult {
  const UserRecalculateBookkeepingResult({
    required this.coordinationRepairedCount,
    required this.inboxRowsRepairedCount,
    required this.inboxRowsInsertedCount,
    required this.affectedBeaconIds,
  });

  final int coordinationRepairedCount;
  final int inboxRowsRepairedCount;
  final int inboxRowsInsertedCount;
  final List<String> affectedBeaconIds;

  int get inboxTouchedCount => inboxRowsRepairedCount + inboxRowsInsertedCount;
}
