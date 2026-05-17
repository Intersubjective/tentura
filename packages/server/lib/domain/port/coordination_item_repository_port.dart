import 'package:tentura_server/data/database/tentura_db.dart';
import 'package:tentura_server/domain/entity/coordination_item_with_counts.dart';

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

  /// Ask created by [creatorId] targeting self, already accepted; one accept event only.
  Future<CoordinationItem> createSelfAcceptedAsk({
    required String beaconId,
    required String creatorId,
    required String title,
    String body = '',
    String? linkedMessageId,
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

  Future<List<CoordinationItemWithCounts>> listByBeacon(
    String beaconId, {
    required String viewerUserId,
    int? status,
    int? kind,
    String? acceptedById,
    String? targetPersonId,
    String? linkedParentItemId,
    bool rootOnly = false,
  });

  Future<void> markItemSeen({
    required String userId,
    required String itemId,
    required DateTime at,
  });

  /// Latest item-discussion message time per beacon (active items only).
  Future<Map<String, DateTime>> lastCoordinationItemMessageAtByBeaconIds({
    required List<String> beaconIds,
    required String viewerUserId,
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

  /// Draft ask (published=false): no room message or activity until [publishDraft].
  Future<CoordinationItem> createDraftAsk({
    required String beaconId,
    required String creatorId,
    required String title,
    String body = '',
    String? targetPersonId,
  });

  /// Publishes a draft ask: sets [targetPersonId], published=true, emits room+activity (or self-accept path).
  Future<CoordinationItem> publishDraft({
    required String id,
    required String actorId,
    required String targetPersonId,
  });

  Future<CoordinationItem> updateDraftAsk({
    required String id,
    required String actorId,
    required String title,
    String body = '',
    bool updateTargetPersonId = false,
    String? targetPersonId,
  });

  /// In-place title/body update for a published item (open or accepted).
  Future<CoordinationItem> updatePublishedItem({
    required String id,
    required String actorId,
    required String title,
    String body = '',
  });

  /// Hard-delete draft row owned by creator; no-op/error if not draft.
  Future<void> deleteDraftAsk({
    required String id,
    required String actorId,
  });
}
