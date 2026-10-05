import 'package:tentura_server/domain/attention/attention_models.dart';

/// Request plan («либретто», #220): the attention-side storage the plan
/// reconciler and sweep need (plan §4.5, §4.6). Joins the caller's ambient
/// transaction.
abstract interface class PlanAttentionRepositoryPort {
  /// Live (unsettled) plan obligations on [beaconId]: `planStepDue`,
  /// `planStepTurn` and `planChangePending` receipts.
  Future<List<PlanObligationReceipt>> liveObligations(String beaconId);

  /// Settles the receipts [receiptIds] as `resolved` or `superseded`.
  Future<int> settle(
    Iterable<String> receiptIds, {
    required AttentionSettlementKind kind,
    String? settledByUserId,
  });

  /// Whether an occurrence with [sourceEventKey] was already recorded.
  Future<bool> occurrenceExists(String sourceEventKey);

  /// Claims one sweep phase by its key (`PlanSweepPhase.key`); `false` when
  /// another pass already claimed it.
  Future<bool> claimSweepMark({
    required String key,
    required String beaconId,
  });

  /// Live, unticked plan steps of open-family Requests that may owe a sweep
  /// phase at [now]: a start within the reminder lead or past, or an end in
  /// the past, and the step's final phase not yet claimed.
  Future<List<PlanSweepStep>> sweepCandidates({
    required DateTime now,
    int limit = 500,
  });
}

/// One live plan obligation receipt.
final class PlanObligationReceipt {
  const PlanObligationReceipt({
    required this.receiptId,
    required this.accountId,
    required this.eventType,
    this.stepId,
  });

  final String receiptId;
  final String accountId;
  final AttentionEventType eventType;

  /// `coordination_item_id` of a step obligation; null for a pending change.
  final String? stepId;
}

/// A sweep candidate step, read without locks.
final class PlanSweepStep {
  const PlanSweepStep({
    required this.stepId,
    required this.beaconId,
    this.assigneeId,
    this.startAt,
    this.endAt,
    this.timedAt,
  });

  final String stepId;
  final String beaconId;
  final String? assigneeId;
  final DateTime? startAt;
  final DateTime? endAt;

  /// When the step's time or assignee last changed (the revision at its
  /// `ack_seq`); a reminder is skipped for a step set inside the lead.
  final DateTime? timedAt;
}
