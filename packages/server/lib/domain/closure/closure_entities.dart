import 'package:tentura_server/domain/closure/closure_band.dart';
import 'package:tentura_server/domain/closure/closure_outcome.dart';
import 'package:tentura_server/domain/closure/membership_reducer.dart';
import 'package:tentura_server/domain/trust/forward/forward_provenance.dart';

/// A11 closure persistence entities (Arch §5.4) — plain immutable row
/// carriers for the raw-SQL `beacon_closure*` tables (no Drift classes).

enum ClosureEpochStatus {
  evaluating(0),
  finalized(1),
  cancelled(2);

  const ClosureEpochStatus(this.dbValue);

  final int dbValue;

  static ClosureEpochStatus? tryFromInt(int? v) => switch (v) {
    0 => evaluating,
    1 => finalized,
    2 => cancelled,
    _ => null,
  };
}

enum ClosureSupportVersion {
  draft(0),
  committed(1);

  const ClosureSupportVersion(this.dbValue);

  final int dbValue;

  static ClosureSupportVersion? tryFromInt(int? v) => switch (v) {
    0 => draft,
    1 => committed,
    _ => null,
  };
}

enum ClosureResultDraftFlag {
  none(0),
  notCounted(1),
  lastEditNotCounted(2);

  const ClosureResultDraftFlag(this.dbValue);

  final int dbValue;

  static ClosureResultDraftFlag? tryFromInt(int? v) => switch (v) {
    0 => none,
    1 => notCounted,
    2 => lastEditNotCounted,
    _ => null,
  };
}

final class ClosureEpoch {
  const ClosureEpoch({
    required this.beaconId,
    required this.epoch,
    required this.status,
    required this.openedAt,
    required this.closesAt,
    required this.extensionsUsed,
    this.finalizedAt,
    this.finalizeReason,
    this.settlementVersion,
    this.settlementParams,
  });

  final String beaconId;
  final int epoch;
  final ClosureEpochStatus status;
  final DateTime openedAt;
  final DateTime closesAt;
  final int extensionsUsed;
  final DateTime? finalizedAt;
  final int? finalizeReason;
  final int? settlementVersion;
  final Map<String, Object?>? settlementParams;
}

final class ClosureMemberInsert {
  const ClosureMemberInsert({
    required this.userId,
    required this.activeAtOpen,
    this.arrivalEdgeId,
    this.departure,
  });

  final String userId;
  final bool activeAtOpen;
  final String? arrivalEdgeId;
  final Departure? departure;
}

final class ClosureMemberRow {
  const ClosureMemberRow({
    required this.userId,
    required this.activeAtOpen,
    this.arrivalEdgeId,
    this.departure,
  });

  final String userId;
  final bool activeAtOpen;
  final String? arrivalEdgeId;
  final Departure? departure;
}

final class ClosureOutcomeRow {
  const ClosureOutcomeRow({
    required this.helperId,
    required this.updatedAt,
    this.outcome,
  });

  final String helperId;
  final ClosureOutcome? outcome;
  final DateTime updatedAt;
}

final class ClosureSupportRow {
  const ClosureSupportRow({
    required this.voterId,
    required this.targetId,
    required this.version,
    required this.pressedAt,
  });

  final String voterId;
  final String targetId;
  final ClosureSupportVersion version;
  final DateTime pressedAt;
}

final class ClosureCommitRow {
  const ClosureCommitRow({
    required this.voterId,
    required this.committedAt,
  });

  final String voterId;
  final DateTime committedAt;
}

final class ClosureMarkRow {
  const ClosureMarkRow({
    required this.markerId,
    required this.targetId,
    required this.updatedAt,
  });

  final String markerId;
  final String targetId;
  final DateTime updatedAt;
}

final class ClosureResultInsert {
  const ClosureResultInsert({
    required this.userId,
    required this.outcome,
    required this.band,
    required this.draftFlag,
    required this.helped,
  });

  final String userId;
  final ClosureOutcome outcome;
  final ClosureBand band;
  final ClosureResultDraftFlag draftFlag;
  final double helped;
}

final class ClosureResultRow {
  const ClosureResultRow({
    required this.beaconId,
    required this.epoch,
    required this.userId,
    required this.outcome,
    required this.band,
    required this.draftFlag,
    required this.helped,
  });

  final String beaconId;
  final int epoch;
  final String userId;
  final ClosureOutcome outcome;
  final ClosureBand band;
  final ClosureResultDraftFlag draftFlag;
  final double helped;
}

/// An evaluating epoch whose window has elapsed (finalize sweep candidate).
final class ClosureDueEpoch {
  const ClosureDueEpoch({required this.beaconId, required this.epoch});

  final String beaconId;
  final int epoch;
}

/// Raw forward-routing inputs of one request (Arch §5.8).
final class ClosureRoutingSource {
  const ClosureRoutingSource({
    required this.edges,
    required this.attributionByBatch,
    required this.offerAt,
  });

  final List<ForwardProvenanceEdge> edges;
  final Map<String, List<ForwardAttributionInput>> attributionByBatch;

  /// Help-offer `created_at` by user.
  final Map<String, DateTime> offerAt;
}
