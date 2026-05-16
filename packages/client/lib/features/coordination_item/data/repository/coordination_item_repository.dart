import 'package:injectable/injectable.dart';

import 'package:tentura/data/service/remote_api_service.dart';
import 'package:tentura/domain/entity/coordination_item.dart';
import 'package:tentura/domain/entity/coordination_item_message.dart';

import '../gql/_g/coordination_item_list.req.gql.dart';
import '../gql/_g/coordination_item_messages.req.gql.dart';
import '../gql/_g/coordination_item_mark_blocker.req.gql.dart';
import '../gql/_g/coordination_item_resolve_blocker.req.gql.dart';
import '../gql/_g/coordination_item_cancel_blocker.req.gql.dart';
import '../gql/_g/coordination_item_mark_ask.req.gql.dart';
import '../gql/_g/coordination_item_create_self_ask.req.gql.dart';
import '../gql/_g/coordination_item_accept_ask.req.gql.dart';
import '../gql/_g/coordination_item_resolve_ask.req.gql.dart';
import '../gql/_g/coordination_item_cancel_ask.req.gql.dart';
import '../gql/_g/coordination_item_redirect_ask.req.gql.dart';
import '../gql/_g/coordination_item_append_message.req.gql.dart';
import '../gql/_g/coordination_item_update_plan.req.gql.dart';
import '../gql/_g/coordination_item_add_plan_step.req.gql.dart';
import '../gql/_g/coordination_item_resolve_plan_step.req.gql.dart';
import '../gql/_g/coordination_item_create_resolution.req.gql.dart';
import '../gql/_g/coordination_item_accept_resolution.req.gql.dart';
import '../gql/_g/coordination_item_reject_resolution.req.gql.dart';
import '../gql/_g/coordination_item_create_draft_ask.req.gql.dart';
import '../gql/_g/coordination_item_publish_ask.req.gql.dart';
import '../gql/_g/coordination_item_update_draft_ask.req.gql.dart';
import '../gql/_g/coordination_item_delete_draft_ask.req.gql.dart';
import '../gql/_g/coordination_item_mark_seen.req.gql.dart';
import '../model/coordination_item_model.dart';

@lazySingleton
class CoordinationItemRepository {
  CoordinationItemRepository(this._remote);

  static const _label = 'CoordinationItem';

  final RemoteApiService _remote;

  Future<List<CoordinationItem>> listByBeacon(
    String beaconId, {
    int? status,
    int? kind,
    String? acceptedById,
    String? targetPersonId,
    String? linkedParentItemId,
    bool? rootOnly,
  }) =>
      _remote
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
          .then((r) => r
              .dataOrThrow(label: _label)
              .coordinationItemsByBeacon
              .map((e) => (e as CoordinationItemListModel).toEntity())
              .toList());

  Future<CoordinationItem> markBlocker({
    required String beaconId,
    required String title,
    String? body,
    String? linkedMessageId,
  }) =>
      _remote
          .request(
            GCoordinationItemMarkBlockerReq(
              (b) => b.vars
                ..beaconId = beaconId
                ..title = title
                ..body = body
                ..linkedMessageId = linkedMessageId,
            ),
          )
          .firstWhere((e) => e.dataSource == DataSource.Link)
          .then((r) => (r
                  .dataOrThrow(label: _label)
                  .markBlocker as CoordinationItemMarkBlockerModel)
              .toEntity());

  Future<CoordinationItem> resolveBlocker({
    required String itemId,
    String? note,
  }) =>
      _remote
          .request(
            GCoordinationItemResolveBlockerReq(
              (b) => b.vars
                ..itemId = itemId
                ..note = note,
            ),
          )
          .firstWhere((e) => e.dataSource == DataSource.Link)
          .then((r) => (r
                  .dataOrThrow(label: _label)
                  .resolveBlocker as CoordinationItemResolveBlockerModel)
              .toEntity());

  Future<CoordinationItem> cancelBlocker({
    required String itemId,
    String? reason,
  }) =>
      _remote
          .request(
            GCoordinationItemCancelBlockerReq(
              (b) => b.vars
                ..itemId = itemId
                ..reason = reason,
            ),
          )
          .firstWhere((e) => e.dataSource == DataSource.Link)
          .then((r) => (r
                  .dataOrThrow(label: _label)
                  .cancelBlocker as CoordinationItemCancelBlockerModel)
              .toEntity());

  Future<CoordinationItem> markAsk({
    required String beaconId,
    required String title,
    required String targetPersonId,
    String? body,
    String? linkedMessageId,
  }) =>
      _remote
          .request(
            GCoordinationItemMarkAskReq(
              (b) => b.vars
                ..beaconId = beaconId
                ..title = title
                ..targetPersonId = targetPersonId
                ..body = body
                ..linkedMessageId = linkedMessageId,
            ),
          )
          .firstWhere((e) => e.dataSource == DataSource.Link)
          .then((r) => (r.dataOrThrow(label: _label).markAsk
                  as CoordinationItemMarkAskModel)
              .toEntity());

  Future<CoordinationItem> createSelfAsk({
    required String beaconId,
    required String title,
    String? body,
    String? linkedMessageId,
  }) =>
      _remote
          .request(
            GCoordinationItemCreateSelfAskReq(
              (b) => b.vars
                ..beaconId = beaconId
                ..title = title
                ..body = body
                ..linkedMessageId = linkedMessageId,
            ),
          )
          .firstWhere((e) => e.dataSource == DataSource.Link)
          .then((r) => (r.dataOrThrow(label: _label).createSelfAsk
                  as CoordinationItemCreateSelfAskModel)
              .toEntity());

  Future<CoordinationItem> createDraftAsk({
    required String beaconId,
    required String title,
    String? body,
    String? targetPersonId,
  }) =>
      _remote
          .request(
            GCoordinationItemCreateDraftAskReq(
              (b) => b.vars
                ..beaconId = beaconId
                ..title = title
                ..body = body
                ..targetPersonId = targetPersonId,
            ),
          )
          .firstWhere((e) => e.dataSource == DataSource.Link)
          .then((r) => (r.dataOrThrow(label: _label).createDraftAsk
                  as CoordinationItemCreateDraftAskModel)
              .toEntity());

  Future<CoordinationItem> publishDraftAsk({
    required String itemId,
    required String targetPersonId,
  }) =>
      _remote
          .request(
            GCoordinationItemPublishAskReq(
              (b) => b.vars
                ..itemId = itemId
                ..targetPersonId = targetPersonId,
            ),
          )
          .firstWhere((e) => e.dataSource == DataSource.Link)
          .then((r) => (r.dataOrThrow(label: _label).publishAsk
                  as CoordinationItemPublishAskModel)
              .toEntity());

  Future<CoordinationItem> updateDraftAsk({
    required String itemId,
    required String title,
    String body = '',
    String? targetPersonId,
    bool omitTargetPersonId = false,
  }) =>
      _remote
          .request(
            GCoordinationItemUpdateDraftAskReq(
              (b) => b.vars
                ..itemId = itemId
                ..title = title
                ..body = body
                ..targetPersonId =
                    omitTargetPersonId ? null : targetPersonId,
            ),
          )
          .firstWhere((e) => e.dataSource == DataSource.Link)
          .then((r) => (r.dataOrThrow(label: _label).updateDraftAsk
                  as CoordinationItemUpdateDraftAskModel)
              .toEntity());

  Future<void> deleteDraftAsk({required String itemId}) => _remote
      .request(
        GCoordinationItemDeleteDraftAskReq((b) => b.vars..itemId = itemId),
      )
      .firstWhere((e) => e.dataSource == DataSource.Link)
      .then((r) => r.dataOrThrow(label: _label).deleteDraftAsk);

  Future<CoordinationItem> acceptAsk({required String itemId}) =>
      _remote
          .request(
            GCoordinationItemAcceptAskReq((b) => b.vars..itemId = itemId),
          )
          .firstWhere((e) => e.dataSource == DataSource.Link)
          .then((r) => (r.dataOrThrow(label: _label).acceptAsk
                  as CoordinationItemAcceptAskModel)
              .toEntity());

  Future<CoordinationItem> resolveAsk({
    required String itemId,
    String? note,
  }) =>
      _remote
          .request(
            GCoordinationItemResolveAskReq(
              (b) => b.vars
                ..itemId = itemId
                ..note = note,
            ),
          )
          .firstWhere((e) => e.dataSource == DataSource.Link)
          .then((r) => (r.dataOrThrow(label: _label).resolveAsk
                  as CoordinationItemResolveAskModel)
              .toEntity());

  Future<CoordinationItem> cancelAsk({
    required String itemId,
    String? reason,
  }) =>
      _remote
          .request(
            GCoordinationItemCancelAskReq(
              (b) => b.vars
                ..itemId = itemId
                ..reason = reason,
            ),
          )
          .firstWhere((e) => e.dataSource == DataSource.Link)
          .then((r) => (r.dataOrThrow(label: _label).cancelAsk
                  as CoordinationItemCancelAskModel)
              .toEntity());

  Future<CoordinationItem> redirectAsk({
    required String itemId,
    required String newTargetPersonId,
  }) =>
      _remote
          .request(
            GCoordinationItemRedirectAskReq(
              (b) => b.vars
                ..itemId = itemId
                ..newTargetPersonId = newTargetPersonId,
            ),
          )
          .firstWhere((e) => e.dataSource == DataSource.Link)
          .then((r) => (r.dataOrThrow(label: _label).redirectAsk
                  as CoordinationItemRedirectAskModel)
              .toEntity());

  Future<List<CoordinationItemMessage>> listMessages(
    String itemId, {
    int? limit,
    String? before,
  }) =>
      _remote
          .request(
            GCoordinationItemMessagesReq(
              (b) => b.vars
                ..itemId = itemId
                ..limit = limit
                ..before = before,
            ),
          )
          .firstWhere((e) => e.dataSource == DataSource.Link)
          .then((r) => r
              .dataOrThrow(label: _label)
              .coordinationItemMessages
              .map((e) => (e as CoordinationItemMessageListModel).toEntity())
              .toList());

  Future<CoordinationItem> updatePlan({
    required String beaconId,
    required String title,
    String? body,
    String? linkedMessageId,
  }) =>
      _remote
          .request(
            GCoordinationItemUpdatePlanReq(
              (b) => b.vars
                ..beaconId = beaconId
                ..title = title
                ..body = body
                ..linkedMessageId = linkedMessageId,
            ),
          )
          .firstWhere((e) => e.dataSource == DataSource.Link)
          .then((r) => (r.dataOrThrow(label: _label).updateCoordinationPlan
                  as CoordinationItemUpdatePlanModel)
              .toEntity());

  Future<CoordinationItem> addPlanStep({
    required String parentItemId,
    required String title,
    String? body,
  }) =>
      _remote
          .request(
            GCoordinationItemAddPlanStepReq(
              (b) => b.vars
                ..parentItemId = parentItemId
                ..title = title
                ..body = body,
            ),
          )
          .firstWhere((e) => e.dataSource == DataSource.Link)
          .then((r) => (r.dataOrThrow(label: _label).addPlanStep
                  as CoordinationItemAddPlanStepModel)
              .toEntity());

  Future<CoordinationItem> resolvePlanStep({required String itemId}) =>
      _remote
          .request(
            GCoordinationItemResolvePlanStepReq((b) => b.vars..itemId = itemId),
          )
          .firstWhere((e) => e.dataSource == DataSource.Link)
          .then((r) => (r.dataOrThrow(label: _label).resolvePlanStep
                  as CoordinationItemResolvePlanStepModel)
              .toEntity());

  Future<CoordinationItem> createResolution({
    required String beaconId,
    required String title,
    String? body,
    String? targetItemId,
    String? targetMessageId,
    String? linkedMessageId,
  }) =>
      _remote
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
          .then((r) => (r.dataOrThrow(label: _label).createResolution
                  as CoordinationItemCreateResolutionModel)
              .toEntity());

  Future<CoordinationItem> acceptResolution({required String itemId}) =>
      _remote
          .request(
            GCoordinationItemAcceptResolutionReq((b) => b.vars..itemId = itemId),
          )
          .firstWhere((e) => e.dataSource == DataSource.Link)
          .then((r) => (r.dataOrThrow(label: _label).acceptResolution
                  as CoordinationItemAcceptResolutionModel)
              .toEntity());

  Future<CoordinationItem> rejectResolution({
    required String itemId,
    String? reason,
  }) =>
      _remote
          .request(
            GCoordinationItemRejectResolutionReq(
              (b) => b.vars
                ..itemId = itemId
                ..reason = reason,
            ),
          )
          .firstWhere((e) => e.dataSource == DataSource.Link)
          .then((r) => (r.dataOrThrow(label: _label).rejectResolution
                  as CoordinationItemRejectResolutionModel)
              .toEntity());

  Future<CoordinationItemMessage> appendMessage({
    required String itemId,
    required String body,
  }) =>
      _remote
          .request(
            GCoordinationItemAppendMessageReq(
              (b) => b.vars
                ..itemId = itemId
                ..body = body,
            ),
          )
          .firstWhere((e) => e.dataSource == DataSource.Link)
          .then((r) =>
              (r.dataOrThrow(label: _label).appendCoordinationItemMessage
                      as CoordinationItemAppendMessageModel)
                  .toEntity());

  Future<void> markSeen({required String itemId}) async {
    await _remote
        .request(
          GCoordinationItemMarkSeenReq((b) => b.vars.itemId = itemId),
        )
        .firstWhere((e) => e.dataSource == DataSource.Link)
        .then((r) => r.dataOrThrow(label: _label).markCoordinationItemSeen);
  }
}
