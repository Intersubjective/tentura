import '../entity/lineage_memory_fact.dart';

abstract class LineageMemoryReadPort {
  Future<List<String>> fetchLineageBeaconIds({required String rootBeaconId});

  Future<Set<String>> fetchAuthorBeaconIdsInSet({
    required String userId,
    required Set<String> beaconIds,
  });

  Future<List<LineageForwardEdgeFact>> fetchMyLineageForwardEdges({
    required String userId,
    required Set<String> beaconIds,
  });

  Future<Set<String>> fetchRecipientsWhoHelped({
    required Set<String> myTouchedBeaconIds,
    required Set<String> recipientIds,
  });

  Future<Set<String>> fetchRecipientsWhoRoutedToHelp({
    required String userId,
    required Set<String> myTouchedBeaconIds,
    required Set<String> recipientIds,
  });

  Future<List<LineageEvaluationFact>> fetchMyEvaluationsOnLineage({
    required String userId,
    required Set<String> beaconIds,
  });

  Future<List<LineagePrivateTagFact>> fetchMyPrivateTags({
    required String userId,
  });
}
