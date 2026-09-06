import 'package:injectable/injectable.dart';

import 'package:tentura/data/service/remote_api_service.dart';
import 'package:tentura/domain/entity/coordination_item.dart';
import 'package:tentura/domain/entity/coordination_responsibility.dart';
import 'package:tentura/features/beacon_threads/domain/coordination_item_room_sync.dart';
import '../gql/_g/coordination_item_list.req.gql.dart';
import '../gql/_g/coordination_item_update_plan.req.gql.dart';
import '../gql/_g/coordination_item_add_plan_step.req.gql.dart';
import '../gql/_g/coordination_item_resolve_plan_step.req.gql.dart';
import '../gql/_g/coordination_item_update.req.gql.dart';
import '../gql/_g/coordination_item_remind.req.gql.dart';
import '../gql/_g/coordination_responsibility_batch.req.gql.dart';
import '../gql/_g/coordination_my_responsibility_items.req.gql.dart';
import '../gql/_g/mark_beacon_items_seen.req.gql.dart';
import '../model/coordination_responsibility_model.dart';
import '../model/coordination_item_model.dart';

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
                ?.map((e) => (e as CoordinationItemListModel).toEntity())
                .toList() ??
            const [],
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
      for (final row in [...?rows])
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
                ?.map(
                  (e) =>
                      (e as CoordinationMyResponsibilityItemModel).toEntity(),
                )
                .toList(growable: false) ??
            const [],
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
