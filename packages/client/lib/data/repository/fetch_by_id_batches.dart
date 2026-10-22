/// The most Request ids one V2 card-context read serves: the server's
/// `inboxRoomContextBatch` and `myWorkLastActivityEventsByBeaconIds` drop the
/// rest (`packages/server/lib/domain/use_case/beacon_room_case.dart`).
const kCardContextBatchMaxIds = 80;

/// W5 (#525) — reads [ids] in batches of at most [batchSize], all at once,
/// and merges the results. Without it, every Request past the 80th on the
/// Requests list got no latest message and no activity time, so it sorted by
/// its entry time alone.
Future<Map<String, V>> fetchByIdBatches<V>(
  Iterable<String> ids,
  Future<Map<String, V>> Function(List<String> batch) fetch, {
  int batchSize = kCardContextBatchMaxIds,
}) async {
  final unique = ids.toSet().toList();
  if (unique.isEmpty) return {};
  final batches = [
    for (var i = 0; i < unique.length; i += batchSize)
      unique.sublist(
        i,
        i + batchSize > unique.length ? unique.length : i + batchSize,
      ),
  ];
  final parts = await Future.wait(batches.map(fetch));
  return {for (final part in parts) ...part};
}
