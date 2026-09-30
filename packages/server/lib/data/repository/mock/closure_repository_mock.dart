import 'package:injectable/injectable.dart';

import 'package:tentura_server/domain/closure/closure_entities.dart';
import 'package:tentura_server/domain/closure/closure_outcome.dart';
import 'package:tentura_server/domain/closure/membership_reducer.dart';
import 'package:tentura_server/domain/entity/forward_edge_entity.dart';
import 'package:tentura_server/domain/port/closure_repository_port.dart';

@LazySingleton(
  as: ClosureRepositoryPort,
  env: [Environment.test],
  order: 1,
)
class ClosureRepositoryMock implements ClosureRepositoryPort {
  const ClosureRepositoryMock();

  @override
  Future<void> lockRequest(String beaconId) async {}

  @override
  Future<ClosureEpoch?> liveEpoch(String beaconId) async => null;

  @override
  Future<int> maxEpoch(String beaconId) async => 0;

  @override
  Future<int> cancelledEpochCount(String beaconId) async => 0;

  @override
  Future<void> extendEpoch({
    required String beaconId,
    required int epoch,
  }) async {}

  @override
  Future<ClosureEpoch> createEpoch({
    required String beaconId,
    required int epoch,
    required DateTime openedAt,
    required DateTime closesAt,
    int extensionsUsed = 0,
  }) async => ClosureEpoch(
    beaconId: beaconId,
    epoch: epoch,
    status: ClosureEpochStatus.evaluating,
    openedAt: openedAt,
    closesAt: closesAt,
    extensionsUsed: extensionsUsed,
  );

  @override
  Future<void> setEpochStatus({
    required String beaconId,
    required int epoch,
    required ClosureEpochStatus status,
    DateTime? finalizedAt,
    int? finalizeReason,
    int? settlementVersion,
    Map<String, Object?>? settlementParams,
  }) async {}

  @override
  Future<void> insertMembers({
    required String beaconId,
    required int epoch,
    required List<ClosureMemberInsert> members,
  }) async {}

  @override
  Future<void> setDeparture({
    required String beaconId,
    required int epoch,
    required String userId,
    Departure? departure,
  }) async {}

  @override
  Future<List<ClosureMemberRow>> members({
    required String beaconId,
    required int epoch,
  }) async =>
      const [];

  @override
  Future<List<ClosureOutcomeRow>> outcomes(String beaconId) async => const [];

  @override
  Future<void> saveOutcome({
    required String beaconId,
    required String helperId,
    ClosureOutcome? outcome,
  }) async {}

  @override
  Future<Map<String, int>> split(String beaconId) async => const {};

  @override
  Future<void> replaceSplit(
    String beaconId,
    Map<String, int>? helperPct,
  ) async {}

  @override
  Future<List<ClosureSupportRow>> supports({
    required String beaconId,
    required ClosureSupportVersion version,
  }) async =>
      const [];

  @override
  Future<void> toggleSupport({
    required String beaconId,
    required String voterId,
    required String targetId,
    required bool on,
  }) async {}

  @override
  Future<void> commitSupport({
    required String beaconId,
    required String voterId,
  }) async {}

  @override
  Future<void> skip({
    required String beaconId,
    required String voterId,
  }) async {}

  @override
  Future<void> clearCommitted(String beaconId) async {}

  @override
  Future<List<ClosureCommitRow>> commits(String beaconId) async => const [];

  @override
  Future<void> setMark({
    required String beaconId,
    required String markerId,
    required String targetId,
    required bool on,
  }) async {}

  @override
  Future<List<ClosureMarkRow>> marks(String beaconId) async => const [];

  @override
  Future<void> saveStory({
    required String beaconId,
    required String body,
  }) async {}

  @override
  Future<String?> story(String beaconId) async => null;

  @override
  Future<void> insertResults({
    required String beaconId,
    required int epoch,
    required List<ClosureResultInsert> rows,
  }) async {}

  @override
  Future<ClosureResultRow?> resultFor({
    required String beaconId,
    required String userId,
  }) async =>
      null;

  @override
  Future<ForwardEdgeEntity?> selectArrivalEdge({
    required String beaconId,
    required String helperId,
    required DateTime offerCreatedAt,
  }) async =>
      null;
}
