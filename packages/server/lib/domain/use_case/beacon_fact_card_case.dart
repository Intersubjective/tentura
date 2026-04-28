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

  Future<bool> _isAuthorOrSteward({
    required String beaconId,
    required String userId,
  }) async {
    if (await _room.isBeaconAuthor(beaconId: beaconId, userId: userId)) {
      return true;
    }
    return _room.isBeaconSteward(beaconId: beaconId, userId: userId);
  }

  Future<Map<String, Object?>> pin({
    required String beaconId,
    required String factText,
    required int visibility,
    required String userId,
    String? sourceMessageId,
  }) async {
    final isPub = visibility == BeaconFactCardVisibilityBits.public;
    if (isPub) {
      final ok =
          await _isAuthorOrSteward(beaconId: beaconId, userId: userId);
      if (!ok) {
        throw const UnauthorizedException(
          description: 'Author or steward only for public facts',
        );
      }
    } else {
      final ok = await _canUseRoom(beaconId: beaconId, userId: userId);
      if (!ok) {
        throw const UnauthorizedException(
          description: 'Room access required to pin private fact',
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
    if (!await _isAuthorOrSteward(beaconId: beaconId, userId: actorUserId)) {
      throw const UnauthorizedException(description: 'Author or steward only');
    }
    await _facts.correct(
      factCardId: factCardId,
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
    if (!await _isAuthorOrSteward(beaconId: beaconId, userId: actorUserId)) {
      throw const UnauthorizedException(description: 'Author or steward only');
    }
    await _facts.remove(factCardId: factCardId, actorUserId: actorUserId);
    return true;
  }

  Future<List<Map<String, Object?>>> list({
    required String beaconId,
    required String userId,
  }) async {
    final admitted = await _canUseRoom(beaconId: beaconId, userId: userId);
    final rows = await _facts.listForBeacon(beaconId);
    final out = <Map<String, Object?>>[];
    for (final e in rows) {
      if (e.visibility == BeaconFactCardVisibilityBits.room && !admitted) {
        continue;
      }
      out.add(<String, Object?>{
        'id': e.id,
        'beaconId': e.beaconId,
        'factText': e.factText,
        'visibility': e.visibility,
        'pinnedBy': e.pinnedBy,
        'sourceMessageId': e.sourceMessageId,
        'status': e.status,
        'createdAt': e.createdAt.toIso8601String(),
        'updatedAt': e.updatedAt?.toIso8601String(),
      });
    }
    return out;
  }
}
