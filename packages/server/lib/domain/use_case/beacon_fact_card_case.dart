import 'package:injectable/injectable.dart';
import 'package:tentura_root/domain/entity/beacon_status.dart';

import 'package:tentura_server/domain/entity/beacon_fact_card_outcome.dart';
import 'package:tentura_server/domain/entity/beacon_fact_history_entry_entity.dart';
import 'package:tentura_server/domain/port/beacon_access_guard.dart';
import 'package:tentura_server/domain/port/beacon_fact_card_repository_port.dart';
import 'package:tentura_server/domain/port/beacon_hierarchy_repository_port.dart';
import 'package:tentura_server/domain/port/beacon_room_repository_port.dart';
import 'package:tentura_server/consts/beacon_fact_card_consts.dart';
import 'package:tentura_server/domain/exception.dart';
import 'package:tentura_server/domain/policy/beacon_room_lifecycle_write_policy.dart';

import '_use_case_base.dart';

@Singleton(order: 2)
final class BeaconFactCardCase extends UseCaseBase {
  BeaconFactCardCase(
    this._facts,
    this._room,
    // Kept for DI; writes and list go through the fused loadRoomAccess
    // preflight.
    // ignore: avoid_unused_constructor_parameters
    BeaconHierarchyRepositoryPort hierarchyRepository,
    // Kept for DI, same as the hierarchy port above.
    // ignore: avoid_unused_constructor_parameters
    BeaconAccessGuard guard, {
    required super.env,
    required super.logger,
  });

  final BeaconFactCardRepositoryPort _facts;

  final BeaconRoomRepositoryPort _room;

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

  /// Edits the fact text against the caller's [baseRevisionSeq]; returns
  /// the resulting head seq.
  Future<int> correct({
    required String factCardId,
    required String beaconId,
    required String actorUserId,
    required String newText,
    required int baseRevisionSeq,
  }) async {
    final trimmed = newText.trim();
    if (trimmed.isEmpty) {
      throw const BeaconCreateException(description: 'Fact text is empty');
    }
    await _ensureWritableRoomAccess(beaconId: beaconId, userId: actorUserId);
    return _seqOrThrow(
      await _facts.editText(
        factCardId: factCardId,
        beaconId: beaconId,
        actorUserId: actorUserId,
        newText: trimmed,
        baseRevisionSeq: baseRevisionSeq,
        rateWindow: env.factEditRateWindow,
        rateMax: env.factEditRateMax,
        quietWindow: kFactEditQuietWindow,
      ),
      factCardId: factCardId,
    );
  }

  /// Restores the text of revision [fromSeq] as a new head revision; returns
  /// the resulting head seq.
  Future<int> restore({
    required String factCardId,
    required String beaconId,
    required String actorUserId,
    required int fromSeq,
    required int baseRevisionSeq,
  }) async {
    await _ensureWritableRoomAccess(beaconId: beaconId, userId: actorUserId);
    return _seqOrThrow(
      await _facts.restoreRevision(
        factCardId: factCardId,
        beaconId: beaconId,
        actorUserId: actorUserId,
        fromSeq: fromSeq,
        baseRevisionSeq: baseRevisionSeq,
        rateWindow: env.factEditRateWindow,
        rateMax: env.factEditRateMax,
        quietWindow: kFactEditQuietWindow,
      ),
      factCardId: factCardId,
    );
  }

  /// Plan §14.5 outcome → result/exception map.
  int _seqOrThrow(FactEditOutcome outcome, {required String factCardId}) =>
      switch (outcome) {
        FactEditApplied(:final newSeq) => newSeq,
        FactEditNoOp(:final currentSeq) => currentSeq,
        FactEditNotFound() => throw IdNotFoundException(id: factCardId),
        FactEditRemoved() => throw const BeaconFactCardRemovedException(),
        FactEditRateLimited() =>
          throw const BeaconFactCardRateLimitedException(),
        FactEditConflict(:final currentSeq) =>
          throw BeaconFactCardEditConflictException(currentSeq: currentSeq),
        FactRestoreSourceMissing() => throw IdWrongException(
          id: factCardId,
          description: 'Fact card revision not found',
        ),
      };

  Future<bool> remove({
    required String factCardId,
    required String beaconId,
    required String actorUserId,
  }) async {
    await _ensureWritableRoomAccess(beaconId: beaconId, userId: actorUserId);
    return _facts.remove(
      factCardId: factCardId,
      beaconId: beaconId,
      actorUserId: actorUserId,
    );
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

  /// Plan §8.4 / §8.11, D1: read-only fact timeline page. Gates on
  /// `canUseRoom` (members only), not `list()`'s `canReadContent`. [before]
  /// is the opaque `'<iso8601UTC>|<entry_key>'` cursor from a prior page's
  /// `nextCursor`.
  Future<({List<BeaconFactHistoryEntry> entries, String? nextCursor})>
  history({
    required String factCardId,
    required String beaconId,
    required String userId,
    String? before,
  }) async {
    final parsedBefore = _parseHistoryCursor(before, factCardId: factCardId);

    final access = await _facts.loadRoomAccess(
      beaconId: beaconId,
      userId: userId,
    );
    if (!access.exists || !access.canUseRoom) {
      throw const UnauthorizedException(
        description: 'Room access required',
      );
    }

    final rows = await _facts.history(
      factCardId: factCardId,
      before: parsedBefore,
    );
    final entries = rows.take(kFactHistoryPageSize).toList();
    return (
      entries: entries,
      nextCursor: rows.length > kFactHistoryPageSize
          ? _serializeHistoryCursor(entries.last)
          : null,
    );
  }

  /// Parses the opaque cursor into the port's keyset `before` argument;
  /// throws `IdWrongException` on any malformed input.
  ({DateTime createdAt, String entryKey})? _parseHistoryCursor(
    String? cursor, {
    required String factCardId,
  }) {
    if (cursor == null) return null;
    final sep = cursor.indexOf('|');
    final createdAt = sep < 0
        ? null
        : DateTime.tryParse(cursor.substring(0, sep));
    final entryKey = sep < 0 ? '' : cursor.substring(sep + 1);
    if (createdAt == null || entryKey.isEmpty) {
      throw IdWrongException(id: factCardId);
    }
    return (createdAt: createdAt, entryKey: entryKey);
  }

  String _serializeHistoryCursor(BeaconFactHistoryEntry entry) =>
      '${entry.createdAt.toUtc().toIso8601String()}|${_historyEntryKey(entry)}';

  /// Mirrors the repository's `entry_key` convention (§14.3): `'r' ||
  /// lpad(seq, 10)` for revisions, `'e' || id` for events. `BeaconFactHistoryEvent`
  /// carries no persisted event id, so a page boundary landing on an event
  /// row cannot yet be serialised into a round-trippable cursor.
  String _historyEntryKey(BeaconFactHistoryEntry entry) => switch (entry) {
    BeaconFactHistoryRevision(:final seq) =>
      'r${seq.toString().padLeft(10, '0')}',
    BeaconFactHistoryEvent() => throw UnimplementedError(
      'nextCursor cannot be serialised for an event-row page boundary: '
      'BeaconFactHistoryEvent does not carry a persisted event id',
    ),
  };
}
