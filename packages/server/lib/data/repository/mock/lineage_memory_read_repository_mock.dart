import 'package:injectable/injectable.dart';

import 'package:tentura_server/domain/entity/lineage_memory_fact.dart';
import 'package:tentura_server/domain/port/lineage_memory_read_port.dart';

@Injectable(
  as: LineageMemoryReadPort,
  env: [Environment.test],
  order: 1,
)
class LineageMemoryReadRepositoryMock implements LineageMemoryReadPort {
  @override
  Future<List<String>> fetchLineageBeaconIds({required String rootBeaconId}) =>
      Future.value(const []);

  @override
  Future<Set<String>> fetchAuthorBeaconIdsInSet({
    required String userId,
    required Set<String> beaconIds,
  }) => Future.value(const {});

  @override
  Future<List<LineageForwardEdgeFact>> fetchMyLineageForwardEdges({
    required String userId,
    required Set<String> beaconIds,
  }) => Future.value(const []);

  @override
  Future<Set<String>> fetchRecipientsWhoHelped({
    required Set<String> myTouchedBeaconIds,
    required Set<String> recipientIds,
  }) => Future.value(const {});

  @override
  Future<Set<String>> fetchRecipientsWhoRoutedToHelp({
    required String userId,
    required Set<String> myTouchedBeaconIds,
    required Set<String> recipientIds,
  }) => Future.value(const {});

  @override
  Future<List<LineageEvaluationFact>> fetchMyEvaluationsOnLineage({
    required String userId,
    required Set<String> beaconIds,
  }) => Future.value(const []);

  @override
  Future<List<LineagePrivateTagFact>> fetchMyPrivateTags({
    required String userId,
  }) => Future.value(const []);
}
