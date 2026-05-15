import 'package:injectable/injectable.dart';

import 'package:tentura/domain/entity/coordination_item.dart';
import 'package:tentura/domain/entity/coordination_item_message.dart';

import '../../data/repository/coordination_item_repository.dart';

@singleton
class CoordinationItemCase {
  const CoordinationItemCase(this._repository);

  final CoordinationItemRepository _repository;

  Future<List<CoordinationItem>> listByBeacon(
    String beaconId, {
    int? status,
    int? kind,
    String? acceptedById,
    String? targetPersonId,
  }) =>
      _repository.listByBeacon(
        beaconId,
        status: status,
        kind: kind,
        acceptedById: acceptedById,
        targetPersonId: targetPersonId,
      );

  Future<CoordinationItem> markBlocker({
    required String beaconId,
    required String title,
    String? body,
    String? linkedMessageId,
  }) =>
      _repository.markBlocker(
        beaconId: beaconId,
        title: title,
        body: body,
        linkedMessageId: linkedMessageId,
      );

  Future<CoordinationItem> resolveBlocker({required String itemId}) =>
      _repository.resolveBlocker(itemId: itemId);

  Future<CoordinationItem> cancelBlocker({required String itemId}) =>
      _repository.cancelBlocker(itemId: itemId);

  Future<CoordinationItem> markAsk({
    required String beaconId,
    required String title,
    required String targetPersonId,
    String? body,
    String? linkedMessageId,
  }) =>
      _repository.markAsk(
        beaconId: beaconId,
        title: title,
        targetPersonId: targetPersonId,
        body: body,
        linkedMessageId: linkedMessageId,
      );

  Future<CoordinationItem> acceptAsk({required String itemId}) =>
      _repository.acceptAsk(itemId: itemId);

  Future<CoordinationItem> resolveAsk({required String itemId, String? note}) =>
      _repository.resolveAsk(itemId: itemId, note: note);

  Future<CoordinationItem> cancelAsk({required String itemId, String? reason}) =>
      _repository.cancelAsk(itemId: itemId, reason: reason);

  Future<CoordinationItem> redirectAsk({
    required String itemId,
    required String newTargetPersonId,
  }) =>
      _repository.redirectAsk(
        itemId: itemId,
        newTargetPersonId: newTargetPersonId,
      );

  Future<List<CoordinationItemMessage>> listMessages(
    String itemId, {
    int? limit,
    String? before,
  }) =>
      _repository.listMessages(itemId, limit: limit, before: before);

  Future<CoordinationItemMessage> appendMessage({
    required String itemId,
    required String body,
  }) =>
      _repository.appendMessage(itemId: itemId, body: body);
}
