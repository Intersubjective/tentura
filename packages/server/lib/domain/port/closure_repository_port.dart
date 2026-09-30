import 'package:tentura_server/domain/closure/closure_entities.dart';
import 'package:tentura_server/domain/closure/closure_outcome.dart';
import 'package:tentura_server/domain/closure/membership_reducer.dart';
import 'package:tentura_server/domain/entity/forward_edge_entity.dart';

/// A11: thin SQL persistence for episode closure (Arch §5.4).
///
/// No business rules here — A12 `ClosureCase` orchestrates. Every method is a
/// single SQL statement and joins the caller's ambient transaction
/// (`MutatingUnitOfWorkPort.run`).
abstract class ClosureRepositoryPort {
  /// Per-request advisory lock (xact-scoped; pool-safe).
  Future<void> lockRequest(String beaconId);

  /// The live (evaluating) epoch, if any. Finalized epochs stay on the
  /// `beacon_closure_one_live` index (no reopen after finalize, P10) but are
  /// no longer live.
  Future<ClosureEpoch?> liveEpoch(String beaconId);

  /// Highest epoch number ever created for [beaconId] (0 if none).
  Future<int> maxEpoch(String beaconId);

  Future<int> cancelledEpochCount(String beaconId);

  /// `closes_at += 7 days`, `extensions_used += 1` on the live epoch.
  Future<void> extendEpoch({required String beaconId, required int epoch});

  Future<ClosureEpoch> createEpoch({
    required String beaconId,
    required int epoch,
    required DateTime openedAt,
    required DateTime closesAt,
    int extensionsUsed,
  });

  Future<void> setEpochStatus({
    required String beaconId,
    required int epoch,
    required ClosureEpochStatus status,
    DateTime? finalizedAt,
    int? finalizeReason,
    int? settlementVersion,
    Map<String, Object?>? settlementParams,
  });

  Future<void> insertMembers({
    required String beaconId,
    required int epoch,
    required List<ClosureMemberInsert> members,
  });

  Future<void> setDeparture({
    required String beaconId,
    required int epoch,
    required String userId,
    Departure? departure,
  });

  Future<List<ClosureMemberRow>> members({
    required String beaconId,
    required int epoch,
  });

  Future<List<ClosureOutcomeRow>> outcomes(String beaconId);

  Future<void> saveOutcome({
    required String beaconId,
    required String helperId,
    ClosureOutcome? outcome,
  });

  Future<Map<String, int>> split(String beaconId);

  Future<void> replaceSplit(String beaconId, Map<String, int>? helperPct);

  Future<List<ClosureSupportRow>> supports({
    required String beaconId,
    required ClosureSupportVersion version,
  });

  Future<void> toggleSupport({
    required String beaconId,
    required String voterId,
    required String targetId,
    required bool on,
  });

  Future<void> commitSupport({
    required String beaconId,
    required String voterId,
  });

  Future<void> skip({
    required String beaconId,
    required String voterId,
  });

  Future<void> clearCommitted(String beaconId);

  Future<List<ClosureCommitRow>> commits(String beaconId);

  Future<void> setMark({
    required String beaconId,
    required String markerId,
    required String targetId,
    required bool on,
  });

  Future<List<ClosureMarkRow>> marks(String beaconId);

  Future<void> saveStory({
    required String beaconId,
    required String body,
  });

  Future<String?> story(String beaconId);

  Future<void> insertResults({
    required String beaconId,
    required int epoch,
    required List<ClosureResultInsert> rows,
  });

  /// Latest-epoch result row for one member (PK is `(beacon_id, epoch,
  /// user_id)`; the port exposes the most recent one).
  Future<ClosureResultRow?> resultFor({
    required String beaconId,
    required String userId,
  });

  /// The forward edge through which [helperId] arrived on [beaconId] as of
  /// [offerCreatedAt] (Arch §5.6): latest edge created strictly before the
  /// offer and not cancelled at or before it; ties broken by id DESC.
  Future<ForwardEdgeEntity?> selectArrivalEdge({
    required String beaconId,
    required String helperId,
    required DateTime offerCreatedAt,
  });
}
