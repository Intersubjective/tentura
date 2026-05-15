import 'package:tentura_server/data/database/tentura_db.dart';

// TODO(contract): Phase-2 DTO migration — replace Drift types with domain DTOs.
abstract class CoordinationItemRepositoryPort {
  Future<CoordinationItem> create({
    required String beaconId,
    required int kind,
    required String creatorId,
    required String title,
    String body = '',
    String? targetPersonId,
    String? targetItemId,
    String? targetMessageId,
    String? linkedMessageId,
    String? linkedParentItemId,
    int ordering = 0,
  });

  Future<CoordinationItem> updateStatus({
    required String id,
    required int newStatus,
    required String actorId,
  });

  /// Accepts an Ask: status → accepted, [acceptedById] set.
  Future<CoordinationItem> acceptItem({
    required String id,
    required String actorId,
    required String acceptedById,
  });

  /// Redirects an Ask to a different target person (emits updated event).
  Future<CoordinationItem> redirectTarget({
    required String id,
    required String actorId,
    required String newTargetPersonId,
  });

  Future<CoordinationItem?> getById(String id);

  Future<List<CoordinationItem>> listByBeacon(
    String beaconId, {
    int? status,
    int? kind,
    String? acceptedById,
    String? targetPersonId,
    String? linkedParentItemId,
    bool rootOnly = false,
  });

  /// Supersedes open root plans and creates a new root plan item.
  Future<CoordinationItem> publishRootPlan({
    required String beaconId,
    required String creatorId,
    required String title,
    String body = '',
    String? linkedMessageId,
    String? syncCurrentPlanText,
  });

  /// Child plan step under [parentItemId].
  Future<CoordinationItem> addPlanStep({
    required String parentItemId,
    required String creatorId,
    required String title,
    String body = '',
  });

  Future<CoordinationItemMessage> appendMessage({
    required String itemId,
    required String senderId,
    required String body,
  });

  Future<List<CoordinationItemMessage>> listMessages(
    String itemId, {
    int? limit,
    String? before,
  });
}
