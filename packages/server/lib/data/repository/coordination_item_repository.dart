import 'package:injectable/injectable.dart';
import 'package:drift_postgres/drift_postgres.dart';

import 'package:tentura_server/consts/coordination_item_consts.dart';
import 'package:tentura_server/domain/entity/beacon_activity_event_entity.dart';
import 'package:tentura_server/domain/entity/coordination_item_entity.dart';
import 'package:tentura_server/domain/entity/coordination_item_message_entity.dart';
import 'package:tentura_server/domain/port/coordination_item_repository_port.dart';
import 'package:tentura_server/utils/id.dart';

import '../database/tentura_db.dart';

@LazySingleton(as: CoordinationItemRepositoryPort, order: 1)
class CoordinationItemRepository implements CoordinationItemRepositoryPort {
  const CoordinationItemRepository(this._db);

  final TenturaDb _db;

  @override
  Future<CoordinationItem> create({
    required String beaconId,
    required int kind,
    required String creatorId,
    required String title,
    String body = '',
    String? targetPersonId,
    String? targetItemId,
    String? targetMessageId,
    String? linkedMessageId,
    String? linkedParentItemId,
    int ordering = 0,
  }) =>
      _db.withMutatingUser(creatorId, () async {
        final id = CoordinationItemEntity.newId;
        final now = PgDateTime(DateTime.timestamp());

        return _db.transaction(() async {
          final item =
              await _db.managers.coordinationItems.createReturning((o) => o(
                    id: id,
                    beaconId: beaconId,
                    kind: kind,
                    status: const Value(coordinationItemStatusOpen),
                    title: Value(title),
                    body: Value(body),
                    creatorId: creatorId,
                    targetPersonId: Value(targetPersonId),
                    acceptedById: const Value(null),
                    targetItemId: Value(targetItemId),
                    targetMessageId: Value(targetMessageId),
                    linkedMessageId: Value(linkedMessageId),
                    linkedParentItemId: Value(linkedParentItemId),
                    ordering: Value(ordering),
                    createdAt: Value(now),
                    updatedAt: Value(now),
                    resolvedAt: const Value(null),
                    cancelledAt: const Value(null),
                  ));

          final roomMsgId = generateId('R');
          await _db.managers.beaconRoomMessages.createReturning((o) => o(
                id: roomMsgId,
                beaconId: beaconId,
                authorId: creatorId,
                body: const Value(''),
                semanticMarker: const Value(null),
                linkedBlockerId: const Value(null),
                linkedNextMoveId: const Value(null),
                linkedFactCardId: const Value(null),
                linkedPollingId: const Value(null),
                linkedItemId: Value(id),
                linkedEventKind:
                    const Value(coordinationEventKindCreated),
                systemPayload: const Value(null),
                mentions: const Value([]),
                createdAt: const Value.absent(),
              ));

          await _db.managers.beaconActivityEvents.create(
            (o) => o(
              id: Value(BeaconActivityEventEntity.newId),
              beaconId: beaconId,
              visibility: 1,
              type: _activityEventTypeForKind(kind, coordinationEventKindCreated),
              actorId: Value(creatorId),
              targetUserId: Value(targetPersonId),
              sourceMessageId: Value(roomMsgId),
              diff: const Value(null),
              createdAt: const Value.absent(),
            ),
          );

          return item;
        });
      });

  @override
  Future<CoordinationItem> updateStatus({
    required String id,
    required int newStatus,
    required String actorId,
  }) =>
      _db.withMutatingUser(actorId, () async {
        return _db.transaction(() async {
          final now = PgDateTime(DateTime.timestamp());
          final rows = await (_db.select(_db.coordinationItems)
                ..where((t) => t.id.equals(id)))
              .get();
          if (rows.isEmpty) {
            throw StateError('CoordinationItem not found: $id');
          }
          final existing = rows.first;

          await (_db.update(_db.coordinationItems)
                ..where((t) => t.id.equals(id)))
              .write(CoordinationItemsCompanion(
            status: Value(newStatus),
            updatedAt: Value(now),
            resolvedAt: newStatus == coordinationItemStatusResolved
                ? Value(now)
                : const Value.absent(),
            cancelledAt: newStatus == coordinationItemStatusCancelled
                ? Value(now)
                : const Value.absent(),
          ));

          final eventKind = _eventKindForStatus(newStatus);
          await _emitStatusRoomEvent(
            existing: existing,
            actorId: actorId,
            eventKind: eventKind,
          );

          final updated = await (_db.select(_db.coordinationItems)
                ..where((t) => t.id.equals(id)))
              .getSingle();
          return updated;
        });
      });

  @override
  Future<CoordinationItem> acceptItem({
    required String id,
    required String actorId,
    required String acceptedById,
  }) =>
      _db.withMutatingUser(actorId, () async {
        return _db.transaction(() async {
          final now = PgDateTime(DateTime.timestamp());
          final rows = await (_db.select(_db.coordinationItems)
                ..where((t) => t.id.equals(id)))
              .get();
          if (rows.isEmpty) {
            throw StateError('CoordinationItem not found: $id');
          }
          final existing = rows.first;

          await (_db.update(_db.coordinationItems)
                ..where((t) => t.id.equals(id)))
              .write(CoordinationItemsCompanion(
            status: const Value(coordinationItemStatusAccepted),
            acceptedById: Value(acceptedById),
            updatedAt: Value(now),
          ));

          await _emitStatusRoomEvent(
            existing: existing,
            actorId: actorId,
            eventKind: coordinationEventKindAccepted,
            targetUserId: existing.targetPersonId,
          );

          return (_db.select(_db.coordinationItems)
                ..where((t) => t.id.equals(id)))
              .getSingle();
        });
      });

  @override
  Future<CoordinationItem> redirectTarget({
    required String id,
    required String actorId,
    required String newTargetPersonId,
  }) =>
      _db.withMutatingUser(actorId, () async {
        return _db.transaction(() async {
          final now = PgDateTime(DateTime.timestamp());
          final rows = await (_db.select(_db.coordinationItems)
                ..where((t) => t.id.equals(id)))
              .get();
          if (rows.isEmpty) {
            throw StateError('CoordinationItem not found: $id');
          }
          final existing = rows.first;

          await (_db.update(_db.coordinationItems)
                ..where((t) => t.id.equals(id)))
              .write(CoordinationItemsCompanion(
            targetPersonId: Value(newTargetPersonId),
            updatedAt: Value(now),
          ));

          await _emitStatusRoomEvent(
            existing: existing,
            actorId: actorId,
            eventKind: coordinationEventKindUpdated,
            targetUserId: newTargetPersonId,
          );

          return (_db.select(_db.coordinationItems)
                ..where((t) => t.id.equals(id)))
              .getSingle();
        });
      });

  Future<void> _emitStatusRoomEvent({
    required CoordinationItem existing,
    required String actorId,
    required int eventKind,
    String? targetUserId,
  }) async {
    final roomMsgId = generateId('R');
    await _db.managers.beaconRoomMessages.createReturning((o) => o(
          id: roomMsgId,
          beaconId: existing.beaconId,
          authorId: actorId,
          body: const Value(''),
          semanticMarker: const Value(null),
          linkedBlockerId: const Value(null),
          linkedNextMoveId: const Value(null),
          linkedFactCardId: const Value(null),
          linkedPollingId: const Value(null),
          linkedItemId: Value(existing.id),
          linkedEventKind: Value(eventKind),
          systemPayload: const Value(null),
          mentions: const Value([]),
          createdAt: const Value.absent(),
        ));

    await _db.managers.beaconActivityEvents.create(
      (o) => o(
        id: Value(BeaconActivityEventEntity.newId),
        beaconId: existing.beaconId,
        visibility: 1,
        type: _activityEventTypeForKind(existing.kind, eventKind),
        actorId: Value(actorId),
        targetUserId: Value(targetUserId ?? existing.targetPersonId),
        sourceMessageId: Value(roomMsgId),
        diff: const Value(null),
        createdAt: const Value.absent(),
      ),
    );
  }

  @override
  Future<CoordinationItem?> getById(String id) =>
      (_db.select(_db.coordinationItems)..where((t) => t.id.equals(id)))
          .getSingleOrNull();

  @override
  Future<List<CoordinationItem>> listByBeacon(
    String beaconId, {
    int? status,
    int? kind,
    String? acceptedById,
    String? targetPersonId,
  }) {
    final q = _db.select(_db.coordinationItems)
      ..where((t) => t.beaconId.equals(beaconId))
      ..orderBy([
        (t) => OrderingTerm(expression: t.createdAt, mode: OrderingMode.desc),
      ]);
    if (status != null) {
      q.where((t) => t.status.equals(status));
    }
    if (kind != null) {
      q.where((t) => t.kind.equals(kind));
    }
    if (acceptedById != null) {
      q.where((t) => t.acceptedById.equals(acceptedById));
    }
    if (targetPersonId != null) {
      q.where((t) => t.targetPersonId.equals(targetPersonId));
    }
    return q.get();
  }

  @override
  Future<CoordinationItemMessage> appendMessage({
    required String itemId,
    required String senderId,
    required String body,
  }) async {
    final item = await getById(itemId);
    if (item == null) {
      throw StateError('CoordinationItem not found: $itemId');
    }
    return _db.withMutatingUser(senderId, () async {
      final id = CoordinationItemMessageEntity.newId;
      return _db.managers.coordinationItemMessages.createReturning((o) => o(
            id: id,
            itemId: itemId,
            beaconId: item.beaconId,
            senderId: senderId,
            body: Value(body),
            createdAt: const Value.absent(),
            editedAt: const Value(null),
          ));
    });
  }

  @override
  Future<List<CoordinationItemMessage>> listMessages(
    String itemId, {
    int? limit,
    String? before,
  }) {
    final q = _db.select(_db.coordinationItemMessages)
      ..where((t) => t.itemId.equals(itemId))
      ..orderBy([
        (t) => OrderingTerm(expression: t.createdAt, mode: OrderingMode.desc),
      ]);
    if (limit != null) {
      q.limit(limit);
    }
    if (before != null) {
      q.where(
        (t) => t.createdAt.isSmallerThanValue(
          PgDateTime(DateTime.parse(before)),
        ),
      );
    }
    return q.get();
  }

  int _eventKindForStatus(int status) => switch (status) {
        coordinationItemStatusAccepted => coordinationEventKindAccepted,
        coordinationItemStatusResolved => coordinationEventKindResolved,
        coordinationItemStatusCancelled => coordinationEventKindCancelled,
        coordinationItemStatusSuperseded => coordinationEventKindSuperseded,
        _ => coordinationEventKindUpdated,
      };

  /// Activity event type encoding: kind * 100 + eventKind.
  int _activityEventTypeForKind(int itemKind, int eventKind) =>
      itemKind * 100 + eventKind;
}
