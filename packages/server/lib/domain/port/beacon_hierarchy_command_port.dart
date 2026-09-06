import 'package:tentura_root/domain/entity/beacon_child_command_outcome.dart';
import 'package:tentura_root/domain/entity/beacon_creation_context.dart';

/// Persisted child-command lookup for idempotent create flows.
class BeaconChildCommandRecord {
  const BeaconChildCommandRecord({
    required this.actorUserId,
    required this.clientCommandId,
    required this.normalizedInputHash,
    required this.outcome,
    this.resultBeaconId,
    required this.deleted,
  });

  final String actorUserId;
  final String clientCommandId;
  final String normalizedInputHash;
  final BeaconChildCommandOutcome outcome;
  final String? resultBeaconId;
  final bool deleted;
}

/// Domain result of an authorized child create command.
class BeaconChildCreateResult {
  const BeaconChildCreateResult({
    required this.outcome,
    this.beaconId,
  });

  final BeaconChildCommandOutcome outcome;
  final String? beaconId;
}

/// Idempotency and promotion provenance persistence.
abstract class BeaconHierarchyCommandPort {
  Future<BeaconChildCommandRecord?> findCommand({
    required String actorUserId,
    required String clientCommandId,
  });

  Future<BeaconChildCreateResult> recordCreateOutcome({
    required String actorUserId,
    required String clientCommandId,
    required String normalizedInputHash,
    required BeaconCreationContext creationContext,
    required BeaconChildCommandOutcome outcome,
    String? resultBeaconId,
  });

  Future<void> markCommandDeleted({
    required String actorUserId,
    required String clientCommandId,
  });

  Future<String?> findPublishedChildForSourceMessage({
    required String sourceMessageId,
  });
}
