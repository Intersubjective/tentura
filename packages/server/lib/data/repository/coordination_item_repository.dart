import 'package:injectable/injectable.dart';
import 'package:drift_postgres/drift_postgres.dart';

import 'package:tentura_server/consts/coordination_item_consts.dart';
import 'package:tentura_server/domain/entity/beacon_activity_event_entity.dart';
import 'package:tentura_server/domain/entity/coordination_item_entity.dart';
import 'package:tentura_server/domain/entity/coordination_item_message_entity.dart';
import 'package:tentura_server/domain/entity/coordination_item_with_counts.dart';
import 'package:tentura_server/domain/port/coordination_item_repository_port.dart';
import 'package:postgres/postgres.dart' show Type, TypedValue;
import 'package:tentura_server/utils/id.dart';

import '../database/tentura_db.dart';

@LazySingleton(as: CoordinationItemRepositoryPort, order: 1)
class CoordinationItemRepository implements CoordinationItemRepositoryPort {
  const CoordinationItemRepository(this._db);

  final TenturaDb _db;

  @override
  Future<CoordinationItem> createSelfAcceptedAsk({
    required String beaconId,
    required String creatorId,
    required String title,
    String body = '',
    String? linkedMessageId,
  }) =>
      _db.withMutatingUser(creatorId, () async {
        final id = CoordinationItemEntity.newId;
        final now = PgDateTime(DateTime.timestamp());

        return _db.transaction(() async {
          final item =
              await _db.managers.coordinationItems.createReturning((o) => o(
                    id: id,
                    beaconId: beaconId,
                    kind: coordinationItemKindAsk,
                    status: const Value(coordinationItemStatusAccepted),
                    title: Value(title),
                    body: Value(body),
                    creatorId: creatorId,
                    targetPersonId: Value(creatorId),
                    acceptedById: Value(creatorId),
                    targetItemId: const Value(null),
                    targetMessageId: const Value(null),
                    linkedMessageId: Value(linkedMessageId),
                    linkedParentItemId: const Value(null),
                    ordering: const Value(0),
                    createdAt: Value(now),
                    updatedAt: Value(now),
                    resolvedAt: const Value(null),
                    cancelledAt: const Value(null),
                    source: const Value(coordinationItemSourceSelfPromise),
                    published: const Value(true),
                  ));

          await _emitStatusRoomEvent(
            existing: item,
            actorId: creatorId,
            eventKind: coordinationEventKindAccepted,
            targetUserId: creatorId,
          );

          return (_db.select(_db.coordinationItems)
                ..where((t) => t.id.equals(item.id)))
              .getSingle();
        });
      });

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
                    source: const Value(coordinationItemSourceDefault),
                    published: const Value(true),
                  ));

          final trimmedLinkedMessageId = linkedMessageId?.trim();
          final String roomMsgIdForActivity;
          if (trimmedLinkedMessageId != null &&
              trimmedLinkedMessageId.isNotEmpty) {
            final srcRows = await (_db.select(_db.beaconRoomMessages)
                  ..where((t) => t.id.equals(trimmedLinkedMessageId)))
                .get();
            if (srcRows.isEmpty) {
              throw StateError(
                'Linked room message not found: $trimmedLinkedMessageId',
              );
            }
            if (srcRows.first.beaconId != beaconId) {
              throw StateError(
                'Linked message $trimmedLinkedMessageId is not in beacon $beaconId',
              );
            }
            await (_db.update(_db.beaconRoomMessages)
                  ..where((t) => t.id.equals(trimmedLinkedMessageId)))
                .write(
              BeaconRoomMessagesCompanion(
                linkedItemId: Value(id),
                linkedEventKind: const Value(coordinationEventKindCreated),
              ),
            );
            final notifyId = generateId('R');
            await _db.managers.beaconRoomMessages.createReturning((o) => o(
                  id: notifyId,
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
                  systemPayload: Value(<String, Object?>{
                    'sourceMessageId': trimmedLinkedMessageId,
                  }),
                  mentions: const Value([]),
                  createdAt: const Value.absent(),
                ));
            roomMsgIdForActivity = notifyId;
          } else {
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
            roomMsgIdForActivity = roomMsgId;
          }

          await _db.managers.beaconActivityEvents.create(
            (o) => o(
              id: Value(BeaconActivityEventEntity.newId),
              beaconId: beaconId,
              visibility: 1,
              type: _activityEventTypeForKind(kind, coordinationEventKindCreated),
              actorId: Value(creatorId),
              targetUserId: Value(targetPersonId),
              sourceMessageId: Value(roomMsgIdForActivity),
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
  Future<CoordinationItem> createDraftAsk({
    required String beaconId,
    required String creatorId,
    required String title,
    String body = '',
    String? targetPersonId,
    String? linkedMessageId,
  }) =>
      _db.withMutatingUser(creatorId, () async {
        final id = CoordinationItemEntity.newId;
        final now = PgDateTime(DateTime.timestamp());
        return _db.managers.coordinationItems.createReturning(
          (o) => o(
            id: id,
            beaconId: beaconId,
            kind: coordinationItemKindAsk,
            status: const Value(coordinationItemStatusOpen),
            title: Value(title),
            body: Value(body),
            creatorId: creatorId,
            targetPersonId: Value(targetPersonId),
            acceptedById: const Value(null),
            targetItemId: const Value(null),
            targetMessageId: const Value(null),
            linkedMessageId: Value(linkedMessageId),
            linkedParentItemId: const Value(null),
            ordering: const Value(0),
            createdAt: Value(now),
            updatedAt: Value(now),
            resolvedAt: const Value(null),
            cancelledAt: const Value(null),
            source: const Value(coordinationItemSourceDefault),
            published: const Value(false),
          ),
        );
      });

  @override
  Future<CoordinationItem> publishDraft({
    required String id,
    required String actorId,
    required String targetPersonId,
  }) =>
      _db.withMutatingUser(actorId, () async {
        return _db.transaction(() async {
          final rows =
              await (_db.select(_db.coordinationItems)..where((t) => t.id.equals(id))).get();
          if (rows.isEmpty) {
            throw StateError('CoordinationItem not found: $id');
          }
          final row = rows.first;
          if (row.published) {
            throw StateError('Coordination item is already published');
          }
          if (row.creatorId != actorId) {
            throw StateError('Only the creator may publish this draft');
          }
          if (row.kind != coordinationItemKindAsk) {
            throw StateError('Only ask drafts may be published');
          }
          final now = PgDateTime(DateTime.timestamp());
          final self = targetPersonId == row.creatorId;

          await (_db.update(_db.coordinationItems)..where((t) => t.id.equals(id))).write(
            CoordinationItemsCompanion(
              published: const Value(true),
              targetPersonId: Value(targetPersonId),
              updatedAt: Value(now),
              status: self
                  ? const Value(coordinationItemStatusAccepted)
                  : const Value.absent(),
              acceptedById: self ? Value(actorId) : const Value.absent(),
              source: self
                  ? const Value(coordinationItemSourceSelfPromise)
                  : const Value.absent(),
            ),
          );

          final updated =
              await (_db.select(_db.coordinationItems)..where((t) => t.id.equals(id))).getSingle();

          if (self) {
            await _emitStatusRoomEvent(
              existing: updated,
              actorId: actorId,
              eventKind: coordinationEventKindAccepted,
              targetUserId: targetPersonId,
            );
          } else {
            final roomMsgId = generateId('R');
            await _db.managers.beaconRoomMessages.createReturning((o) => o(
                  id: roomMsgId,
                  beaconId: updated.beaconId,
                  authorId: actorId,
                  body: const Value(''),
                  semanticMarker: const Value(null),
                  linkedBlockerId: const Value(null),
                  linkedNextMoveId: const Value(null),
                  linkedFactCardId: const Value(null),
                  linkedPollingId: const Value(null),
                  linkedItemId: Value(id),
                  linkedEventKind: const Value(coordinationEventKindCreated),
                  systemPayload: const Value(null),
                  mentions: const Value([]),
                  createdAt: const Value.absent(),
                ));

            await _db.managers.beaconActivityEvents.create(
              (o) => o(
                id: Value(BeaconActivityEventEntity.newId),
                beaconId: updated.beaconId,
                visibility: 1,
                type: _activityEventTypeForKind(
                  updated.kind,
                  coordinationEventKindCreated,
                ),
                actorId: Value(actorId),
                targetUserId: Value(targetPersonId),
                sourceMessageId: Value(roomMsgId),
                diff: const Value(null),
                createdAt: const Value.absent(),
              ),
            );
          }

          return (_db.select(_db.coordinationItems)..where((t) => t.id.equals(id))).getSingle();
        });
      });

  @override
  Future<CoordinationItem> updateDraftAsk({
    required String id,
    required String actorId,
    required String title,
    String body = '',
    bool updateTargetPersonId = false,
    String? targetPersonId,
  }) =>
      _db.withMutatingUser(actorId, () async {
        final rows =
            await (_db.select(_db.coordinationItems)..where((t) => t.id.equals(id))).get();
        if (rows.isEmpty) {
          throw StateError('CoordinationItem not found: $id');
        }
        final row = rows.first;
        if (row.published) {
          throw StateError('Only unpublished drafts may be edited');
        }
        if (row.creatorId != actorId) {
          throw StateError('Only the creator may edit this draft');
        }
        final now = PgDateTime(DateTime.timestamp());
        await (_db.update(_db.coordinationItems)..where((t) => t.id.equals(id))).write(
          CoordinationItemsCompanion(
            title: Value(title),
            body: Value(body),
            targetPersonId: updateTargetPersonId
                ? Value(targetPersonId)
                : const Value.absent(),
            updatedAt: Value(now),
          ),
        );
        return (_db.select(_db.coordinationItems)..where((t) => t.id.equals(id))).getSingle();
      });

  @override
  Future<CoordinationItem> updatePublishedItem({
    required String id,
    required String actorId,
    required String title,
    String body = '',
  }) =>
      _db.withMutatingUser(actorId, () async {
        return _db.transaction(() async {
          final rows = await (_db.select(_db.coordinationItems)
                ..where((t) => t.id.equals(id)))
              .get();
          if (rows.isEmpty) {
            throw StateError('CoordinationItem not found: $id');
          }
          final existing = rows.first;
          if (!existing.published) {
            throw StateError('Only published items may be edited in place');
          }
          if (existing.status != coordinationItemStatusOpen &&
              existing.status != coordinationItemStatusAccepted) {
            throw StateError('Item is not editable');
          }
          final now = PgDateTime(DateTime.timestamp());
          await (_db.update(_db.coordinationItems)
                ..where((t) => t.id.equals(id)))
              .write(
            CoordinationItemsCompanion(
              title: Value(title),
              body: Value(body),
              updatedAt: Value(now),
            ),
          );

          await _emitStatusRoomEvent(
            existing: existing,
            actorId: actorId,
            eventKind: coordinationEventKindUpdated,
            targetUserId: existing.targetPersonId,
          );

          if (existing.kind == coordinationItemKindPlan &&
              existing.linkedParentItemId == null &&
              existing.status == coordinationItemStatusOpen) {
            final planText = title.trim();
            if (planText.isNotEmpty) {
              await _db.into(_db.beaconRoomStates).insertOnConflictUpdate(
                    BeaconRoomStatesCompanion.insert(
                      beaconId: existing.beaconId,
                      currentPlan: Value(planText),
                      updatedBy: Value(actorId),
                      updatedAt: Value(now),
                    ),
                  );
            }
          }

          return (_db.select(_db.coordinationItems)
                ..where((t) => t.id.equals(id)))
              .getSingle();
        });
      });

  @override
  Future<void> deleteDraftAsk({
    required String id,
    required String actorId,
  }) =>
      _db.withMutatingUser(actorId, () async {
        final deleted = await (_db.delete(_db.coordinationItems)
              ..where(
                (t) =>
                    t.id.equals(id) &
                    t.published.equals(false) &
                    t.creatorId.equals(actorId),
              ))
            .go();
        if (deleted == 0) {
          throw StateError('Draft not found or not deletable');
        }
      });

  @override
  Future<CoordinationItem> createDraftBlocker({
    required String beaconId,
    required String creatorId,
    required String title,
    String body = '',
  }) =>
      _db.withMutatingUser(creatorId, () async {
        final id = CoordinationItemEntity.newId;
        final now = PgDateTime(DateTime.timestamp());
        return _db.managers.coordinationItems.createReturning(
          (o) => o(
            id: id,
            beaconId: beaconId,
            kind: coordinationItemKindBlocker,
            status: const Value(coordinationItemStatusOpen),
            title: Value(title),
            body: Value(body),
            creatorId: creatorId,
            targetPersonId: const Value(null),
            acceptedById: const Value(null),
            targetItemId: const Value(null),
            targetMessageId: const Value(null),
            linkedMessageId: const Value(null),
            linkedParentItemId: const Value(null),
            ordering: const Value(0),
            createdAt: Value(now),
            updatedAt: Value(now),
            resolvedAt: const Value(null),
            cancelledAt: const Value(null),
            source: const Value(coordinationItemSourceDefault),
            published: const Value(false),
          ),
        );
      });

  @override
  Future<CoordinationItem> publishDraftBlocker({
    required String id,
    required String actorId,
  }) =>
      _db.withMutatingUser(actorId, () async {
        return _db.transaction(() async {
          final rows = await (_db.select(_db.coordinationItems)
                ..where((t) => t.id.equals(id)))
              .get();
          if (rows.isEmpty) {
            throw StateError('CoordinationItem not found: $id');
          }
          final row = rows.first;
          if (row.published) {
            throw StateError('Coordination item is already published');
          }
          if (row.creatorId != actorId) {
            throw StateError('Only the creator may publish this draft');
          }
          if (row.kind != coordinationItemKindBlocker) {
            throw StateError('Only blocker drafts may be published');
          }
          final now = PgDateTime(DateTime.timestamp());

          await (_db.update(_db.coordinationItems)..where((t) => t.id.equals(id)))
              .write(
            CoordinationItemsCompanion(
              published: const Value(true),
              updatedAt: Value(now),
            ),
          );

          final updated = await (_db.select(_db.coordinationItems)
                ..where((t) => t.id.equals(id)))
              .getSingle();

          final roomMsgId = generateId('R');
          await _db.managers.beaconRoomMessages.createReturning((o) => o(
                id: roomMsgId,
                beaconId: updated.beaconId,
                authorId: actorId,
                body: const Value(''),
                semanticMarker: const Value(null),
                linkedBlockerId: const Value(null),
                linkedNextMoveId: const Value(null),
                linkedFactCardId: const Value(null),
                linkedPollingId: const Value(null),
                linkedItemId: Value(id),
                linkedEventKind: const Value(coordinationEventKindCreated),
                systemPayload: const Value(null),
                mentions: const Value([]),
                createdAt: const Value.absent(),
              ));

          await _db.managers.beaconActivityEvents.create(
            (o) => o(
              id: Value(BeaconActivityEventEntity.newId),
              beaconId: updated.beaconId,
              visibility: 1,
              type: _activityEventTypeForKind(
                updated.kind,
                coordinationEventKindCreated,
              ),
              actorId: Value(actorId),
              targetUserId: const Value(null),
              sourceMessageId: Value(roomMsgId),
              diff: const Value(null),
              createdAt: const Value.absent(),
            ),
          );

          return updated;
        });
      });

  @override
  Future<CoordinationItem> updateDraftBlocker({
    required String id,
    required String actorId,
    required String title,
    String body = '',
  }) =>
      _db.withMutatingUser(actorId, () async {
        final rows = await (_db.select(_db.coordinationItems)
              ..where((t) => t.id.equals(id)))
            .get();
        if (rows.isEmpty) {
          throw StateError('CoordinationItem not found: $id');
        }
        final row = rows.first;
        if (row.published) {
          throw StateError('Only unpublished drafts may be edited');
        }
        if (row.creatorId != actorId) {
          throw StateError('Only the creator may edit this draft');
        }
        if (row.kind != coordinationItemKindBlocker) {
          throw StateError('Only blocker drafts may be edited');
        }
        final now = PgDateTime(DateTime.timestamp());
        await (_db.update(_db.coordinationItems)..where((t) => t.id.equals(id)))
            .write(
          CoordinationItemsCompanion(
            title: Value(title),
            body: Value(body),
            updatedAt: Value(now),
          ),
        );
        return (_db.select(_db.coordinationItems)..where((t) => t.id.equals(id)))
            .getSingle();
      });

  @override
  Future<void> deleteDraftBlocker({
    required String id,
    required String actorId,
  }) =>
      _db.withMutatingUser(actorId, () async {
        final deleted = await (_db.delete(_db.coordinationItems)
              ..where(
                (t) =>
                    t.id.equals(id) &
                    t.kind.equals(coordinationItemKindBlocker) &
                    t.published.equals(false) &
                    t.creatorId.equals(actorId),
              ))
            .go();
        if (deleted == 0) {
          throw StateError('Draft not found or not deletable');
        }
      });

  @override
  Future<CoordinationItem?> getById(String id) =>
      (_db.select(_db.coordinationItems)..where((t) => t.id.equals(id)))
          .getSingleOrNull();

  @override
  Future<List<CoordinationItemWithCounts>> listByBeacon(
    String beaconId, {
    required String viewerUserId,
    int? status,
    int? kind,
    String? acceptedById,
    String? targetPersonId,
    String? linkedParentItemId,
    bool rootOnly = false,
  }) async {
    final q = _db.select(_db.coordinationItems)
      ..where((t) => t.beaconId.equals(beaconId))
      ..where(
        (t) =>
            t.published.equals(true) |
            t.creatorId.equals(viewerUserId),
      )
      ..orderBy([
        (t) => OrderingTerm(expression: t.ordering),
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
    if (linkedParentItemId != null) {
      q.where((t) => t.linkedParentItemId.equals(linkedParentItemId));
    }
    if (rootOnly) {
      q.where((t) => t.linkedParentItemId.isNull());
    }
    final items = await q.get();
    if (items.isEmpty) {
      return const [];
    }

    final countRows = await _db.customSelect(
      r'''
      SELECT ci.id AS item_id,
        (SELECT COUNT(*)::bigint FROM coordination_item_message m
         WHERE m.item_id = ci.id) AS message_count,
        (SELECT COUNT(*)::bigint FROM coordination_item_message m
         WHERE m.item_id = ci.id
           AND m.sender_id <> $2
           AND (s.last_seen_at IS NULL OR m.created_at > s.last_seen_at)
        ) AS unread_count
      FROM coordination_item ci
      LEFT JOIN coordination_item_user_seen s
        ON s.item_id = ci.id AND s.user_id = $2
      WHERE ci.id = ANY($1::text[])
      ''',
      variables: [
        Variable(TypedValue(Type.textArray, items.map((e) => e.id).toList())),
        Variable<String>(viewerUserId),
      ],
    ).get();

    final itemIds = items.map((e) => e.id).toList();
    final seenRows = await (_db.select(_db.coordinationItemUserSeen)
          ..where((t) => t.userId.equals(viewerUserId))
          ..where((t) => t.itemId.isIn(itemIds)))
        .get();
    final lastSeenByItemId = {
      for (final row in seenRows) row.itemId: row.lastSeenAt.dateTime,
    };

    final countsByItemId = <String, ({int messageCount, int unreadCount})>{};
    for (final row in countRows) {
      countsByItemId[row.read<String>('item_id')] = (
        messageCount: row.read<int>('message_count'),
        unreadCount: row.read<int>('unread_count'),
      );
    }

    return [
      for (final item in items)
        CoordinationItemWithCounts(
          item: item,
          messageCount: countsByItemId[item.id]?.messageCount ?? 0,
          unreadCount: countsByItemId[item.id]?.unreadCount ?? 0,
          lastSeenAt: lastSeenByItemId[item.id],
        ),
    ];
  }

  @override
  Future<void> markItemSeen({
    required String userId,
    required String itemId,
    required DateTime at,
  }) =>
      _db.withMutatingUser(userId, () async {
        final seenAt = PgDateTime(at);
        await _db.into(_db.coordinationItemUserSeen).insert(
              CoordinationItemUserSeenCompanion(
                userId: Value(userId),
                itemId: Value(itemId),
                lastSeenAt: Value(seenAt),
              ),
              onConflict: DoUpdate(
                (_) => CoordinationItemUserSeenCompanion(
                  lastSeenAt: Value(seenAt),
                ),
              ),
            );
      });

  @override
  Future<Map<String, DateTime>> lastCoordinationItemMessageAtByBeaconIds({
    required List<String> beaconIds,
    required String viewerUserId,
  }) async {
    if (beaconIds.isEmpty) {
      return const {};
    }
    // Aggregates only scalars drift can read from customSelect (int/bigint).
    // Timestamptz columns must use typed table reads (see beacon_mapper .dateTime).
    final rows = await _db.customSelect(
      r'''
      SELECT ci.beacon_id AS beacon_id,
        floor(extract(epoch from max(cim.created_at)) * 1000)::bigint
          AS last_at_ms
      FROM coordination_item ci
      INNER JOIN coordination_item_message cim ON cim.item_id = ci.id
      WHERE ci.beacon_id = ANY($1::text[])
        AND ci.status IN ($3, $4)
        AND (ci.published = true OR ci.creator_id = $2)
      GROUP BY ci.beacon_id
      ''',
      variables: [
        Variable(TypedValue(Type.textArray, beaconIds)),
        Variable<String>(viewerUserId),
        const Variable<int>(coordinationItemStatusOpen),
        const Variable<int>(coordinationItemStatusAccepted),
      ],
    ).get();

    return {
      for (final row in rows)
        row.read<String>('beacon_id'): DateTime.fromMillisecondsSinceEpoch(
          row.read<int>('last_at_ms'),
          isUtc: true,
        ),
    };
  }

  @override
  Future<CoordinationItem> publishRootPlan({
    required String beaconId,
    required String creatorId,
    required String title,
    String body = '',
    String? targetPersonId,
    String? linkedMessageId,
    String? syncCurrentPlanText,
  }) async {
    final openRootPlans = await (_db.select(_db.coordinationItems)
          ..where((t) => t.beaconId.equals(beaconId))
          ..where((t) => t.kind.equals(coordinationItemKindPlan))
          ..where((t) => t.linkedParentItemId.isNull())
          ..where((t) => t.status.equals(coordinationItemStatusOpen)))
        .get();
    for (final existing in openRootPlans) {
      await updateStatus(
        id: existing.id,
        newStatus: coordinationItemStatusSuperseded,
        actorId: creatorId,
      );
    }

    final item = await create(
      beaconId: beaconId,
      kind: coordinationItemKindPlan,
      creatorId: creatorId,
      title: title,
      body: body,
      targetPersonId: targetPersonId,
      linkedMessageId: linkedMessageId,
    );

    final planText = (syncCurrentPlanText ?? title).trim();
    if (planText.isNotEmpty) {
      await _db.withMutatingUser(creatorId, () async {
        await _db.into(_db.beaconRoomStates).insertOnConflictUpdate(
              BeaconRoomStatesCompanion.insert(
                beaconId: beaconId,
                currentPlan: Value(planText),
                updatedBy: Value(creatorId),
                updatedAt: Value(PgDateTime(DateTime.timestamp())),
              ),
            );
      });
    }
    return item;
  }

  @override
  Future<CoordinationItem> addPlanStep({
    required String parentItemId,
    required String creatorId,
    required String title,
    String body = '',
  }) async {
    final parent = await getById(parentItemId);
    if (parent == null) {
      throw StateError('CoordinationItem not found: $parentItemId');
    }
    if (parent.kind != coordinationItemKindPlan) {
      throw StateError('Parent is not a plan item');
    }
    final siblings = await (_db.select(_db.coordinationItems)
          ..where((t) => t.linkedParentItemId.equals(parentItemId)))
        .get();
    var maxOrder = 0;
    for (final s in siblings) {
      if (s.ordering > maxOrder) maxOrder = s.ordering;
    }
    return create(
      beaconId: parent.beaconId,
      kind: coordinationItemKindPlan,
      creatorId: creatorId,
      title: title,
      body: body,
      linkedParentItemId: parentItemId,
      ordering: maxOrder + 1,
    );
  }

  @override
  Future<CoordinationItemMessage?> getMessageById(String messageId) =>
      _db.managers.coordinationItemMessages
          .filter((m) => m.id.equals(messageId))
          .getSingleOrNull();

  @override
  Future<void> deleteMessage({required String messageId}) =>
      _db.managers.coordinationItemMessages
          .filter((m) => m.id.equals(messageId))
          .delete();

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
