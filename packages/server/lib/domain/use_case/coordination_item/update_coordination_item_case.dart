import 'package:injectable/injectable.dart';
import 'package:tentura_server/domain/entity/coordination_item_record.dart';

import 'package:tentura_server/consts/coordination_item_consts.dart';
import 'package:tentura_server/domain/port/beacon_room_repository_port.dart';
import 'package:tentura_server/domain/exception.dart';
import 'package:tentura_server/domain/port/beacon_repository_port.dart';
import 'package:tentura_server/domain/port/coordination_item_repository_port.dart';
import 'package:tentura_server/domain/use_case/attention_intent_case.dart';
import 'package:tentura_server/domain/use_case/transactional_attention_case.dart';

import '../_use_case_base.dart';

@Singleton(order: 2)
final class UpdateCoordinationItemCase extends UseCaseBase {
  UpdateCoordinationItemCase(
    this._beaconRepository,
    this._itemRepository,
    this._roomRepository, {
    AttentionIntentCase? attentionIntents,
    TransactionalAttentionCase? attention,
    required super.env,
    required super.logger,
  }) : _attentionIntents = attentionIntents,
       _attention = attention;

  final BeaconRepositoryPort _beaconRepository;
  final CoordinationItemRepositoryPort _itemRepository;
  final BeaconRoomRepositoryPort _roomRepository;
  final AttentionIntentCase? _attentionIntents;
  final TransactionalAttentionCase? _attention;

  Future<CoordinationItemRecord> call({
    required String userId,
    required String itemId,
    required String title,
    String body = '',
  }) async {
    final trimmed = title.trim();
    if (trimmed.isEmpty) {
      throw const BeaconCreateException(description: 'Title is required');
    }
    final existing = await _itemRepository.getById(itemId);
    if (existing == null) {
      throw const IdNotFoundException(description: 'Item not found');
    }
    if (!existing.published) {
      throw const BeaconCreateException(
        description: 'Use updateDraftAsk for unpublished asks',
      );
    }
    if (existing.status != coordinationItemStatusOpen &&
        existing.status != coordinationItemStatusAccepted) {
      throw const BeaconCreateException(description: 'Item is not editable');
    }
    final beacon =
        await _beaconRepository.getBeaconById(beaconId: existing.beaconId);
    if (!beacon.allowsCoordination) {
      throw const BeaconCreateException(description: 'Request is not open');
    }
    if (!await _canEditItem(
      beaconId: existing.beaconId,
      userId: userId,
      creatorId: existing.creatorId,
    )) {
      throw const UnauthorizedException(
        description: 'Not allowed to edit this item',
      );
    }
    final contentChanged = trimmed != existing.title.trim();
    return _attention!.runAction(
      actorUserId: userId,
      action: (transaction) async {
        final updated = await _itemRepository.updatePublishedItem(
          id: itemId,
          actorId: userId,
          title: trimmed,
          body: '',
        );
        if (contentChanged) {
          await transaction.record(
            await _attentionIntents!.coordinationChanged(
              beaconId: updated.beaconId,
              actorUserId: userId,
              planExcerpt: trimmed,
              beaconTitle: beacon.title,
              sourceEventKey: _sourceKey(updated, 'item_updated'),
            ),
          );
        }
        return updated;
      },
    );
  }

  Future<bool> _canEditItem({
    required String beaconId,
    required String userId,
    required String creatorId,
  }) async {
    if (userId == creatorId) {
      return true;
    }
    if (await _roomRepository.isBeaconAuthor(beaconId: beaconId, userId: userId)) {
      return true;
    }
    if (await _roomRepository.isBeaconSteward(beaconId: beaconId, userId: userId)) {
      return true;
    }
    return false;
  }

  String _sourceKey(CoordinationItemRecord item, String transition) =>
      'coordination_item:${item.id}:$transition:'
      '${item.updatedAt.toUtc().microsecondsSinceEpoch}';
}
