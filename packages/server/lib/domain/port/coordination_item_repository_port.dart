import 'package:tentura_server/domain/entity/coordination_item_record.dart';

import 'package:tentura_server/domain/entity/coordination_responsibility_counts.dart';
import 'package:tentura_server/domain/entity/coordination_item_with_counts.dart';

abstract class CoordinationItemRepositoryPort {
  Future<CoordinationItemRecord> create({
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
    int? staleAfterDays,
  });

  Future<CoordinationItemRecord> updateStatus({
    required String id,
    required int newStatus,
    required String actorId,
  });

  /// Accepts an Ask or Promise: status → accepted, [acceptedById] set; recomputes [staleAt].
  Future<CoordinationItemRecord> acceptItem({
    required String id,
    required String actorId,
    required String acceptedById,
  });

  /// Redirects an Ask to a different target person (emits updated event).
  Future<CoordinationItemRecord> redirectTarget({
    required String id,
    required String actorId,
    required String newTargetPersonId,
  });

  Future<CoordinationItemRecord?> getById(String id);

  /// Atomically claims a remind slot (24h throttle + stale predicate). Returns null if not claimed.
  Future<CoordinationItemRecord?> tryClaimRemind({
    required String itemId,
    required String actorId,
  });

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

  /// Latest item-discussion message time per beacon (active items only).
  Future<Map<String, DateTime>> lastCoordinationItemMessageAtByBeaconIds({
    required List<String> beaconIds,
    required String viewerUserId,
  });

  /// Supersedes open root plans and creates a new root plan item.
  Future<CoordinationItemRecord> publishRootPlan({
    required String beaconId,
    required String creatorId,
    required String title,
    String body = '',
    String? targetPersonId,
    String? linkedMessageId,
    String? syncCurrentLineText,
  });

  /// Child plan step under [parentItemId].
  Future<CoordinationItemRecord> addPlanStep({
    required String parentItemId,
    required String creatorId,
    required String title,
    String body = '',
  });

  /// Draft ask (published=false): no room message or activity until [publishDraft].
  Future<CoordinationItemRecord> createDraftAsk({
    required String beaconId,
    required String creatorId,
    required String title,
    String body = '',
    String? targetPersonId,
    String? linkedMessageId,
    int? staleAfterDays,
  });

  /// Draft promise (published=false): no room message or activity until [publishDraft].
  Future<CoordinationItemRecord> createDraftPromise({
    required String beaconId,
    required String creatorId,
    required String title,
    String body = '',
    String? targetPersonId,
    String? linkedMessageId,
    int? staleAfterDays,
  });

  /// Publishes a draft ask or promise: sets [targetPersonId], published=true, emits room+activity.
  Future<CoordinationItemRecord> publishDraft({
    required String id,
    required String actorId,
    required String targetPersonId,
    int? staleAfterDays,
  });

  Future<CoordinationItemRecord> updateDraftAsk({
    required String id,
    required String actorId,
    required String title,
    String body = '',
    bool updateTargetPersonId = false,
    String? targetPersonId,
    bool updateStaleAfterDays = false,
    int? staleAfterDays,
  });

  /// In-place title/body update for a published item (open or accepted).
  Future<CoordinationItemRecord> updatePublishedItem({
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

  /// Draft blocker (published=false): no room message or activity until [publishDraftBlocker].
  Future<CoordinationItemRecord> createDraftBlocker({
    required String beaconId,
    required String creatorId,
    required String title,
    String body = '',
    String? targetPersonId,
    int? staleAfterDays,
  });

  /// Publishes a draft blocker: published=true, emits room+activity.
  Future<CoordinationItemRecord> publishDraftBlocker({
    required String id,
    required String actorId,
    int? staleAfterDays,
  });

  Future<CoordinationItemRecord> updateDraftBlocker({
    required String id,
    required String actorId,
    required String title,
    String body = '',
    bool updateTargetPersonId = false,
    String? targetPersonId,
    bool updateStaleAfterDays = false,
    int? staleAfterDays,
  });

  Future<void> deleteDraftBlocker({
    required String id,
    required String actorId,
  });

  /// Batch YOU-line counts per beacon for [viewerUserId].
  Future<List<CoordinationResponsibilityCounts>> responsibilityCountsByBeaconIds({
    required String viewerUserId,
    required List<String> beaconIds,
  });

  /// Open responsibility items for [viewerUserId] on [beaconId] (sheet list).
  Future<List<CoordinationItemWithCounts>> myResponsibilityItemsByBeacon({
    required String viewerUserId,
    required String beaconId,
  });

  Future<DateTime?> getBeaconItemsSeen({
    required String userId,
    required String beaconId,
  });

  /// Monotonic upsert; returns persisted watermark.
  Future<DateTime> markBeaconItemsSeen({
    required String userId,
    required String beaconId,
  });
}
