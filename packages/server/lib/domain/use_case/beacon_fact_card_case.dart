import 'package:injectable/injectable.dart';
import 'package:tentura_root/domain/entity/beacon_status.dart';

import 'package:tentura_server/domain/port/beacon_access_guard.dart';
import 'package:tentura_server/domain/port/beacon_fact_card_repository_port.dart';
import 'package:tentura_server/domain/port/beacon_hierarchy_repository_port.dart';
import 'package:tentura_server/domain/port/beacon_room_repository_port.dart';
import 'package:tentura_server/consts/beacon_fact_card_consts.dart';
import 'package:tentura_server/consts/beacon_room_consts.dart';
import 'package:tentura_server/domain/exception.dart';
import 'package:tentura_server/domain/policy/beacon_room_lifecycle_write_policy.dart';

import '_use_case_base.dart';

@Singleton(order: 2)
final class BeaconFactCardCase extends UseCaseBase {
  BeaconFactCardCase(
    this._facts,
    this._room,
    this._hierarchyRepository,
    // Kept for DI; list reads through the fused loadRoomAccess preflight.
    // ignore: avoid_unused_constructor_parameters
    BeaconAccessGuard guard, {
    required super.env,
    required super.logger,
  });

  final BeaconFactCardRepositoryPort _facts;

  final BeaconRoomRepositoryPort _room;

  final BeaconHierarchyRepositoryPort _hierarchyRepository;

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

  Future<void> _rejectOrdinaryUserWritesForLifecycle(String beaconId) async {
    final status = await _hierarchyRepository.loadBeaconStatus(beaconId);
    if (status != null &&
        BeaconRoomLifecycleWritePolicy.blocksOrdinaryUserWrites(status)) {
      throw const BeaconCreateException(
        description: 'Discussion is read-only for this request',
      );
    }
  }

  /// Fused `loadRoomAccess` preflight: room use plus lifecycle write check.
  Future<void> _ensureWritableRoomAccess({
    required String beaconId,
    required String userId,
  }) async {
    final access = await _facts.loadRoomAccess(
      beaconId: beaconId,
      userId: userId,
    );
    if (!access.exists || !access.canUseRoom) {
      throw const UnauthorizedException(
        description: 'Room access required',
      );
    }
    if (BeaconRoomLifecycleWritePolicy.blocksOrdinaryUserWrites(
      BeaconStatus.fromSmallint(access.beaconStatus),
    )) {
      throw const BeaconCreateException(
        description: 'Discussion is read-only for this request',
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
    final trimmed = factText.trim();
    if (trimmed.isEmpty) {
      throw const BeaconCreateException(description: 'Fact text is empty');
    }
    await _ensureWritableRoomAccess(beaconId: beaconId, userId: userId);
    final entity = await _facts.pinFact(
      beaconId: beaconId,
      factText: trimmed,
      visibility: visibility,
      pinnedBy: userId,
      sourceMessageId: sourceMessageId,
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
    await _rejectOrdinaryUserWritesForLifecycle(beaconId);
    // The GraphQL mutation does not carry a base seq yet, so edit against
    // the current one (last write wins, as before the rename).
    final facts = await _facts.listForBeacon(
      beaconId: beaconId,
      includeRoomOnly: true,
    );
    final baseRevisionSeq = facts
        .where((f) => f.id == factCardId)
        .map((f) => f.revisionSeq)
        .firstOrNull;
    await _facts.editText(
      factCardId: factCardId,
      beaconId: beaconId,
      actorUserId: actorUserId,
      newText: newText.trim(),
      baseRevisionSeq: baseRevisionSeq ?? 0,
      rateWindow: const Duration(seconds: 60),
      rateMax: 20,
      quietWindow: kFactEditQuietWindow,
    );
    return true;
  }

  Future<bool> remove({
    required String factCardId,
    required String beaconId,
    required String actorUserId,
  }) async {
    await _ensureRoomAccess(beaconId: beaconId, userId: actorUserId);
    await _rejectOrdinaryUserWritesForLifecycle(beaconId);
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
    await _ensureWritableRoomAccess(beaconId: beaconId, userId: actorUserId);
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
    final access = await _facts.loadRoomAccess(
      beaconId: beaconId,
      userId: userId,
    );
    if (!access.canReadContent) {
      throw const UnauthorizedException(
        description: 'Viewer cannot read request content',
      );
    }
    final rows = await _facts.listForBeacon(
      beaconId: beaconId,
      includeRoomOnly: access.canUseRoom,
    );
    final sourceIdsForAttachments = <String>[
      for (final e in rows)
        if (e.sourceMessageId != null && e.sourceMessageId!.isNotEmpty)
          e.sourceMessageId!,
    ];
    final attachmentsBySourceId =
        sourceIdsForAttachments.isEmpty
            ? <String, String>{}
            : await _room.attachmentsJsonByMessageIds(sourceIdsForAttachments);
    return [
      for (final e in rows)
        <String, Object?>{
          'id': e.id,
          'beaconId': e.beaconId,
          'factText': e.factText,
          'visibility': e.visibility,
          'pinnedBy': e.pinnedBy,
          'pinnedByTitle': e.pinnedByTitle,
          'sourceMessageId': e.sourceMessageId,
          'status': e.status,
          'createdAt': e.createdAt.toIso8601String(),
          'updatedAt': e.updatedAt?.toIso8601String(),
          'attachmentsJson': switch (e.sourceMessageId) {
            final smid? when smid.isNotEmpty =>
              attachmentsBySourceId[smid] ?? '[]',
            _ => '[]',
          },
          'revisionSeq': e.revisionSeq,
          'lastEditedBy': e.lastEditedBy,
          'lastEditedByTitle': e.lastEditedByTitle,
          'lastEditedAt': e.lastEditedAt?.toIso8601String(),
          'otherEditorCount': e.otherEditorCount,
          'historyTruncated': e.historyTruncated,
        },
    ];
  }
}
