import 'package:injectable/injectable.dart';
import 'package:drift_postgres/drift_postgres.dart';

import 'package:tentura_server/consts/beacon_activity_event_consts.dart';
import 'package:tentura_server/consts/beacon_fact_card_consts.dart';
import 'package:tentura_server/consts/beacon_room_consts.dart';
import 'package:tentura_server/domain/entity/beacon_fact_card_entity.dart';
import 'package:tentura_server/utils/id.dart';

import '../database/tentura_db.dart';
import 'beacon_room_repository.dart';

@lazySingleton
class BeaconFactCardRepository {
  BeaconFactCardRepository(this._db, this._room);

  final TenturaDb _db;

  final BeaconRoomRepository _room;

  BeaconFactCardEntity _toEntity(BeaconFactCard row) => BeaconFactCardEntity(
        id: row.id,
        beaconId: row.beaconId,
        factText: row.factText,
        visibility: row.visibility,
        pinnedBy: row.pinnedBy,
        createdAt: row.createdAt.dateTime,
        sourceMessageId: row.sourceMessageId,
        status: row.status,
        updatedAt: row.updatedAt.dateTime,
      );

  Future<List<BeaconFactCardEntity>> listForBeacon(String beaconId) async {
    final rows = await _db.managers.beaconFactCards
        .filter((r) => r.beaconId.id(beaconId))
        .get();
    return [
      for (final row in rows)
        if (row.status != BeaconFactCardStatusBits.removed) _toEntity(row),
    ];
  }

  /// Latest active public fact line for inbox / forward strips.
  Future<String?> latestPublicFactSnippet(String beaconId) async {
    final rows = await _db.managers.beaconFactCards
        .filter(
          (r) =>
              r.beaconId.id(beaconId) &
              r.visibility.equals(BeaconFactCardVisibilityBits.public) &
              r.status.equals(BeaconFactCardStatusBits.active),
        )
        .get();
    if (rows.isEmpty) return null;
    var best = rows.first;
    for (final r in rows.skip(1)) {
      if (r.createdAt.dateTime.isAfter(best.createdAt.dateTime)) {
        best = r;
      }
    }
    final t = best.factText.trim();
    if (t.length > 160) {
      return '${t.substring(0, 157)}…';
    }
    return t;
  }

  /// Inserts a fact, optionally links [sourceMessageId], emits a system room line.
  Future<BeaconFactCardEntity> pinFact({
    required String beaconId,
    required String factText,
    required int visibility,
    required String pinnedBy,
    String? sourceMessageId,
  }) =>
      _db.withMutatingUser(pinnedBy, () async {
        final trimmed = factText.trim();
        if (trimmed.isEmpty) {
          throw ArgumentError('factText');
        }
        final id = generateId('F');
        final row = await _db.managers.beaconFactCards.createReturning(
          (o) => o(
            id: Value(id),
            beaconId: beaconId,
            factText: trimmed,
            visibility: visibility,
            pinnedBy: pinnedBy,
            sourceMessageId: Value(sourceMessageId),
            status: const Value(BeaconFactCardStatusBits.active),
            createdAt: const Value.absent(),
            updatedAt: Value(PgDateTime(DateTime.timestamp())),
          ),
        );
        if (sourceMessageId != null) {
          await _db.managers.beaconRoomMessages
              .filter((m) => m.id.equals(sourceMessageId))
              .update(
                (u) => u(linkedFactCardId: Value(row.id)),
              );
        }
        final roomMsg = await _room.insertRoomMessage(
          beaconId: beaconId,
          authorId: pinnedBy,
          body: '',
          semanticMarker:
              visibility == BeaconFactCardVisibilityBits.public
              ? BeaconRoomSemanticMarker.pinFactPublic
              : BeaconRoomSemanticMarker.pinFactPrivate,
          systemPayload: {
            'factCardId': row.id,
            'factText': trimmed,
          },
        );
        await _room.insertActivityEvent(
          beaconId: beaconId,
          visibility: visibility == BeaconFactCardVisibilityBits.public
              ? BeaconActivityEventVisibilityBits.public
              : BeaconActivityEventVisibilityBits.room,
          type: BeaconActivityEventTypeBits.factPinned,
          actorId: pinnedBy,
          sourceMessageId: sourceMessageId ?? roomMsg.id,
          diff: <String, Object?>{
            'factCardId': row.id,
            'factText': trimmed,
          },
        );
        return _toEntity(row);
      });

  Future<void> correct({
    required String factCardId,
    required String actorUserId,
    required String newText,
  }) =>
      _db.withMutatingUser(actorUserId, () async {
        final t = newText.trim();
        if (t.isEmpty) {
          throw ArgumentError('newText');
        }
        await _db.managers.beaconFactCards
            .filter((e) => e.id.equals(factCardId))
            .update(
              (u) => u(
                factText: Value(t),
                status: const Value(BeaconFactCardStatusBits.corrected),
                updatedAt: Value(PgDateTime(DateTime.timestamp())),
              ),
            );
      });

  Future<void> remove({
    required String factCardId,
    required String actorUserId,
  }) =>
      _db.withMutatingUser(actorUserId, () async {
        await _db.managers.beaconFactCards.filter((e) => e.id.equals(factCardId)).update(
              (u) => u(
                status: const Value(BeaconFactCardStatusBits.removed),
                updatedAt: Value(PgDateTime(DateTime.timestamp())),
              ),
            );
      });
}
