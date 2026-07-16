import 'package:tentura_server/domain/entity/coordination_item_record.dart';

import 'package:injectable/injectable.dart';

import 'package:tentura_server/domain/port/beacon_room_repository_port.dart';
import 'package:tentura_server/domain/port/beacon_room_notification_port.dart';
import 'package:tentura_server/domain/coordination_stale_rules.dart';
import 'package:tentura_server/domain/exception.dart';
import 'package:tentura_server/domain/port/coordination_item_repository_port.dart';
import 'package:tentura_server/domain/use_case/attention_intent_case.dart';
import 'package:tentura_server/domain/use_case/transactional_attention_case.dart';

import '../_use_case_base.dart';
import 'coordination_room_access.dart';

@Singleton(order: 2)
final class RemindCoordinationItemCase extends UseCaseBase {
  RemindCoordinationItemCase(
    this._itemRepository,
    this._roomRepository,
    BeaconRoomNotificationPort legacyNotificationPort, {
    AttentionIntentCase? attentionIntents,
    TransactionalAttentionCase? attention,
    required super.env,
    required super.logger,
  }) : _attentionIntents = attentionIntents,
       _attention = attention;

  final CoordinationItemRepositoryPort _itemRepository;
  final BeaconRoomRepositoryPort _roomRepository;
  final AttentionIntentCase? _attentionIntents;
  final TransactionalAttentionCase? _attention;

  Future<CoordinationItemRecord> call({
    required String userId,
    required String itemId,
  }) async {
    final existing = await _itemRepository.getById(itemId);
    if (existing == null) {
      throw const IdNotFoundException(
        description: 'Coordination item not found',
      );
    }
    if (!isRemindableKind(existing.kind)) {
      throw const BeaconCreateException(
        description: 'Only asks, promises, and blockers can be reminded',
      );
    }

    await ensureCanCoordinateOnBeacon(
      room: _roomRepository,
      beaconId: existing.beaconId,
      userId: userId,
    );

    final view = _toView(existing);
    if (!isItemStale(view, DateTime.timestamp().toUtc())) {
      throw const BeaconCreateException(
        description: 'Item is not stale yet',
      );
    }

    final responsible = resolveResponsibleUserId(view);
    if (responsible == null || responsible.isEmpty) {
      throw const BeaconCreateException(
        description: 'No one is responsible for this item',
      );
    }
    if (responsible == userId) {
      throw const BeaconCreateException(
        description: 'You cannot remind yourself',
      );
    }

    return _attention!.runAction(
      actorUserId: userId,
      action: (transaction) async {
        final claimed = await _itemRepository.tryClaimRemind(
          itemId: itemId,
          actorId: userId,
        );
        if (claimed == null) {
          throw const BeaconCreateException(
            description: 'Reminder was sent recently — try again later',
          );
        }

        final excerpt = claimed.title.trim().isNotEmpty
            ? claimed.title.trim()
            : claimed.body.trim();
        await transaction.record(
          await _attentionIntents!.staleReminder(
            beaconId: claimed.beaconId,
            actorUserId: userId,
            targetPersonId: responsible,
            coordinationItemId: claimed.id,
            excerpt: excerpt,
            sourceEventKey: _sourceKey(claimed),
          ),
        );
        return claimed;
      },
    );
  }

  String _sourceKey(CoordinationItemRecord item) =>
      'coordination_item:${item.id}:reminded:'
      '${item.lastRemindedAt?.toUtc().microsecondsSinceEpoch ?? item.updatedAt.toUtc().microsecondsSinceEpoch}';

  CoordinationStaleItemView _toView(CoordinationItemRecord item) =>
      CoordinationStaleItemView(
        kind: item.kind,
        status: item.status,
        creatorId: item.creatorId,
        targetPersonId: item.targetPersonId,
        acceptedById: item.acceptedById,
        staleAt: item.staleAt?.toUtc(),
        staleAfterDays: item.staleAfterDays,
      );
}
