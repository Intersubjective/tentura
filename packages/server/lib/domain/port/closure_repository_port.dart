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

  /// The most recently created epoch in any status, if any.
  Future<ClosureEpoch?> latestEpoch(String beaconId);

  /// Highest epoch number ever created for [beaconId] (0 if none).
  Future<int> maxEpoch(String beaconId);

  Future<int> cancelledEpochCount(String beaconId);

  /// `closes_at += 7 days`, `extensions_used += 1` on the live epoch.
  Future<void> extendEpoch({required String beaconId, required int epoch});

  /// QA only: `closes_at = now() - 1 second` on the live (evaluating) epoch of
  /// [beaconId], so the next sweep pass finalizes it.
  Future<void> expireLiveEpoch(String beaconId);

  /// QA only: inserts an open, published request owned by [authorId] with one
  /// acknowledged help offer per [helperIds] entry; returns the request id.
  Future<String> seedQaRequestWithHelpers({
    required String authorId,
    required List<String> helperIds,
    required String title,
  });

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

  /// Done: replaces the voter's version-1 rows with a copy of their draft and
  /// upserts the commit row (`committed_at = now()`).
  Future<void> commitDraft({
    required String beaconId,
    required String voterId,
  });

  /// Drops the voter's version-1 rows and upserts the commit row.
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

  /// Ledger row `marked` (kind 3, count 1) for a post-finalize mark; an
  /// existing row with the same source key is un-retracted.
  Future<void> upsertMarkEvidence({
    required String beaconId,
    required int epoch,
    required String markerId,
    required String targetId,
    required DateTime occurredAt,
  });

  Future<void> retractMarkEvidence({
    required String beaconId,
    required int epoch,
    required String markerId,
    required String targetId,
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

  /// Stream 2 (Arch §5.7): records `approval:<beacon>:<helper>` as a
  /// `useful_forward` helper → [senderId], restoring the original row after a
  /// withdrawal and keeping at most one live row per pair per 30 days.
  Future<void> recordApprovalEdge({
    required String beaconId,
    required String helperId,
    required String senderId,
    required String arrivalEdgeId,
  });

  /// Retracts the stream-2 row of [helperId] on [beaconId], if any.
  Future<void> retractApprovalEdge({
    required String beaconId,
    required String helperId,
  });

  /// `status = evaluating AND closes_at <= now()`, oldest first.
  Future<List<ClosureDueEpoch>> dueEpochs({int limit = 50});

  Future<ClosureRoutingSource> routingSource(String beaconId);

  /// Posts [body] to the request room as a system message (kind 3).
  Future<void> postStoryMessage({
    required String beaconId,
    required String body,
  });

  /// Close-acknowledgement capability events `author → helper` over each
  /// helper's offer help type (none when the offer carries no help type).
  Future<void> insertCloseAcknowledgements({
    required String beaconId,
    required String authorId,
    required Set<String> helperIds,
  });
}
