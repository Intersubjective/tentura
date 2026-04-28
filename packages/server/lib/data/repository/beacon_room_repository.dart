import 'dart:convert';

import 'package:injectable/injectable.dart';
import 'package:drift_postgres/drift_postgres.dart';

import 'package:tentura_server/consts/beacon_blocker_consts.dart';
import 'package:tentura_server/consts/beacon_participant_status_bits.dart';
import 'package:tentura_server/consts/beacon_room_consts.dart';
import 'package:tentura_server/domain/entity/beacon_activity_event_entity.dart';
import 'package:tentura_server/domain/entity/beacon_blocker_entity.dart';
import 'package:tentura_server/utils/id.dart';

import '../database/tentura_db.dart';

/// Beacon Room messages + participants — Postgres via Drift.
@lazySingleton
class BeaconRoomRepository {
  const BeaconRoomRepository(this._db);

  final TenturaDb _db;

  Future<List<BeaconRoomMessage>> listMessages({
    required String beaconId,
    DateTime? before,
    int limit = 50,
  }) async {
    if (before == null) {
      return (_db.select(_db.beaconRoomMessages)
            ..where((m) => m.beaconId.equals(beaconId))
            ..orderBy([
              (m) => OrderingTerm(
                    expression: m.createdAt,
                    mode: OrderingMode.desc,
                  ),
            ])
            ..limit(limit))
          .get();
    }
    return (_db.select(_db.beaconRoomMessages)
          ..where((m) =>
              m.beaconId.equals(beaconId) &
              m.createdAt.isSmallerThanValue(PgDateTime(before)))
          ..orderBy([
            (m) =>
                OrderingTerm(expression: m.createdAt, mode: OrderingMode.desc),
          ])
          ..limit(limit))
        .get();
  }

  Future<BeaconRoomMessage> insertRoomMessage({
    required String beaconId,
    required String authorId,
    required String body,
    String? replyToMessageId,
    String? linkedParticipantId,
    int? semanticMarker,
    Map<String, Object?>? systemPayload,
  }) =>
      _db.withMutatingUser(authorId, () async {
        final id = generateId('R');
        return _db.managers.beaconRoomMessages.createReturning((o) => o(
              id: id,
              beaconId: beaconId,
              authorId: authorId,
              body: Value(body),
              replyToMessageId: Value(replyToMessageId),
              linkedBlockerId: const Value.absent(),
              linkedNextMoveId: Value(linkedParticipantId),
              linkedFactCardId: const Value.absent(),
              semanticMarker: Value(semanticMarker),
              systemPayload: Value(systemPayload),
              createdAt: const Value.absent(),
            ));
      });

  Future<void> updateParticipantNextMoveFields({
    required String actorUserId,
    required String participantRowId,
    required String nextMoveText,
    required int nextMoveSource,
    int? nextMoveStatus,
  }) =>
      _db.withMutatingUser(actorUserId, () async {
        await _db.managers.beaconParticipants
            .filter((r) => r.id.equals(participantRowId))
            .update(
              (o) => o(
                nextMoveText: Value(nextMoveText),
                nextMoveSource: Value(nextMoveSource),
                nextMoveStatus: Value(nextMoveStatus),
                updatedAt: Value(PgDateTime(DateTime.timestamp())),
              ),
            );
      });

  Future<BeaconParticipant?> findParticipant({
    required String beaconId,
    required String userId,
  }) =>
      _db.managers.beaconParticipants
          .filter((r) => r.beaconId.id(beaconId) & r.userId.id(userId))
          .getSingleOrNull();

  Future<List<BeaconParticipant>> listParticipants(String beaconId) =>
      _db.managers.beaconParticipants
          .filter((r) => r.beaconId.id(beaconId))
          .get();

  Future<void> participantOfferHelp({
    required String beaconId,
    required String userId,
    required String note,
  }) =>
      _db.withMutatingUser(userId, () async {
        final existing = await findParticipant(
          beaconId: beaconId,
          userId: userId,
        );
        if (existing == null) {
          await _db.managers.beaconParticipants.create(
            (o) => o(
              createdAt: const Value.absent(),
              updatedAt: const Value.absent(),
              id: generateId('P'),
              beaconId: beaconId,
              userId: userId,
              role: BeaconParticipantRoleBits.helper,
              status: const Value(BeaconParticipantStatusBits.offeredHelp),
              roomAccess:
                  const Value(RoomAccessBits.requested),
              offerNote: Value(note),
            ),
          );
        } else {
          await _db.managers.beaconParticipants
              .filter(
                (r) => r.beaconId.id(beaconId) & r.userId.id(userId),
              )
              .update(
                (o) => o(
                  status: Value(BeaconParticipantStatusBits.offeredHelp),
                  roomAccess: const Value(RoomAccessBits.requested),
                  offerNote: Value(note),
                  updatedAt: Value(PgDateTime(DateTime.timestamp())),
                ),
              );
        }
      });

  Future<void> admitParticipant({
    required String beaconId,
    required String participantUserId,
    required String actorUserId,
  }) =>
      _db.withMutatingUser(actorUserId, () async {
        await _db.managers.beaconParticipants
            .filter(
              (r) => r.beaconId.id(beaconId) & r.userId.id(participantUserId),
            )
            .update(
              (o) => o(
                roomAccess:
                    const Value(RoomAccessBits.admitted),
                status: Value(BeaconParticipantStatusBits.committed),
                updatedAt: Value(PgDateTime(DateTime.timestamp())),
              ),
            );
      });

  Future<void> setBeaconSteward({
    required String beaconId,
    required String stewardUserId,
    required String authorUserId,
  }) =>
      _db.withMutatingUser(authorUserId, () async {
        await _db.into(_db.beaconStewards).insertOnConflictUpdate(
              BeaconStewardsCompanion.insert(
                beaconId: beaconId,
                userId: stewardUserId,
              ),
            );
        await _db.managers.beaconParticipants
            .filter(
              (r) => r.beaconId.id(beaconId) & r.userId.id(stewardUserId),
            )
            .update(
              (o) => o(
                role: const Value(BeaconParticipantRoleBits.steward),
                updatedAt: Value(PgDateTime(DateTime.timestamp())),
              ),
            );
      });

  Future<void> toggleReaction({
    required String messageId,
    required String userId,
    required String emoji,
  }) =>
      _db.withMutatingUser(userId, () async {
        final existing = await _db.managers.beaconRoomMessageReactions
            .filter(
              (r) =>
                  r.messageId.id(messageId) &
                  r.userId.id(userId) &
                  r.emoji.equals(emoji),
            )
            .getSingleOrNull();
        if (existing != null) {
          await _db.managers.beaconRoomMessageReactions
              .filter((r) => r.id.equals(existing.id))
              .delete();
        } else {
          await _db.managers.beaconRoomMessageReactions.create(
            (o) => o(
              id: generateId('E'),
              messageId: messageId,
              userId: userId,
              emoji: emoji,
              createdAt: const Value.absent(),
            ),
          );
        }
      });

  Future<bool> isBeaconAuthor({
    required String beaconId,
    required String userId,
  }) async {
    final b = await _db.managers.beacons
        .filter((e) => e.id.equals(beaconId))
        .getSingleOrNull();
    return b?.userId == userId;
  }

  Future<bool> isBeaconSteward({
    required String beaconId,
    required String userId,
  }) =>
      _db.managers.beaconStewards
          .filter(
            (s) => s.beaconId.id(beaconId) & s.userId.id(userId),
          )
          .getSingleOrNull()
          .then((r) => r != null);

  Future<BeaconRoomState?> getBeaconRoomState(String beaconId) =>
      _db.managers.beaconRoomStates
          .filter((e) => e.beaconId.id(beaconId))
          .getSingleOrNull();

  Future<String?> getBlockerTitle(String blockerId) =>
      _db.managers.beaconBlockers
          .filter((b) => b.id.equals(blockerId))
          .getSingleOrNull()
          .then((r) => r?.title);

  Future<void> markParticipantRoomSeen({
    required String beaconId,
    required String userId,
  }) =>
      _db.withMutatingUser(userId, () async {
        final p = await findParticipant(
          beaconId: beaconId,
          userId: userId,
        );
        if (p == null) {
          return;
        }
        await _db.managers.beaconParticipants
            .filter((r) => r.id.equals(p.id))
            .update(
              (u) => u(
                lastSeenRoomAt:
                    Value(PgDateTime(DateTime.timestamp())),
                updatedAt: Value(PgDateTime(DateTime.timestamp())),
              ),
            );
      });

  /// Upserts coordinated plan text (`beacon_room_state.current_plan`).
  Future<void> upsertBeaconRoomPlan({
    required String beaconId,
    required String currentPlan,
    required String updatedByUserId,
  }) =>
      _db.withMutatingUser(updatedByUserId, () async {
        final plan = currentPlan.trim();
        await _db.into(_db.beaconRoomStates).insertOnConflictUpdate(
              BeaconRoomStatesCompanion.insert(
                beaconId: beaconId,
                currentPlan: Value(plan),
                updatedBy: Value(updatedByUserId),
                updatedAt: Value(PgDateTime(DateTime.timestamp())),
              ),
            );
      });

  Future<BeaconRoomMessage?> getRoomMessageById(String messageId) =>
      _db.managers.beaconRoomMessages
          .filter((m) => m.id.equals(messageId))
          .getSingleOrNull();

  /// Opens a blocker tied to [openedFromMessageId], updates message + NOW strip pointer.
  Future<String> insertBlockerOpen({
    required String beaconId,
    required String title,
    required int visibility,
    required String openedBy,
    String? openedFromMessageId,
    String? affectedParticipantId,
    String? resolverParticipantId,
  }) =>
      _db.withMutatingUser(openedBy, () async {
        final t = title.trim();
        if (t.isEmpty) {
          throw ArgumentError('title');
        }
        final blockerId = BeaconBlockerEntity.newId;
        await _db.managers.beaconBlockers.create(
          (o) => o(
            id: Value(blockerId),
            beaconId: beaconId,
            title: t,
            status: Value(BeaconBlockerStatusBits.open),
            visibility: Value(visibility),
            openedBy: openedBy,
            openedFromMessageId: Value(openedFromMessageId),
            affectedParticipantId: Value(affectedParticipantId),
            resolverParticipantId: Value(resolverParticipantId),
            resolvedBy: const Value.absent(),
            resolvedFromMessageId: const Value.absent(),
            resolvedAt: const Value.absent(),
            createdAt: const Value.absent(),
          ),
        );
        final roomState = await getBeaconRoomState(beaconId);
        if (roomState == null) {
          await _db.into(_db.beaconRoomStates).insert(
                BeaconRoomStatesCompanion.insert(
                  beaconId: beaconId,
                  currentPlan: const Value(''),
                  openBlockerId: Value(blockerId),
                  lastRoomMeaningfulChange: const Value.absent(),
                  updatedAt: Value(PgDateTime(DateTime.timestamp())),
                  updatedBy: Value(openedBy),
                ),
              );
        } else {
          await _db.managers.beaconRoomStates
              .filter((s) => s.beaconId.id(beaconId))
              .update(
                (u) => u(
                  openBlockerId: Value(blockerId),
                  updatedAt: Value(PgDateTime(DateTime.timestamp())),
                  updatedBy: Value(openedBy),
                ),
              );
        }
        if (openedFromMessageId != null) {
          await _db.managers.beaconRoomMessages
              .filter((m) => m.id.equals(openedFromMessageId))
              .update(
                (u) => u(
                  linkedBlockerId: Value(blockerId),
                  semanticMarker:
                      Value(BeaconRoomSemanticMarker.blocker),
                ),
              );
        }
        return blockerId;
      });

  Future<void> resolveBlocker({
    required String blockerId,
    required String resolvedByUserId,
    String? resolvedFromMessageId,
  }) =>
      _db.withMutatingUser(resolvedByUserId, () async {
        await _db.managers.beaconBlockers.filter((b) => b.id.equals(blockerId)).update(
              (u) => u(
                status: Value(BeaconBlockerStatusBits.resolved),
                resolvedBy: Value(resolvedByUserId),
                resolvedFromMessageId: Value(resolvedFromMessageId),
                resolvedAt: Value(PgDateTime(DateTime.timestamp())),
              ),
            );
        await _db.managers.beaconRoomStates
            .filter((s) => s.openBlockerId.id(blockerId))
            .update(
              (u) => u(
                openBlockerId: const Value(null),
                updatedAt: Value(PgDateTime(DateTime.timestamp())),
                updatedBy: Value(resolvedByUserId),
              ),
            );
      });

  Future<void> markRoomMessageSemanticDone({
    required String messageId,
    required String actingUserId,
  }) =>
      _db.withMutatingUser(actingUserId, () async {
        await _db.managers.beaconRoomMessages
            .filter((m) => m.id.equals(messageId))
            .update(
              (u) => u(
                semanticMarker: Value(BeaconRoomSemanticMarker.done),
              ),
            );
      });

  Future<void> setParticipantNeedsInfo({
    required String participantRowId,
    required String actingUserId,
    required String requestText,
    required String linkedMessageId,
  }) =>
      _db.withMutatingUser(actingUserId, () async {
        final trimmed = requestText.trim();
        if (trimmed.isEmpty) {
          throw ArgumentError('requestText');
        }
        await _db.managers.beaconParticipants
            .filter((r) => r.id.equals(participantRowId))
            .update(
              (u) => u(
                status: Value(BeaconParticipantStatusBits.needsInfo),
                nextMoveText: Value(trimmed),
                nextMoveStatus:
                    Value(BeaconNextMoveStatusBits.requested),
                nextMoveSource:
                    Value(BeaconNextMoveSourceBits.stewardOrAuthor),
                linkedMessageId: Value(linkedMessageId),
                updatedAt: Value(PgDateTime(DateTime.timestamp())),
              ),
            );
      });

  /// Audit row for the Activity tab / timeline (Phase 5).
  Future<void> insertActivityEvent({
    required String beaconId,
    required int visibility,
    required int type,
    required String actorId,
    String? targetUserId,
    String? sourceMessageId,
    Map<String, Object?>? diff,
  }) =>
      _db.withMutatingUser(actorId, () async {
        await _db.managers.beaconActivityEvents.create(
          (o) => o(
            id: Value(BeaconActivityEventEntity.newId),
            beaconId: beaconId,
            visibility: visibility,
            type: type,
            actorId: Value(actorId),
            targetUserId: Value(targetUserId),
            sourceMessageId: Value(sourceMessageId),
            diff: Value(diff),
            createdAt: const Value.absent(),
          ),
        );
      });

  Future<List<Map<String, Object?>>> listActivityEvents({
    required String beaconId,
    int limit = 200,
  }) async {
    final rows = await (_db.select(_db.beaconActivityEvents)
          ..where((e) => e.beaconId.equals(beaconId))
          ..orderBy([
            (e) =>
                OrderingTerm(expression: e.createdAt, mode: OrderingMode.desc),
          ])
          ..limit(limit))
        .get();
    return rows
        .map(
          (r) => <String, Object?>{
            'id': r.id,
            'beaconId': r.beaconId,
            'visibility': r.visibility,
            'type': r.type,
            'actorId': r.actorId,
            'targetUserId': r.targetUserId,
            'sourceMessageId': r.sourceMessageId,
            'diffJson': r.diff == null ? null : jsonEncode(r.diff),
            'createdAt': r.createdAt.dateTime.toUtc().toIso8601String(),
          },
        )
        .toList();
  }

  Future<String?> beaconAuthorUserId(String beaconId) async {
    final b =
        await _db.managers.beacons
            .filter((e) => e.id.equals(beaconId))
            .getSingleOrNull();
    return b?.userId;
  }

  Future<List<String>> listStewardUserIds(String beaconId) async {
    final rows = await _db.managers.beaconStewards
        .filter((s) => s.beaconId.id(beaconId))
        .get();
    return rows.map((r) => r.userId).toList();
  }

  Future<List<String>> listAdmittedUserIds(String beaconId) async {
    final rows = await listParticipants(beaconId);
    return rows
        .where((p) => p.roomAccess == RoomAccessBits.admitted)
        .map((p) => p.userId)
        .toList();
  }

  Future<List<String>> listAllParticipantUserIds(String beaconId) async {
    final rows = await listParticipants(beaconId);
    return rows.map((p) => p.userId).toSet().toList();
  }

  Future<String?> participantUserIdForRow(String participantRowId) async {
    final p = await _db.managers.beaconParticipants
        .filter((r) => r.id.equals(participantRowId))
        .getSingleOrNull();
    return p?.userId;
  }

  /// Blocker opened: involved participants first; else beacon author + stewards.
  Future<Set<String>> blockerOpenedNotifyUserIds({
    required String beaconId,
    required String openedByUserId,
    String? affectedParticipantId,
    String? resolverParticipantId,
  }) async {
    final out = <String>{};
    if (affectedParticipantId != null && affectedParticipantId.isNotEmpty) {
      final u = await participantUserIdForRow(affectedParticipantId);
      if (u != null) {
        out.add(u);
      }
    }
    if (resolverParticipantId != null && resolverParticipantId.isNotEmpty) {
      final u = await participantUserIdForRow(resolverParticipantId);
      if (u != null) {
        out.add(u);
      }
    }
    if (out.isEmpty) {
      final author = await beaconAuthorUserId(beaconId);
      if (author != null && author.isNotEmpty) {
        out.add(author);
      }
      out.addAll(await listStewardUserIds(beaconId));
    }
    out.remove(openedByUserId);
    return out;
  }

  /// Blocker resolved: opened-by + involved participants (excluding resolver).
  Future<Set<String>> blockerResolvedNotifyUserIds({
    required String blockerId,
    required String resolvedByUserId,
  }) async {
    final blocker = await _db.managers.beaconBlockers
        .filter((b) => b.id.equals(blockerId))
        .getSingleOrNull();
    if (blocker == null) {
      return {};
    }
    final out = <String>{blocker.openedBy};
    final ap = blocker.affectedParticipantId;
    if (ap != null) {
      final u = await participantUserIdForRow(ap);
      if (u != null) {
        out.add(u);
      }
    }
    final rp = blocker.resolverParticipantId;
    if (rp != null) {
      final u = await participantUserIdForRow(rp);
      if (u != null) {
        out.add(u);
      }
    }
    out.remove(resolvedByUserId);
    return out;
  }

  /// Room messages created strictly after [after] (exclusive), for unread counts.
  Future<int> countRoomMessagesAfter({
    required String beaconId,
    DateTime? after,
  }) async {
    if (after == null) {
      final rows = await (_db.select(_db.beaconRoomMessages)
            ..where((m) => m.beaconId.equals(beaconId)))
          .get();
      return rows.length;
    }
    final rows = await (_db.select(_db.beaconRoomMessages)
          ..where(
            (m) =>
                m.beaconId.equals(beaconId) &
                m.createdAt.isBiggerThanValue(PgDateTime(after)),
          ))
        .get();
    return rows.length;
  }
}
