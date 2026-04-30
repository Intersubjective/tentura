import 'dart:async';

import 'package:injectable/injectable.dart';

import 'package:tentura_server/data/repository/beacon_fact_card_repository.dart';
import 'package:tentura_server/data/repository/beacon_room_repository.dart';
import 'package:tentura_server/data/service/beacon_room_push_service.dart';
import 'package:tentura_server/consts/beacon_fact_card_consts.dart';
import 'package:tentura_server/consts/beacon_room_consts.dart';
import 'package:tentura_server/domain/exception.dart';

import '_use_case_base.dart';

@Singleton(order: 2)
final class BeaconFactCardCase extends UseCaseBase {
  BeaconFactCardCase(
    this._facts,
    this._room,
    this._push, {
    required super.env,
    required super.logger,
  });

  final BeaconFactCardRepository _facts;

  final BeaconRoomRepository _room;

  final BeaconRoomPushService _push;

  Future<bool> _canUseRoom({
    required String beaconId,
    required String userId,
  }) async {
    if (await _room.isBeaconAuthor(beaconId: beaconId, userId: userId)) {
      return true;
    }
    if (await _room.isBeaconSteward(beaconId: beaconId, userId: userId)) {
      return true;
    }
    final p =
        await _room.findParticipant(beaconId: beaconId, userId: userId);
    return p?.roomAccess == RoomAccessBits.admitted;
  }

  Future<void> _ensureRoomAccess({
    required String beaconId,
    required String userId,
  }) async {
    final ok = await _canUseRoom(beaconId: beaconId, userId: userId);
    if (!ok) {
      throw const UnauthorizedException(
        description: 'Room access required',
      );
    }
  }

  Future<Map<String, Object?>> pin({
    required String beaconId,
    required String factText,
    required int visibility,
    required String userId,
    String? sourceMessageId,
  }) async {
    await _ensureRoomAccess(beaconId: beaconId, userId: userId);
    if (sourceMessageId != null) {
      final dup = await _facts.findNonRemovedBySourceMessage(
        beaconId: beaconId,
        sourceMessageId: sourceMessageId,
      );
      if (dup != null) {
        throw BeaconFactCardAlreadyPinnedException(
          existingFactCardId: dup.id,
        );
      }
    }
    final entity = await _facts.pinFact(
      beaconId: beaconId,
      factText: factText,
      visibility: visibility,
      pinnedBy: userId,
      sourceMessageId: sourceMessageId,
    );
    final isPub = visibility == BeaconFactCardVisibilityBits.public;
    final recipients = isPub
        ? await _room.listAllParticipantUserIds(beaconId)
        : await _room.listAdmittedUserIds(beaconId);
    unawaited(
      _push.notifyFactPinned(
        beaconId: beaconId,
        actorUserId: userId,
        isPublic: isPub,
        recipientUserIds: recipients,
      ),
    );
    return {'id': entity.id, 'beaconId': entity.beaconId};
  }

  Future<bool> correct({
    required String factCardId,
    required String beaconId,
    required String actorUserId,
    required String newText,
  }) async {
    await _ensureRoomAccess(beaconId: beaconId, userId: actorUserId);
    await _facts.correct(
      factCardId: factCardId,
      beaconId: beaconId,
      actorUserId: actorUserId,
      newText: newText,
    );
    return true;
  }

  Future<bool> remove({
    required String factCardId,
    required String beaconId,
    required String actorUserId,
  }) async {
    await _ensureRoomAccess(beaconId: beaconId, userId: actorUserId);
    await _facts.remove(
      factCardId: factCardId,
      beaconId: beaconId,
      actorUserId: actorUserId,
    );
    return true;
  }

  Future<bool> setVisibility({
    required String factCardId,
    required String beaconId,
    required String actorUserId,
    required int visibility,
  }) async {
    await _ensureRoomAccess(beaconId: beaconId, userId: actorUserId);
    await _facts.setVisibility(
      factCardId: factCardId,
      beaconId: beaconId,
      actorUserId: actorUserId,
      visibility: visibility,
    );
    return true;
  }

  Future<List<Map<String, Object?>>> list({
    required String beaconId,
    required String userId,
  }) async {
    final admitted = await _canUseRoom(beaconId: beaconId, userId: userId);
    final rows = await _facts.listForBeacon(beaconId);
    final sourceIdsForAttachments = <String>[
      for (final e in rows)
        if (e.sourceMessageId != null && e.sourceMessageId!.isNotEmpty)
          if (!(e.visibility == BeaconFactCardVisibilityBits.room && !admitted))
            e.sourceMessageId!,
    ];
    final attachmentsBySourceId =
        sourceIdsForAttachments.isEmpty
            ? <String, String>{}
            : await _room.attachmentsJsonByMessageIds(sourceIdsForAttachments);
    final pinnerIds = <String>{
      for (final e in rows)
        if (e.pinnedBy.isNotEmpty) e.pinnedBy,
    };
    final pinnedByTitles = pinnerIds.isEmpty
        ? <String, String>{}
        : await _room.userTitlesByIds(pinnerIds);
    final out = <Map<String, Object?>>[];
    for (final e in rows) {
      if (e.visibility == BeaconFactCardVisibilityBits.room && !admitted) {
        continue;
      }
      final smid = e.sourceMessageId;
      final attachmentsJson = smid != null && smid.isNotEmpty
          ? attachmentsBySourceId[smid] ?? '[]'
          : '[]';
      out.add(<String, Object?>{
        'id': e.id,
        'beaconId': e.beaconId,
        'factText': e.factText,
        'visibility': e.visibility,
        'pinnedBy': e.pinnedBy,
        'pinnedByTitle': pinnedByTitles[e.pinnedBy] ?? '',
        'sourceMessageId': e.sourceMessageId,
        'status': e.status,
        'createdAt': e.createdAt.toIso8601String(),
        'updatedAt': e.updatedAt?.toIso8601String(),
        'attachmentsJson': attachmentsJson,
      });
    }
    return out;
  }
}
