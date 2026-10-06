import 'package:tentura_root/domain/plan/plan.dart';

import 'package:tentura_server/domain/entity/beacon_plan.dart';

/// Request plan («либретто», #220) storage. Raw SQL over m0223; plan steps are
/// `coordination_item` rows of kind 6 and are never read through Drift.
abstract interface class BeaconPlanRepositoryPort {
  /// Kind, status and author of the Request; `null` when it does not exist.
  Future<PlanRequestInfo?> requestInfo(String beaconId);

  Future<BeaconPlanHead?> getHead(String beaconId);

  /// Creates the head row when missing, then locks it (`FOR UPDATE`).
  Future<BeaconPlanHead> lockHead(String beaconId);

  /// Live steps in plan order.
  Future<List<PlanStepRecord>> liveSteps(String beaconId);

  /// Steps of [beaconId] (live and removed) by id.
  Future<Map<String, PlanStepRecord>> stepsById(
    String beaconId,
    Iterable<String> ids,
  );

  /// Ids among [ids] that already exist on any Request other than
  /// [beaconId] (id collisions).
  Future<Set<String>> foreignStepIds(String beaconId, Iterable<String> ids);

  Future<PlanStepRecord?> getStep(String stepId);

  Future<PlanRevisionRecord?> getRevision(String beaconId, int seq);

  /// Newest first. [beforeSeq] pages backwards; [afterSeq] reads only newer.
  Future<List<PlanRevisionRecord>> listRevisions(
    String beaconId, {
    int? beforeSeq,
    int? afterSeq,
    int limit = 50,
  });

  /// Plan revisions written by [actorId] since [since] (rate limit).
  Future<int> countRevisionsByActorSince(String actorId, DateTime since);

  Future<void> insertRevision({
    required String beaconId,
    required int seq,
    required int kind,
    required PlanSnapshot snapshot,
    required List<Map<String, Object?>> changes,
    int? baseSeq,
    String? actorId,
    int? restoredFromSeq,
    String comment = '',
  });

  /// Materializes [snapshot] as the live steps of [beaconId] at revision
  /// [seq]: inserts new steps, updates changed content, soft-removes steps
  /// missing from [snapshot] and revives removed steps present in it.
  /// Ordering is renumbered 1..n. Tick columns are never touched.
  ///
  /// [ackChangedIds] are steps whose title, time or assignee changed.
  Future<void> writeSteps({
    required String beaconId,
    required int seq,
    required String? actorId,
    required PlanSnapshot snapshot,
    required Set<String> ackChangedIds,
  });

  /// Bumps `change_seq` (and sets `revision_seq` / editor when given); the
  /// head trigger publishes realtime.
  Future<void> touchHead(
    String beaconId, {
    int? revisionSeq,
    String? editedById,
  });

  Future<void> setCopiedFrom({
    required String beaconId,
    required String sourceBeaconId,
  });

  /// Ticks a live step; `false` when it was already ticked.
  Future<bool> setDone({required String stepId, required String actorId});

  /// Unticks a live step; `false` when it was not ticked.
  Future<bool> clearDone(String stepId);

  Future<PlanMemberRecord?> getMember(String beaconId, String userId);

  Future<List<PlanMemberRecord>> listMembers(String beaconId);

  /// `pending_from_seq = COALESCE(pending_from_seq, seq)` for [userIds].
  Future<void> markPending(String beaconId, Set<String> userIds, int seq);

  Future<void> writeAck({
    required String beaconId,
    required String userId,
    required int ackedSeq,
    required int? pendingFromSeq,
  });

  /// Clears a pending «Понятно» without acknowledging (domain act or leave).
  Future<void> clearPending(String beaconId, String userId);

  Future<Map<String, String>> displayNames(Iterable<String> userIds);

  /// Inserts a plan system line (`system_message_kind = 5`) into the main
  /// room and returns its id.
  Future<String> insertPlanLine({
    required String beaconId,
    required String? actorId,
    required int marker,
    required Map<String, Object?> payload,
  });

  /// The newest main-room message (coalescing tail).
  Future<PlanTailMessage?> tailMainRoomMessage(String beaconId);

  Future<void> updateLinePayload(
    String messageId,
    Map<String, Object?> payload,
  );

  /// The newest marker-14 line that lists [stepId] (untick strike-through).
  Future<PlanTailMessage?> latestTickLineFor(String beaconId, String stepId);

  Future<void> insertActivity({
    required String beaconId,
    required int type,
    required String? actorId,
    String? stepId,
    String? targetUserId,
    String? sourceMessageId,
    Map<String, Object?>? diff,
  });

  /// My Work / inbox plan slices (plan §4.9): status, live steps, head and
  /// the pending revisions of [userId] for every Request among [beaconIds],
  /// in **one** statement. Requests that do not exist or are not Requests
  /// are absent.
  Future<Map<String, PlanSliceSource>> sliceSourcesFor(
    String userId,
    Iterable<String> beaconIds,
  );
}

final class PlanTailMessage {
  const PlanTailMessage({
    required this.id,
    required this.createdAt,
    this.marker,
    this.payload,
  });

  final String id;
  final int? marker;
  final DateTime createdAt;
  final Map<String, Object?>? payload;
}
