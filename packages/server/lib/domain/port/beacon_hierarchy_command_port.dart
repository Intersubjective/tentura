import 'package:tentura_root/domain/entity/beacon_child_command_outcome.dart';
import 'package:tentura_root/domain/entity/beacon_creation_context.dart';
import 'package:tentura_root/domain/entity/beacon_status.dart';

import 'package:tentura_server/domain/policy/beacon_promotion_eligibility_policy.dart';

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
    this.beacon,
  });

  final BeaconChildCommandOutcome outcome;
  final String? beaconId;
  final Object? beacon;
}

/// Parent beacon facts required for child create/publish validation.
class BeaconParentValidationRow {
  const BeaconParentValidationRow({
    required this.id,
    required this.ownerId,
    required this.status,
    required this.isPublished,
  });

  final String id;
  final String ownerId;
  final BeaconStatus status;
  final bool isPublished;
}

/// Promotion provenance row for a child draft.
class BeaconChildPromotionRow {
  const BeaconChildPromotionRow({
    required this.childBeaconId,
    required this.parentBeaconId,
    this.sourceMessageId,
    this.publishedAt,
  });

  final String childBeaconId;
  final String parentBeaconId;
  final String? sourceMessageId;
  final DateTime? publishedAt;
}

/// Thrown when a promotion publish hits the partial unique source index.
class BeaconPromotionPublishConflict implements Exception {
  const BeaconPromotionPublishConflict(this.existingChildBeaconId);

  final String existingChildBeaconId;
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

  Future<void> lockBeaconRows(List<String> beaconIds);

  Future<void> lockChildCommandRow({
    required String actorUserId,
    required String clientCommandId,
  });

  Future<void> lockPromotionRows({
    required String childBeaconId,
    String? sourceMessageId,
  });

  Future<bool> effectiveAdmission({
    required String beaconId,
    required String viewerId,
  });

  Future<BeaconParentValidationRow?> loadParentValidationRow(
    String parentBeaconId,
  );

  Future<BeaconPromotionSourceFacts?> loadPromotionSourceFacts({
    required String parentBeaconId,
    required String sourceMessageId,
  });

  Future<BeaconChildPromotionRow?> loadPromotionForChild(String childBeaconId);

  Future<void> upsertDraftPromotion({
    required String childBeaconId,
    required String parentBeaconId,
    required String? sourceMessageId,
    required String promoterUserId,
  });

  /// Sets [publishedAt] on the child's promotion row.
  ///
  /// Throws [BeaconPromotionPublishConflict] when another child already
  /// published for the same source message.
  Future<void> markPromotionPublished({
    required String childBeaconId,
    required String parentBeaconId,
    required String? sourceMessageId,
    required String promoterUserId,
  });

  Future<String> insertChildCreationNotice({
    required String parentBeaconId,
    required String childBeaconId,
    String? sourceMessageId,
    required String actorUserId,
  });
}
