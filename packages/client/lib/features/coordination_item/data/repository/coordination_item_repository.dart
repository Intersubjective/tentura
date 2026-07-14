import 'package:injectable/injectable.dart';

import 'package:tentura/data/service/remote_api_service.dart';
import 'package:tentura/domain/entity/coordination_item.dart';
import 'package:tentura/domain/entity/coordination_responsibility.dart';
import 'package:tentura/features/beacon_room/domain/coordination_item_room_sync.dart';
import '../gql/_g/coordination_item_list.req.gql.dart';
import '../gql/_g/coordination_item_mark_blocker.req.gql.dart';
import '../gql/_g/coordination_item_resolve_blocker.req.gql.dart';
import '../gql/_g/coordination_item_cancel_blocker.req.gql.dart';
import '../gql/_g/coordination_item_mark_ask.req.gql.dart';
import '../gql/_g/coordination_item_create_promise.req.gql.dart';
import '../gql/_g/coordination_item_create_draft_promise.req.gql.dart';
import '../gql/_g/coordination_item_publish_promise.req.gql.dart';
import '../gql/_g/coordination_item_update_draft_promise.req.gql.dart';
import '../gql/_g/coordination_item_delete_draft_promise.req.gql.dart';
import '../gql/_g/coordination_item_accept_promise.req.gql.dart';
import '../gql/_g/coordination_item_resolve_promise.req.gql.dart';
import '../gql/_g/coordination_item_cancel_promise.req.gql.dart';
import '../gql/_g/coordination_item_redirect_promise.req.gql.dart';
import '../gql/_g/coordination_item_accept_ask.req.gql.dart';
import '../gql/_g/coordination_item_resolve_ask.req.gql.dart';
import '../gql/_g/coordination_item_cancel_ask.req.gql.dart';
import '../gql/_g/coordination_item_redirect_ask.req.gql.dart';
import '../gql/_g/coordination_item_update_plan.req.gql.dart';
import '../gql/_g/coordination_item_add_plan_step.req.gql.dart';
import '../gql/_g/coordination_item_resolve_plan_step.req.gql.dart';
import '../gql/_g/coordination_item_create_resolution.req.gql.dart';
import '../gql/_g/coordination_item_accept_resolution.req.gql.dart';
import '../gql/_g/coordination_item_reject_resolution.req.gql.dart';
import '../gql/_g/coordination_item_create_draft_ask.req.gql.dart';
import '../gql/_g/coordination_item_publish_ask.req.gql.dart';
import '../gql/_g/coordination_item_update_draft_ask.req.gql.dart';
import '../gql/_g/coordination_item_update.req.gql.dart';
import '../gql/_g/coordination_item_delete_draft_ask.req.gql.dart';
import '../gql/_g/coordination_item_create_draft_blocker.req.gql.dart';
import '../gql/_g/coordination_item_publish_blocker.req.gql.dart';
import '../gql/_g/coordination_item_update_draft_blocker.req.gql.dart';
import '../gql/_g/coordination_item_delete_draft_blocker.req.gql.dart';
import '../gql/_g/coordination_item_remind.req.gql.dart';
import '../gql/_g/coordination_responsibility_batch.req.gql.dart';
import '../gql/_g/coordination_my_responsibility_items.req.gql.dart';
import '../gql/_g/mark_beacon_items_seen.req.gql.dart';
import '../model/coordination_responsibility_model.dart';
import '../model/coordination_item_model.dart';

int? _wirePublishStaleAfterDays(int? staleAfterDays) {
  if (staleAfterDays == null ||
      staleAfterDays == CoordinationItem.defaultStaleDays) {
    return null;
  }
  return staleAfterDays;
}

@lazySingleton
class CoordinationItemRepository {
  CoordinationItemRepository(
    this._remote,
    this._itemRoomSync,
  );

  static const _label = 'CoordinationItem';

  final RemoteApiService _remote;

  final CoordinationItemRoomSync _itemRoomSync;

  CoordinationItem _notifyItemUpdated(CoordinationItem item) {
    _itemRoomSync.notifyItemUpdated(item);
    return item;
  }

  Future<List<CoordinationItem>> listByBeacon(
    String beaconId, {
    int? status,
    int? kind,
    String? acceptedById,
    String? targetPersonId,
    String? linkedParentItemId,
    bool? rootOnly,
  }) => _remote
      .request(
        GCoordinationItemListReq(
          (b) => b.vars
            ..beaconId = beaconId
            ..status = status
            ..kind = kind
            ..acceptedById = acceptedById
            ..targetPersonId = targetPersonId
            ..linkedParentItemId = linkedParentItemId
            ..rootOnly = rootOnly,
        ),
      )
      .firstWhere((e) => e.dataSource == DataSource.Link)
      .then(
        (r) => r
            .dataOrThrow(label: _label)
            .coordinationItemsByBeacon
            .map((e) => (e as CoordinationItemListModel).toEntity())
            .toList(),
      );

  Future<CoordinationItem> remindItem({required String itemId}) => _remote
      .request(
        GCoordinationItemRemindReq((b) => b.vars..itemId = itemId),
      )
      .firstWhere((e) => e.dataSource == DataSource.Link)
      .then(
        (r) =>
            (r.dataOrThrow(label: _label).remindCoordinationItem
                    as CoordinationItemRemindModel)
                .toEntity(),
      )
      .then(_notifyItemUpdated);

  Future<CoordinationItem> markBlocker({
    required String beaconId,
    required String title,
    String? body,
    String? targetPersonId,
    String? linkedMessageId,
    int? staleAfterDays,
  }) => _remote
      .request(
        GCoordinationItemMarkBlockerReq(
          (b) => b.vars
            ..beaconId = beaconId
            ..title = title
            ..body = body
            ..targetPersonId = targetPersonId
            ..linkedMessageId = linkedMessageId
            ..staleAfterDays = _wirePublishStaleAfterDays(staleAfterDays),
        ),
      )
      .firstWhere((e) => e.dataSource == DataSource.Link)
      .then(
        (r) =>
            (r.dataOrThrow(label: _label).markBlocker
                    as CoordinationItemMarkBlockerModel)
                .toEntity(),
      )
      .then(_notifyItemUpdated);

  Future<CoordinationItem> resolveBlocker({
    required String itemId,
    String? note,
  }) => _remote
      .request(
        GCoordinationItemResolveBlockerReq(
          (b) => b.vars
            ..itemId = itemId
            ..note = note,
        ),
      )
      .firstWhere((e) => e.dataSource == DataSource.Link)
      .then(
        (r) =>
            (r.dataOrThrow(label: _label).resolveBlocker
                    as CoordinationItemResolveBlockerModel)
                .toEntity(),
      )
      .then(_notifyItemUpdated);

  Future<CoordinationItem> cancelBlocker({
    required String itemId,
    String? reason,
  }) => _remote
      .request(
        GCoordinationItemCancelBlockerReq(
          (b) => b.vars
            ..itemId = itemId
            ..reason = reason,
        ),
      )
      .firstWhere((e) => e.dataSource == DataSource.Link)
      .then(
        (r) =>
            (r.dataOrThrow(label: _label).cancelBlocker
                    as CoordinationItemCancelBlockerModel)
                .toEntity(),
      )
      .then(_notifyItemUpdated);

  Future<CoordinationItem> markAsk({
    required String beaconId,
    required String title,
    required String targetPersonId,
    String? body,
    String? linkedMessageId,
    int? staleAfterDays,
  }) => _remote
      .request(
        GCoordinationItemMarkAskReq(
          (b) => b.vars
            ..beaconId = beaconId
            ..title = title
            ..targetPersonId = targetPersonId
            ..body = body
            ..linkedMessageId = linkedMessageId
            ..staleAfterDays = _wirePublishStaleAfterDays(staleAfterDays),
        ),
      )
      .firstWhere((e) => e.dataSource == DataSource.Link)
      .then(
        (r) =>
            (r.dataOrThrow(label: _label).markAsk
                    as CoordinationItemMarkAskModel)
                .toEntity(),
      )
      .then(_notifyItemUpdated);

  Future<CoordinationItem> createPromise({
    required String beaconId,
    required String title,
    required String targetPersonId,
    String? body,
    String? linkedMessageId,
    int? staleAfterDays,
  }) => _remote
      .request(
        GCoordinationItemCreatePromiseReq(
          (b) => b.vars
            ..beaconId = beaconId
            ..title = title
            ..targetPersonId = targetPersonId
            ..body = body
            ..linkedMessageId = linkedMessageId
            ..staleAfterDays = _wirePublishStaleAfterDays(staleAfterDays),
        ),
      )
      .firstWhere((e) => e.dataSource == DataSource.Link)
      .then(
        (r) =>
            (r.dataOrThrow(label: _label).createPromise
                    as CoordinationItemCreatePromiseModel)
                .toEntity(),
      )
      .then(_notifyItemUpdated);

  Future<CoordinationItem> createDraftPromise({
    required String beaconId,
    required String title,
    String? body,
    String? targetPersonId,
    String? linkedMessageId,
    int? staleAfterDays,
  }) => _remote
      .request(
        GCoordinationItemCreateDraftPromiseReq(
          (b) => b.vars
            ..beaconId = beaconId
            ..title = title
            ..body = body
            ..targetPersonId = targetPersonId
            ..linkedMessageId = linkedMessageId
            ..staleAfterDays = _wirePublishStaleAfterDays(staleAfterDays),
        ),
      )
      .firstWhere((e) => e.dataSource == DataSource.Link)
      .then(
        (r) =>
            (r.dataOrThrow(label: _label).createDraftPromise
                    as CoordinationItemCreateDraftPromiseModel)
                .toEntity(),
      )
      .then(_notifyItemUpdated);

  Future<CoordinationItem> publishDraftPromise({
    required String itemId,
    required String targetPersonId,
    int? staleAfterDays,
  }) => _remote
      .request(
        GCoordinationItemPublishPromiseReq(
          (b) => b.vars
            ..itemId = itemId
            ..targetPersonId = targetPersonId
            ..staleAfterDays = _wirePublishStaleAfterDays(staleAfterDays),
        ),
      )
      .firstWhere((e) => e.dataSource == DataSource.Link)
      .then(
        (r) =>
            (r.dataOrThrow(label: _label).publishPromise
                    as CoordinationItemPublishPromiseModel)
                .toEntity(),
      )
      .then(_notifyItemUpdated);

  Future<CoordinationItem> updateDraftPromise({
    required String itemId,
    required String title,
    String body = '',
    String? targetPersonId,
    bool omitTargetPersonId = false,
    int? staleAfterDays,
  }) => _remote
      .request(
        GCoordinationItemUpdateDraftPromiseReq(
          (b) => b.vars
            ..itemId = itemId
            ..title = title
            ..body = body
            ..targetPersonId = omitTargetPersonId ? null : targetPersonId
            ..staleAfterDays = staleAfterDays,
        ),
      )
      .firstWhere((e) => e.dataSource == DataSource.Link)
      .then(
        (r) =>
            (r.dataOrThrow(label: _label).updateDraftPromise
                    as CoordinationItemUpdateDraftPromiseModel)
                .toEntity(),
      )
      .then(_notifyItemUpdated);

  Future<void> deleteDraftPromise({required String itemId}) => _remote
      .request(
        GCoordinationItemDeleteDraftPromiseReq((b) => b.vars..itemId = itemId),
      )
      .firstWhere((e) => e.dataSource == DataSource.Link)
      .then((r) => r.dataOrThrow(label: _label).deleteDraftPromise);

  Future<CoordinationItem> acceptPromise({required String itemId}) => _remote
      .request(
        GCoordinationItemAcceptPromiseReq((b) => b.vars..itemId = itemId),
      )
      .firstWhere((e) => e.dataSource == DataSource.Link)
      .then(
        (r) =>
            (r.dataOrThrow(label: _label).acceptPromise
                    as CoordinationItemAcceptPromiseModel)
                .toEntity(),
      )
      .then(_notifyItemUpdated);

  Future<CoordinationItem> resolvePromise({
    required String itemId,
    String? note,
  }) => _remote
      .request(
        GCoordinationItemResolvePromiseReq(
          (b) => b.vars
            ..itemId = itemId
            ..note = note,
        ),
      )
      .firstWhere((e) => e.dataSource == DataSource.Link)
      .then(
        (r) =>
            (r.dataOrThrow(label: _label).resolvePromise
                    as CoordinationItemResolvePromiseModel)
                .toEntity(),
      )
      .then(_notifyItemUpdated);

  Future<CoordinationItem> cancelPromise({
    required String itemId,
    String? reason,
  }) => _remote
      .request(
        GCoordinationItemCancelPromiseReq(
          (b) => b.vars
            ..itemId = itemId
            ..reason = reason,
        ),
      )
      .firstWhere((e) => e.dataSource == DataSource.Link)
      .then(
        (r) =>
            (r.dataOrThrow(label: _label).cancelPromise
                    as CoordinationItemCancelPromiseModel)
                .toEntity(),
      )
      .then(_notifyItemUpdated);

  Future<CoordinationItem> redirectPromise({
    required String itemId,
    required String newTargetPersonId,
  }) => _remote
      .request(
        GCoordinationItemRedirectPromiseReq(
          (b) => b.vars
            ..itemId = itemId
            ..newTargetPersonId = newTargetPersonId,
        ),
      )
      .firstWhere((e) => e.dataSource == DataSource.Link)
      .then(
        (r) =>
            (r.dataOrThrow(label: _label).redirectPromise
                    as CoordinationItemRedirectPromiseModel)
                .toEntity(),
      )
      .then(_notifyItemUpdated);

  Future<CoordinationItem> createDraftAsk({
    required String beaconId,
    required String title,
    String? body,
    String? targetPersonId,
    String? linkedMessageId,
    int? staleAfterDays,
  }) => _remote
      .request(
        GCoordinationItemCreateDraftAskReq(
          (b) => b.vars
            ..beaconId = beaconId
            ..title = title
            ..body = body
            ..targetPersonId = targetPersonId
            ..linkedMessageId = linkedMessageId
            ..staleAfterDays = _wirePublishStaleAfterDays(staleAfterDays),
        ),
      )
      .firstWhere((e) => e.dataSource == DataSource.Link)
      .then(
        (r) =>
            (r.dataOrThrow(label: _label).createDraftAsk
                    as CoordinationItemCreateDraftAskModel)
                .toEntity(),
      )
      .then(_notifyItemUpdated);

  Future<CoordinationItem> publishDraftAsk({
    required String itemId,
    required String targetPersonId,
    int? staleAfterDays,
  }) => _remote
      .request(
        GCoordinationItemPublishAskReq(
          (b) => b.vars
            ..itemId = itemId
            ..targetPersonId = targetPersonId
            ..staleAfterDays = _wirePublishStaleAfterDays(staleAfterDays),
        ),
      )
      .firstWhere((e) => e.dataSource == DataSource.Link)
      .then(
        (r) =>
            (r.dataOrThrow(label: _label).publishAsk
                    as CoordinationItemPublishAskModel)
                .toEntity(),
      )
      .then(_notifyItemUpdated);

  Future<CoordinationItem> updateDraftAsk({
    required String itemId,
    required String title,
    String body = '',
    String? targetPersonId,
    bool omitTargetPersonId = false,
    int? staleAfterDays,
  }) => _remote
      .request(
        GCoordinationItemUpdateDraftAskReq(
          (b) => b.vars
            ..itemId = itemId
            ..title = title
            ..body = body
            ..targetPersonId = omitTargetPersonId ? null : targetPersonId
            ..staleAfterDays = staleAfterDays,
        ),
      )
      .firstWhere((e) => e.dataSource == DataSource.Link)
      .then(
        (r) =>
            (r.dataOrThrow(label: _label).updateDraftAsk
                    as CoordinationItemUpdateDraftAskModel)
                .toEntity(),
      )
      .then(_notifyItemUpdated);

  Future<void> deleteDraftAsk({required String itemId}) => _remote
      .request(
        GCoordinationItemDeleteDraftAskReq((b) => b.vars..itemId = itemId),
      )
      .firstWhere((e) => e.dataSource == DataSource.Link)
      .then((r) => r.dataOrThrow(label: _label).deleteDraftAsk);

  Future<CoordinationItem> createDraftBlocker({
    required String beaconId,
    required String title,
    String? body,
    String? targetPersonId,
    int? staleAfterDays,
  }) => _remote
      .request(
        GCoordinationItemCreateDraftBlockerReq(
          (b) => b.vars
            ..beaconId = beaconId
            ..title = title
            ..body = body
            ..targetPersonId = targetPersonId
            ..staleAfterDays = _wirePublishStaleAfterDays(staleAfterDays),
        ),
      )
      .firstWhere((e) => e.dataSource == DataSource.Link)
      .then(
        (r) =>
            (r.dataOrThrow(label: _label).createDraftBlocker
                    as CoordinationItemCreateDraftBlockerModel)
                .toEntity(),
      )
      .then(_notifyItemUpdated);

  Future<CoordinationItem> publishDraftBlocker({
    required String itemId,
    int? staleAfterDays,
  }) => _remote
      .request(
        GCoordinationItemPublishBlockerReq(
          (b) => b.vars
            ..itemId = itemId
            ..staleAfterDays = _wirePublishStaleAfterDays(staleAfterDays),
        ),
      )
      .firstWhere((e) => e.dataSource == DataSource.Link)
      .then(
        (r) =>
            (r.dataOrThrow(label: _label).publishBlocker
                    as CoordinationItemPublishBlockerModel)
                .toEntity(),
      )
      .then(_notifyItemUpdated);

  Future<CoordinationItem> updateDraftBlocker({
    required String itemId,
    required String title,
    String body = '',
    String? targetPersonId,
    bool omitTargetPersonId = false,
    int? staleAfterDays,
  }) => _remote
      .request(
        GCoordinationItemUpdateDraftBlockerReq(
          (b) => b.vars
            ..itemId = itemId
            ..title = title
            ..body = body
            ..targetPersonId = omitTargetPersonId ? null : targetPersonId
            ..staleAfterDays = staleAfterDays,
        ),
      )
      .firstWhere((e) => e.dataSource == DataSource.Link)
      .then(
        (r) =>
            (r.dataOrThrow(label: _label).updateDraftBlocker
                    as CoordinationItemUpdateDraftBlockerModel)
                .toEntity(),
      )
      .then(_notifyItemUpdated);

  Future<void> deleteDraftBlocker({required String itemId}) => _remote
      .request(
        GCoordinationItemDeleteDraftBlockerReq((b) => b.vars..itemId = itemId),
      )
      .firstWhere((e) => e.dataSource == DataSource.Link)
      .then((r) => r.dataOrThrow(label: _label).deleteDraftBlocker);

  Future<CoordinationItem> acceptAsk({required String itemId}) => _remote
      .request(
        GCoordinationItemAcceptAskReq((b) => b.vars..itemId = itemId),
      )
      .firstWhere((e) => e.dataSource == DataSource.Link)
      .then(
        (r) =>
            (r.dataOrThrow(label: _label).acceptAsk
                    as CoordinationItemAcceptAskModel)
                .toEntity(),
      )
      .then(_notifyItemUpdated);

  Future<CoordinationItem> resolveAsk({
    required String itemId,
    String? note,
  }) => _remote
      .request(
        GCoordinationItemResolveAskReq(
          (b) => b.vars
            ..itemId = itemId
            ..note = note,
        ),
      )
      .firstWhere((e) => e.dataSource == DataSource.Link)
      .then(
        (r) =>
            (r.dataOrThrow(label: _label).resolveAsk
                    as CoordinationItemResolveAskModel)
                .toEntity(),
      )
      .then(_notifyItemUpdated);

  Future<CoordinationItem> cancelAsk({
    required String itemId,
    String? reason,
  }) => _remote
      .request(
        GCoordinationItemCancelAskReq(
          (b) => b.vars
            ..itemId = itemId
            ..reason = reason,
        ),
      )
      .firstWhere((e) => e.dataSource == DataSource.Link)
      .then(
        (r) =>
            (r.dataOrThrow(label: _label).cancelAsk
                    as CoordinationItemCancelAskModel)
                .toEntity(),
      )
      .then(_notifyItemUpdated);

  Future<CoordinationItem> redirectAsk({
    required String itemId,
    required String newTargetPersonId,
  }) => _remote
      .request(
        GCoordinationItemRedirectAskReq(
          (b) => b.vars
            ..itemId = itemId
            ..newTargetPersonId = newTargetPersonId,
        ),
      )
      .firstWhere((e) => e.dataSource == DataSource.Link)
      .then(
        (r) =>
            (r.dataOrThrow(label: _label).redirectAsk
                    as CoordinationItemRedirectAskModel)
                .toEntity(),
      )
      .then(_notifyItemUpdated);

  Future<CoordinationItem> updateItem({
    required String itemId,
    required String title,
    String? body,
  }) => _remote
      .request(
        GCoordinationItemUpdateReq(
          (b) => b.vars
            ..itemId = itemId
            ..title = title
            ..body = body,
        ),
      )
      .firstWhere((e) => e.dataSource == DataSource.Link)
      .then(
        (r) =>
            (r.dataOrThrow(label: _label).updateCoordinationItem
                    as CoordinationItemUpdateModel)
                .toEntity(),
      )
      .then(_notifyItemUpdated);

  Future<CoordinationItem> updatePlan({
    required String beaconId,
    required String title,
    String? body,
    String? targetPersonId,
    String? linkedMessageId,
  }) => _remote
      .request(
        GCoordinationItemUpdatePlanReq(
          (b) => b.vars
            ..beaconId = beaconId
            ..title = title
            ..body = body
            ..targetPersonId = targetPersonId
            ..linkedMessageId = linkedMessageId,
        ),
      )
      .firstWhere((e) => e.dataSource == DataSource.Link)
      .then(
        (r) =>
            (r.dataOrThrow(label: _label).updateCoordinationPlan
                    as CoordinationItemUpdatePlanModel)
                .toEntity(),
      )
      .then(_notifyItemUpdated);

  Future<CoordinationItem> addPlanStep({
    required String parentItemId,
    required String title,
    String? body,
  }) => _remote
      .request(
        GCoordinationItemAddPlanStepReq(
          (b) => b.vars
            ..parentItemId = parentItemId
            ..title = title
            ..body = body,
        ),
      )
      .firstWhere((e) => e.dataSource == DataSource.Link)
      .then(
        (r) =>
            (r.dataOrThrow(label: _label).addPlanStep
                    as CoordinationItemAddPlanStepModel)
                .toEntity(),
      )
      .then(_notifyItemUpdated);

  Future<CoordinationItem> resolvePlanStep({required String itemId}) => _remote
      .request(
        GCoordinationItemResolvePlanStepReq((b) => b.vars..itemId = itemId),
      )
      .firstWhere((e) => e.dataSource == DataSource.Link)
      .then(
        (r) =>
            (r.dataOrThrow(label: _label).resolvePlanStep
                    as CoordinationItemResolvePlanStepModel)
                .toEntity(),
      )
      .then(_notifyItemUpdated);

  Future<CoordinationItem> createResolution({
    required String beaconId,
    required String title,
    String? body,
    String? targetItemId,
    String? targetMessageId,
    String? linkedMessageId,
  }) => _remote
      .request(
        GCoordinationItemCreateResolutionReq(
          (b) => b.vars
            ..beaconId = beaconId
            ..title = title
            ..body = body
            ..targetItemId = targetItemId
            ..targetMessageId = targetMessageId
            ..linkedMessageId = linkedMessageId,
        ),
      )
      .firstWhere((e) => e.dataSource == DataSource.Link)
      .then(
        (r) =>
            (r.dataOrThrow(label: _label).createResolution
                    as CoordinationItemCreateResolutionModel)
                .toEntity(),
      )
      .then(_notifyItemUpdated);

  Future<CoordinationItem> acceptResolution({required String itemId}) => _remote
      .request(
        GCoordinationItemAcceptResolutionReq((b) => b.vars..itemId = itemId),
      )
      .firstWhere((e) => e.dataSource == DataSource.Link)
      .then(
        (r) =>
            (r.dataOrThrow(label: _label).acceptResolution
                    as CoordinationItemAcceptResolutionModel)
                .toEntity(),
      )
      .then(_notifyItemUpdated);

  Future<CoordinationItem> rejectResolution({
    required String itemId,
    String? reason,
  }) => _remote
      .request(
        GCoordinationItemRejectResolutionReq(
          (b) => b.vars
            ..itemId = itemId
            ..reason = reason,
        ),
      )
      .firstWhere((e) => e.dataSource == DataSource.Link)
      .then(
        (r) =>
            (r.dataOrThrow(label: _label).rejectResolution
                    as CoordinationItemRejectResolutionModel)
                .toEntity(),
      )
      .then(_notifyItemUpdated);

  Future<Map<String, CoordinationResponsibility>> fetchResponsibilityBatch(
    List<String> beaconIds,
  ) async {
    if (beaconIds.isEmpty) {
      return const {};
    }
    final rows = await _remote
        .request(
          GCoordinationResponsibilityBatchReq(
            (b) => b.vars.beaconIds.replace(beaconIds),
          ),
        )
        .firstWhere((e) => e.dataSource == DataSource.Link)
        .then(
          (r) => r.dataOrThrow(label: _label).coordinationResponsibilityBatch,
        );
    return {
      for (final row in rows)
        row.beaconId: (row as CoordinationResponsibilityBatchRowModel)
            .toEntity(),
    };
  }

  Future<CoordinationResponsibility> fetchResponsibility(
    String beaconId,
  ) async {
    final map = await fetchResponsibilityBatch([beaconId]);
    return map[beaconId] ?? CoordinationResponsibility(beaconId: beaconId);
  }

  Future<List<CoordinationItem>> fetchMyResponsibilityItems(
    String beaconId,
  ) => _remote
      .request(
        GCoordinationMyResponsibilityItemsReq(
          (b) => b.vars.beaconId = beaconId,
        ),
      )
      .firstWhere((e) => e.dataSource == DataSource.Link)
      .then(
        (r) => r
            .dataOrThrow(label: _label)
            .coordinationMyResponsibilityItems
            .map(
              (e) => (e as CoordinationMyResponsibilityItemModel).toEntity(),
            )
            .toList(growable: false),
      );

  Future<void> markItemsSeen(String beaconId) => _remote
      .request(
        GMarkBeaconItemsSeenReq((b) => b.vars.beaconId = beaconId),
      )
      .firstWhere((e) => e.dataSource == DataSource.Link)
      .then((r) {
        r.dataOrThrow(label: _label);
      });
}
