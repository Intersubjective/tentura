import 'dart:convert';

import 'package:drift/drift.dart' show QueryRow;
import 'package:injectable/injectable.dart';
import 'package:meta/meta.dart';
import 'package:drift_postgres/drift_postgres.dart';

import 'package:tentura_server/consts/beacon_room_consts.dart';
import 'package:tentura_server/consts/coordination_item_consts.dart';
import 'package:tentura_server/domain/coordination_stale_rules.dart';
import 'package:tentura_server/domain/entity/beacon_activity_event_entity.dart';
import 'package:tentura_server/domain/entity/beacon_thread_record.dart';
import 'package:tentura_server/domain/entity/coordination_responsibility_counts.dart';
import 'package:tentura_server/domain/entity/coordination_item_record.dart';
import 'package:tentura_server/domain/entity/coordination_item_with_counts.dart';
import 'package:tentura_server/domain/port/coordination_item_repository_port.dart';
import 'package:postgres/postgres.dart' show Type, TypedValue;
import 'package:tentura_server/utils/id.dart';

import '../database/tentura_db.dart';
import 'mappers/coordination_row_mappers.dart';

@LazySingleton(as: CoordinationItemRepositoryPort, order: 1)
class CoordinationItemRepository implements CoordinationItemRepositoryPort {
  const CoordinationItemRepository(this._db);

  final TenturaDb _db;

  @override
  Future<CoordinationItemRecord> create({
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
    int? staleAfterDays,
  }) =>
      _db.withMutatingUser(creatorId, () async {
        final id = CoordinationItemEntity.newId;
        final now = PgDateTime(DateTime.timestamp());
        final days = validateStaleAfterDays(staleAfterDays);
        final staleAtValue = computeStaleAt(now.dateTime.toUtc(), days);

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
                    staleAt: Value(staleAtValue == null ? null : PgDateTime(staleAtValue)),
                    staleAfterDays: Value(days),
                    source: const Value(coordinationItemSourceDefault),
                    published: const Value(true),
                    publishedAt: Value(now),
                  ));

          final roomMsgIdForActivity = await _emitCreatedRoomNotify(
            itemId: id,
            beaconId: beaconId,
            kind: kind,
            creatorId: creatorId,
            linkedMessageId: linkedMessageId,
            linkedParentItemId: linkedParentItemId,
            targetPersonId: targetPersonId,
            title: title,
            body: body,
          );

          await _db.managers.beaconActivityEvents.create(
            (o) => o(
              id: Value(BeaconActivityEventEntity.newId),
              beaconId: beaconId,
              visibility: 1,
              type: _activityEventTypeForKind(kind, coordinationEventKindCreated),
              actorId: Value(creatorId),
              targetUserId: Value(targetPersonId),
              sourceMessageId: Value(roomMsgIdForActivity),
              coordinationItemId: Value(id),
              diff: _activityEventDiff(title: title, body: body),
              createdAt: const Value.absent(),
            ),
          );

          return item.toRecord();
        });
      });

  @override
  Future<CoordinationItemRecord> updateStatus({
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
          return updated.toRecord();
        });
      });

  @override
  Future<CoordinationItemRecord> acceptItem({
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
          final newStaleAt = computeStaleAtAfterAccept(
            nowUtc: now.dateTime.toUtc(),
            staleAfterDays: existing.staleAfterDays,
          );

          await (_db.update(_db.coordinationItems)
                ..where((t) => t.id.equals(id)))
              .write(CoordinationItemsCompanion(
            status: const Value(coordinationItemStatusAccepted),
            acceptedById: Value(acceptedById),
            updatedAt: Value(now),
            staleAt: Value(
              newStaleAt == null ? null : PgDateTime(newStaleAt),
            ),
          ));

          await _emitStatusRoomEvent(
            existing: existing,
            actorId: actorId,
            eventKind: coordinationEventKindAccepted,
            targetUserId: existing.targetPersonId,
          );

          return (await (_db.select(_db.coordinationItems)..where((t) => t.id.equals(id))).getSingle()).toRecord();
        });
      });

  @override
  Future<CoordinationItemRecord> redirectTarget({
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

          return (await (_db.select(_db.coordinationItems)..where((t) => t.id.equals(id))).getSingle()).toRecord();
        });
      });

  Future<void> _emitStatusRoomEvent({
    required CoordinationItem existing,
    required String actorId,
    required int eventKind,
    String? targetUserId,
  }) async {
    final anchorId = existing.linkedMessageId?.trim();
    final hasAnchor = anchorId != null && anchorId.isNotEmpty;
    final nowIso = DateTime.timestamp().toUtc().toIso8601String();
    final skipPlanSupersededRoomRow =
        existing.kind == coordinationItemKindPlan &&
        eventKind == coordinationEventKindSuperseded;

    String? roomMsgId;
    if (!skipPlanSupersededRoomRow) {
      final newRoomMsgId = generateId('R');
      roomMsgId = newRoomMsgId;
      await _db.managers.beaconRoomMessages.createReturning((o) => o(
            id: newRoomMsgId,
            beaconId: existing.beaconId,
            authorId: actorId,
            body: const Value(''),
            semanticMarker: const Value(null),
            linkedNextMoveId: const Value(null),
            linkedFactCardId: const Value(null),
            linkedPollingId: const Value(null),
            linkedItemId: Value(existing.id),
            linkedEventKind: Value(eventKind),
            systemPayload: hasAnchor
                ? Value(<String, Object?>{'sourceMessageId': anchorId})
                : const Value(null),
            mentions: const Value([]),
            createdAt: const Value.absent(),
          ));
    }

    if (hasAnchor) {
      await _mergeSourceMessageLastStatusEvent(
        sourceMessageId: anchorId,
        actorId: actorId,
        eventKind: eventKind,
        atIso: nowIso,
      );
    }

    await _db.managers.beaconActivityEvents.create(
      (o) => o(
        id: Value(BeaconActivityEventEntity.newId),
        beaconId: existing.beaconId,
        visibility: 1,
        type: _activityEventTypeForKind(existing.kind, eventKind),
        actorId: Value(actorId),
        targetUserId: Value(targetUserId ?? existing.targetPersonId),
        sourceMessageId: Value(roomMsgId ?? anchorId),
        coordinationItemId: Value(existing.id),
        diff: _activityEventDiff(title: existing.title, body: existing.body),
        createdAt: const Value.absent(),
      ),
    );
  }

  @override
  Future<CoordinationItemRecord> createDraftAsk({
    required String beaconId,
    required String creatorId,
    required String title,
    String body = '',
    String? targetPersonId,
    String? linkedMessageId,
    int? staleAfterDays,
  }) =>
      _db.withMutatingUser(creatorId, () async {
        final id = CoordinationItemEntity.newId;
        final now = PgDateTime(DateTime.timestamp());
        final days = validateStaleAfterDays(staleAfterDays);
        return (await _db.managers.coordinationItems.createReturning(
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
            staleAfterDays: Value(days),
            source: const Value(coordinationItemSourceDefault),
            published: const Value(false),
          ),
        )).toRecord();
      });

  @override
  Future<CoordinationItemRecord> createDraftPromise({
    required String beaconId,
    required String creatorId,
    required String title,
    String body = '',
    String? targetPersonId,
    String? linkedMessageId,
    int? staleAfterDays,
  }) =>
      _db.withMutatingUser(creatorId, () async {
        final id = CoordinationItemEntity.newId;
        final now = PgDateTime(DateTime.timestamp());
        final days = validateStaleAfterDays(staleAfterDays);
        return (await _db.managers.coordinationItems.createReturning(
          (o) => o(
            id: id,
            beaconId: beaconId,
            kind: coordinationItemKindPromise,
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
            staleAfterDays: Value(days),
            source: const Value(coordinationItemSourceDefault),
            published: const Value(false),
          ),
        )).toRecord();
      });

  @override
  Future<CoordinationItemRecord> publishDraft({
    required String id,
    required String actorId,
    required String targetPersonId,
    int? staleAfterDays,
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
          if (row.kind != coordinationItemKindAsk &&
              row.kind != coordinationItemKindPromise) {
            throw StateError('Only ask or promise drafts may be published');
          }
          final now = PgDateTime(DateTime.timestamp());
          final days = staleAfterDays != null
              ? validateStaleAfterDays(staleAfterDays)
              : validateStaleAfterDays(row.staleAfterDays);
          final staleAtValue = computeStaleAt(now.dateTime.toUtc(), days);

          await (_db.update(_db.coordinationItems)..where((t) => t.id.equals(id))).write(
            CoordinationItemsCompanion(
              published: const Value(true),
              publishedAt: Value(now),
              targetPersonId: Value(targetPersonId),
              updatedAt: Value(now),
              staleAfterDays: Value(days),
              staleAt: Value(
                staleAtValue == null ? null : PgDateTime(staleAtValue),
              ),
            ),
          );

          final updated =
              ((await (_db.select(_db.coordinationItems)..where((t) => t.id.equals(id))).getSingle())).toRecord();

          final roomMsgIdForActivity = await _emitCreatedRoomNotify(
            itemId: id,
            beaconId: updated.beaconId,
            kind: updated.kind,
            creatorId: actorId,
            linkedMessageId: updated.linkedMessageId,
            linkedParentItemId: updated.linkedParentItemId,
            targetPersonId: targetPersonId,
            title: updated.title,
            body: updated.body,
          );

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
              sourceMessageId: Value(roomMsgIdForActivity),
              coordinationItemId: Value(id),
              diff: _activityEventDiff(title: updated.title, body: updated.body),
              createdAt: const Value.absent(),
            ),
          );

          return (await (_db.select(_db.coordinationItems)..where((t) => t.id.equals(id))).getSingle()).toRecord();
        });
      });

  @override
  Future<CoordinationItemRecord> updateDraftAsk({
    required String id,
    required String actorId,
    required String title,
    String body = '',
    bool updateTargetPersonId = false,
    String? targetPersonId,
    bool updateStaleAfterDays = false,
    int? staleAfterDays,
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
            staleAfterDays: updateStaleAfterDays
                ? Value(validateStaleAfterDays(staleAfterDays))
                : const Value.absent(),
            updatedAt: Value(now),
          ),
        );
        return (await (_db.select(_db.coordinationItems)..where((t) => t.id.equals(id))).getSingle()).toRecord();
      });

  @override
  Future<CoordinationItemRecord> updatePublishedItem({
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
                      currentLine: Value(planText),
                      updatedBy: Value(actorId),
                      updatedAt: Value(now),
                    ),
                  );
            }
          }

          return (await (_db.select(_db.coordinationItems)..where((t) => t.id.equals(id))).getSingle()).toRecord();
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
  Future<CoordinationItemRecord> createDraftBlocker({
    required String beaconId,
    required String creatorId,
    required String title,
    String body = '',
    String? targetPersonId,
    int? staleAfterDays,
  }) =>
      _db.withMutatingUser(creatorId, () async {
        final id = CoordinationItemEntity.newId;
        final now = PgDateTime(DateTime.timestamp());
        final days = validateStaleAfterDays(staleAfterDays);
        return (await _db.managers.coordinationItems.createReturning(
          (o) => o(
            id: id,
            beaconId: beaconId,
            kind: coordinationItemKindBlocker,
            status: const Value(coordinationItemStatusOpen),
            title: Value(title),
            body: Value(body),
            creatorId: creatorId,
            targetPersonId: Value(targetPersonId),
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
            staleAfterDays: Value(days),
            source: const Value(coordinationItemSourceDefault),
            published: const Value(false),
          ),
        )).toRecord();
      });

  @override
  Future<CoordinationItemRecord> publishDraftBlocker({
    required String id,
    required String actorId,
    int? staleAfterDays,
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
          final days = staleAfterDays != null
              ? validateStaleAfterDays(staleAfterDays)
              : validateStaleAfterDays(row.staleAfterDays);
          final staleAtValue = computeStaleAt(now.dateTime.toUtc(), days);

          await (_db.update(_db.coordinationItems)..where((t) => t.id.equals(id)))
              .write(
            CoordinationItemsCompanion(
              published: const Value(true),
              publishedAt: Value(now),
              updatedAt: Value(now),
              staleAfterDays: Value(days),
              staleAt: Value(
                staleAtValue == null ? null : PgDateTime(staleAtValue),
              ),
            ),
          );

          final updated = await (_db.select(_db.coordinationItems)
                ..where((t) => t.id.equals(id)))
              .getSingle();

          final roomMsgIdForActivity = await _emitCreatedRoomNotify(
            itemId: id,
            beaconId: updated.beaconId,
            kind: updated.kind,
            creatorId: actorId,
            linkedMessageId: updated.linkedMessageId,
            linkedParentItemId: updated.linkedParentItemId,
            title: updated.title,
            body: updated.body,
          );

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
              sourceMessageId: Value(roomMsgIdForActivity),
              coordinationItemId: Value(id),
              diff: _activityEventDiff(title: updated.title, body: updated.body),
              createdAt: const Value.absent(),
            ),
          );

          return updated.toRecord();
        });
      });

  @override
  Future<CoordinationItemRecord> updateDraftBlocker({
    required String id,
    required String actorId,
    required String title,
    String body = '',
    bool updateTargetPersonId = false,
    String? targetPersonId,
    bool updateStaleAfterDays = false,
    int? staleAfterDays,
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
            targetPersonId: updateTargetPersonId
                ? Value(targetPersonId)
                : const Value.absent(),
            staleAfterDays: updateStaleAfterDays
                ? Value(validateStaleAfterDays(staleAfterDays))
                : const Value.absent(),
            updatedAt: Value(now),
          ),
        );
        return (await (_db.select(_db.coordinationItems)..where((t) => t.id.equals(id)))
            .getSingle()).toRecord();
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
  Future<CoordinationItemRecord?> getById(String id) async =>
      (await (_db.select(_db.coordinationItems)..where((t) => t.id.equals(id)))
          .getSingleOrNull())
          ?.toRecord();

  @override
  Future<CoordinationItemRecord?> tryClaimRemind({
    required String itemId,
    required String actorId,
  }) =>
      _db.withMutatingUser(actorId, () async {
        final now = PgDateTime(DateTime.timestamp());
        final cooldownBefore = PgDateTime(
          DateTime.timestamp().subtract(
            const Duration(hours: kCoordinationItemRemindCooldownHours),
          ),
        );
        final updated = await (_db.update(_db.coordinationItems)
              ..where(
                (t) =>
                    t.id.equals(itemId) &
                    t.staleAt.isNotNull() &
                    t.staleAt.isSmallerOrEqualValue(now) &
                    t.status.isIn([
                      coordinationItemStatusOpen,
                      coordinationItemStatusAccepted,
                    ]) &
                    (t.lastRemindedAt.isNull() |
                        t.lastRemindedAt.isSmallerOrEqualValue(cooldownBefore)),
              ))
            .write(
          CoordinationItemsCompanion(
            lastRemindedAt: Value(now),
            updatedAt: Value(now),
          ),
        );
        if (updated == 0) {
          return null;
        }
        return getById(itemId);
      });

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
        (SELECT COUNT(*)::bigint FROM beacon_room_message m
         WHERE m.thread_item_id = ci.id
           AND ci.kind <> $3) AS message_count,
        (SELECT COUNT(*)::bigint FROM beacon_room_message m
         WHERE m.thread_item_id = ci.id
           AND ci.kind <> $3
           AND m.author_id <> $2
           AND (s.last_seen_at IS NULL OR m.created_at > s.last_seen_at)
        ) AS unread_count
      FROM coordination_item ci
      LEFT JOIN beacon_room_seen s
        ON s.thread_item_id = ci.id AND s.user_id = $2
      WHERE ci.id = ANY($1::text[])
      ''',
      variables: [
        Variable(TypedValue(Type.textArray, items.map((e) => e.id).toList())),
        Variable<String>(viewerUserId),
        const Variable<int>(coordinationItemKindPlan),
      ],
    ).get();

    final itemIds = items.map((e) => e.id).toList();
    final seenRows = await (_db.select(_db.beaconRoomSeen)
          ..where((t) => t.userId.equals(viewerUserId))
          ..where((t) => t.threadItemId.isIn(itemIds)))
        .get();
    final lastSeenByItemId = {
      for (final row in seenRows)
        if (row.threadItemId != null) row.threadItemId!: row.lastSeenAt.dateTime,
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
          item: item.toRecord(),
          messageCount: countsByItemId[item.id]?.messageCount ?? 0,
          unreadCount: countsByItemId[item.id]?.unreadCount ?? 0,
          lastSeenAt: lastSeenByItemId[item.id],
        ),
    ];
  }

  @override
  Future<List<BeaconThreadRecord>> listThreads({
    required String beaconId,
    required String viewerUserId,
    required bool includeGeneral,
    required bool itemParticipantsOnly,
    required int excerptCharacters,
  }) async {
    final rows = await _db.customSelect(
      r'''
WITH eligible_item AS (
  SELECT ci.*
  FROM coordination_item ci
  WHERE ci.beacon_id = $1
    AND ci.kind IN (2, 3, 5)
    AND (
      ($3::boolean = false AND (ci.published = true OR ci.creator_id = $2))
      OR
      ($3::boolean = true AND ci.published = true AND
        (ci.creator_id = $2 OR ci.target_person_id = $2 OR ci.accepted_by_id = $2))
    )
), thread_base AS (
  -- General row (synthetic) when includeGeneral is true.
  SELECT 'general'::text AS thread_id, 'general'::text AS thread_kind,
         NULL::text AS item_id, NULL::int AS item_kind,
         NULL::timestamptz AS item_updated_at
  WHERE $4::boolean
  UNION ALL
  SELECT ci.id,
         CASE ci.kind WHEN 2 THEN 'ask' WHEN 3 THEN 'blocker' WHEN 5 THEN 'promise' END,
         ci.id, ci.kind, ci.updated_at
  FROM eligible_item ci
)
SELECT
  tb.thread_id,
  tb.thread_kind,
  counts.message_count,
  counts.unread_count,
  floor(extract(epoch from s.last_seen_at) * 1000)::bigint AS thread_last_seen_at_ms,
  floor(extract(epoch from counts.last_message_at) * 1000)::bigint AS last_message_at_ms,
  lm.author_id AS last_message_author_id,
  lm.body AS lm_body,
  lm.semantic_marker AS lm_semantic_marker,
  lm.linked_item_id AS lm_linked_item_id,
  lm.linked_event_kind AS lm_linked_event_kind,
  lm.system_payload::text AS lm_system_payload_json,
  COALESCE(att.has_attachment, false) AS lm_has_attachment,
  linked_ci.kind AS lm_linked_item_kind,
  linked_ci.title AS lm_linked_item_title,
  pol.question AS lm_poll_title,
  bfc.fact_text AS lm_fact_title,
  bfc.visibility AS lm_fact_visibility,
  ci.id AS ci_id,
  ci.beacon_id AS ci_beacon_id,
  ci.kind AS ci_kind,
  ci.status AS ci_status,
  ci.title AS ci_title,
  ci.body AS ci_body,
  ci.creator_id AS ci_creator_id,
  ci.target_person_id AS ci_target_person_id,
  ci.accepted_by_id AS ci_accepted_by_id,
  ci.target_item_id AS ci_target_item_id,
  ci.target_message_id AS ci_target_message_id,
  ci.linked_message_id AS ci_linked_message_id,
  ci.linked_parent_item_id AS ci_linked_parent_item_id,
  ci.ordering AS ci_ordering,
  ci.source AS ci_source,
  ci.published AS ci_published,
  floor(extract(epoch from ci.created_at) * 1000)::bigint AS ci_created_at_ms,
  floor(extract(epoch from ci.updated_at) * 1000)::bigint AS ci_updated_at_ms,
  floor(extract(epoch from ci.published_at) * 1000)::bigint AS ci_published_at_ms,
  floor(extract(epoch from ci.resolved_at) * 1000)::bigint AS ci_resolved_at_ms,
  floor(extract(epoch from ci.cancelled_at) * 1000)::bigint AS ci_cancelled_at_ms,
  floor(extract(epoch from ci.stale_at) * 1000)::bigint AS ci_stale_at_ms,
  floor(extract(epoch from ci.last_reminded_at) * 1000)::bigint AS ci_last_reminded_at_ms,
  ci.stale_after_days AS ci_stale_after_days
FROM thread_base tb
LEFT JOIN eligible_item ci ON ci.id = tb.item_id
LEFT JOIN beacon_room_seen s
  ON s.user_id = $2 AND s.beacon_id = $1
 AND s.thread_item_id IS NOT DISTINCT FROM tb.item_id
LEFT JOIN LATERAL (
  SELECT
    COUNT(*)::int AS message_count,
    COUNT(*) FILTER (WHERE
      m.author_id <> $2
      AND (s.last_seen_at IS NULL OR m.created_at > s.last_seen_at)
      AND (tb.item_id IS NULL OR tb.item_kind <> $6)
    )::int AS unread_count,
    MAX(m.created_at) AS last_message_at
  FROM beacon_room_message m
  WHERE m.beacon_id = $1
    AND m.thread_item_id IS NOT DISTINCT FROM tb.item_id
    AND (tb.item_id IS NULL OR tb.item_kind <> $6)
) counts ON true
LEFT JOIN LATERAL (
  SELECT m.*
  FROM beacon_room_message m
  WHERE m.beacon_id = $1
    AND m.thread_item_id IS NOT DISTINCT FROM tb.item_id
  ORDER BY m.created_at DESC, m.id DESC
  LIMIT 1
) lm ON true
LEFT JOIN LATERAL (
  SELECT EXISTS(
    SELECT 1 FROM beacon_room_message_attachment a
    WHERE a.message_id = lm.id
  ) AS has_attachment
) att ON lm.id IS NOT NULL
LEFT JOIN coordination_item linked_ci ON linked_ci.id = lm.linked_item_id
LEFT JOIN polling pol ON pol.id = lm.linked_polling_id
LEFT JOIN beacon_fact_card bfc ON bfc.id = lm.linked_fact_card_id
ORDER BY (tb.thread_id = 'general') DESC,
         COALESCE(counts.last_message_at, tb.item_updated_at) DESC,
         tb.thread_id ASC
''',
      variables: [
        Variable<String>(beaconId),
        Variable<String>(viewerUserId),
        Variable<bool>(itemParticipantsOnly),
        Variable<bool>(includeGeneral),
        Variable<int>(excerptCharacters),
        const Variable<int>(coordinationItemKindPlan),
      ],
    ).get();

    return [for (final row in rows) _mapBeaconThreadRow(row, excerptCharacters)];
  }

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
        floor(extract(epoch from max(brm.created_at)) * 1000)::bigint
          AS last_at_ms
      FROM coordination_item ci
      INNER JOIN beacon_room_message brm ON brm.thread_item_id = ci.id
      WHERE ci.beacon_id = ANY($1::text[])
        AND ci.kind <> $5
        AND ci.status IN ($3, $4)
        AND (ci.published = true OR ci.creator_id = $2)
      GROUP BY ci.beacon_id
      ''',
      variables: [
        Variable(TypedValue(Type.textArray, beaconIds)),
        Variable<String>(viewerUserId),
        const Variable<int>(coordinationItemStatusOpen),
        const Variable<int>(coordinationItemStatusAccepted),
        const Variable<int>(coordinationItemKindPlan),
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
  Future<CoordinationItemRecord> publishRootPlan({
    required String beaconId,
    required String creatorId,
    required String title,
    String body = '',
    String? targetPersonId,
    String? linkedMessageId,
    String? syncCurrentLineText,
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

    final planText = (syncCurrentLineText ?? title).trim();
    if (planText.isNotEmpty) {
      await _db.withMutatingUser(creatorId, () async {
        await _db.into(_db.beaconRoomStates).insertOnConflictUpdate(
              BeaconRoomStatesCompanion.insert(
                beaconId: beaconId,
                currentLine: Value(planText),
                updatedBy: Value(creatorId),
                updatedAt: Value(PgDateTime(DateTime.timestamp())),
              ),
            );
      });
    }
    return item;
  }

  @override
  Future<CoordinationItemRecord> addPlanStep({
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
    // KNOWN RACE (low severity): the sibling max+1 is read outside the insert's
    // transaction, so two concurrent addPlanStep calls for the same parent can
    // pick the same ordering and produce a tie. Practically this is a same-user
    // action (a low-likelihood window) and tied ordering is non-fatal (the list
    // falls back to createdAt). A full fix needs a partial unique index on
    // (linked_parent_item_id, ordering) + insert-retry, or computing the next
    // ordering inside a parent-row-locked transaction — deferred to a migration.
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

  /// Body for standalone coordination item creation rows in the room timeline.
  @visibleForTesting
  static String roomBodyForCreatedItem({
    required String title,
    String body = '',
  }) {
    final t = title.trim();
    final b = body.trim();
    if (t.isEmpty) return b;
    if (b.isEmpty) return t;
    return '$t\n$b';
  }

  /// Standalone room row body: root plans use an empty body so the client
  /// renders a plan-announce bar (title comes from linked item snapshot).
  @visibleForTesting
  static String roomBodyForStandaloneCreatedItem({
    required int kind,
    required String title,
    String body = '',
    String? linkedMessageId,
    String? linkedParentItemId,
  }) {
    final trimmedLinkedMessageId = linkedMessageId?.trim();
    if (trimmedLinkedMessageId != null && trimmedLinkedMessageId.isNotEmpty) {
      return '';
    }
    final trimmedParentId = linkedParentItemId?.trim();
    if (kind == coordinationItemKindPlan &&
        (trimmedParentId == null || trimmedParentId.isEmpty)) {
      return '';
    }
    return roomBodyForCreatedItem(title: title, body: body);
  }

  /// Room notify row for item creation (linked source or standalone).
  /// Returns the id used as activity `sourceMessageId`.
  Future<String> _emitCreatedRoomNotify({
    required String itemId,
    required String beaconId,
    required int kind,
    required String creatorId,
    required String title,
    String body = '',
    String? linkedMessageId,
    String? linkedParentItemId,
    String? targetPersonId,
  }) async {
    final trimmedLinkedMessageId = linkedMessageId?.trim();
    if (trimmedLinkedMessageId != null && trimmedLinkedMessageId.isNotEmpty) {
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
          linkedItemId: Value(itemId),
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
            linkedNextMoveId: const Value(null),
            linkedFactCardId: const Value(null),
            linkedPollingId: const Value(null),
            linkedItemId: Value(itemId),
            linkedEventKind: const Value(coordinationEventKindCreated),
            systemPayload: Value(<String, Object?>{
              'sourceMessageId': trimmedLinkedMessageId,
            }),
            mentions: const Value([]),
            createdAt: const Value.absent(),
          ));
      return notifyId;
    }

    final roomMsgId = generateId('R');
    final standaloneBody = roomBodyForStandaloneCreatedItem(
      kind: kind,
      title: title,
      body: body,
      linkedMessageId: linkedMessageId,
      linkedParentItemId: linkedParentItemId,
    );
    await _db.managers.beaconRoomMessages.createReturning((o) => o(
          id: roomMsgId,
          beaconId: beaconId,
          authorId: creatorId,
          body: Value(standaloneBody),
          semanticMarker: const Value(null),
          linkedNextMoveId: const Value(null),
          linkedFactCardId: const Value(null),
          linkedPollingId: const Value(null),
          linkedItemId: Value(itemId),
          linkedEventKind: const Value(coordinationEventKindCreated),
          systemPayload: const Value(null),
          mentions: const Value([]),
          createdAt: const Value.absent(),
        ));
    return roomMsgId;
  }

  Future<void> _mergeSourceMessageLastStatusEvent({
    required String sourceMessageId,
    required String actorId,
    required int eventKind,
    required String atIso,
  }) async {
    final rows = await (_db.select(_db.beaconRoomMessages)
          ..where((t) => t.id.equals(sourceMessageId)))
        .get();
    if (rows.isEmpty) return;

    final merged = _mergeJsonPayload(
      rows.first.systemPayload,
      <String, Object?>{
        'lastStatusEvent': <String, Object?>{
          'eventKind': eventKind,
          'actorId': actorId,
          'at': atIso,
        },
      },
    );

    await (_db.update(_db.beaconRoomMessages)
          ..where((t) => t.id.equals(sourceMessageId)))
        .write(BeaconRoomMessagesCompanion(systemPayload: Value(merged)));
  }

  /// Deep-merge for room message [systemPayload]; used by status-event source patch.
  @visibleForTesting
  static Map<String, Object?> mergeSystemPayload(
    Object? existing,
    Map<String, Object?> patch,
  ) =>
      _mergeJsonPayload(existing, patch);

  static Map<String, Object?> _mergeJsonPayload(
    Object? existing,
    Map<String, Object?> patch,
  ) {
    var base = <String, Object?>{};
    if (existing != null) {
      if (existing is Map) {
        base = Map<String, Object?>.from(existing);
      } else if (existing is String && existing.trim().isNotEmpty) {
        try {
          final decoded = jsonDecode(existing);
          if (decoded is Map) {
            base = Map<String, Object?>.from(decoded);
          }
        } on Object catch (_) {}
      }
    }
    for (final e in patch.entries) {
      final v = e.value;
      if (v is Map && base[e.key] is Map) {
        base[e.key] = {
          ...Map<String, Object?>.from(base[e.key]! as Map),
          ...Map<String, Object?>.from(v),
        };
      } else {
        base[e.key] = v;
      }
    }
    return base;
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

  /// Content snippet stored on the activity event `diff` jsonb so the Log row
  /// can show the item's text (title/body) instead of the bare event type.
  Value<Map<String, Object?>?> _activityEventDiff({
    required String title,
    String body = '',
  }) {
    final t = title.trim();
    final b = body.trim();
    if (t.isEmpty && b.isEmpty) return const Value(null);
    return Value(<String, Object?>{
      if (t.isNotEmpty) 'title': t,
      if (b.isNotEmpty) 'body': b,
    });
  }

  /// Shared SQL predicate: viewer is responsible for coordination item `ci`.
  static const _sqlMyResponsibilityOnCi = r'''
    (
      (ci.kind = 2 AND ci.target_person_id = $1)
      OR (ci.kind = 5 AND ci.creator_id = $1)
      OR (ci.kind = 3 AND ci.target_person_id = $1)
    )
  ''';

  static const _sqlActivePublished = '''
    ci.published = true AND ci.status IN (0, 1)
  ''';

  @override
  Future<List<CoordinationResponsibilityCounts>> responsibilityCountsByBeaconIds({
    required String viewerUserId,
    required List<String> beaconIds,
  }) async {
    if (beaconIds.isEmpty) {
      return const [];
    }
    final slice = beaconIds.length > 80 ? beaconIds.sublist(0, 80) : beaconIds;

    final rows = await _db.customSelect(
      '''
SELECT ci.beacon_id AS beacon_id,
  COUNT(*) FILTER (WHERE $_sqlActivePublished AND ci.kind = 2 AND ci.target_person_id = \$1)::int AS ask_open,
  COUNT(*) FILTER (WHERE $_sqlActivePublished AND ci.kind = 2 AND ci.target_person_id = \$1
    AND COALESCE(ci.published_at, ci.created_at) > COALESCE(bis.last_seen_at, '-infinity'::timestamptz))::int AS ask_new,
  COUNT(*) FILTER (WHERE $_sqlActivePublished AND ci.kind = 5 AND ci.creator_id = \$1)::int AS promise_open,
  COUNT(*) FILTER (WHERE $_sqlActivePublished AND ci.kind = 5 AND ci.creator_id = \$1
    AND COALESCE(ci.published_at, ci.created_at) > COALESCE(bis.last_seen_at, '-infinity'::timestamptz))::int AS promise_new,
  COUNT(*) FILTER (WHERE $_sqlActivePublished AND ci.kind = 3 AND ci.target_person_id = \$1)::int AS blocker_open,
  COUNT(*) FILTER (WHERE $_sqlActivePublished AND ci.kind = 3 AND ci.target_person_id = \$1
    AND COALESCE(ci.published_at, ci.created_at) > COALESCE(bis.last_seen_at, '-infinity'::timestamptz))::int AS blocker_new,
  COUNT(*) FILTER (WHERE $_sqlActivePublished AND ci.kind IN (2, 3, 5) AND NOT ($_sqlMyResponsibilityOnCi))::int AS others_open
FROM coordination_item ci
LEFT JOIN beacon_items_seen bis
  ON bis.user_id = \$1 AND bis.beacon_id = ci.beacon_id
WHERE ci.beacon_id = ANY(\$2::text[])
GROUP BY ci.beacon_id
''',
      variables: [
        Variable<String>(viewerUserId),
        Variable(TypedValue(Type.textArray, slice)),
      ],
    ).get();

    final byBeacon = {
      for (final row in rows)
        row.read<String>('beacon_id'): CoordinationResponsibilityCounts(
          beaconId: row.read<String>('beacon_id'),
          askOpen: row.read<int>('ask_open'),
          askNew: row.read<int>('ask_new'),
          promiseOpen: row.read<int>('promise_open'),
          promiseNew: row.read<int>('promise_new'),
          blockerOpen: row.read<int>('blocker_open'),
          blockerNew: row.read<int>('blocker_new'),
          othersOpenCount: row.read<int>('others_open'),
        ),
    };

    return [
      for (final bid in slice)
        byBeacon[bid] ??
            CoordinationResponsibilityCounts(beaconId: bid),
    ];
  }

  @override
  Future<List<CoordinationItemWithCounts>> myResponsibilityItemsByBeacon({
    required String viewerUserId,
    required String beaconId,
  }) async {
    final idRows = await _db.customSelect(
      r'''
SELECT ci.id AS id
FROM coordination_item ci
WHERE ci.beacon_id = $2
  AND ci.published = true
  AND ci.status IN ($6, $7)
  AND (
    (ci.kind = $3 AND ci.target_person_id = $1)
    OR (ci.kind = $4 AND ci.creator_id = $1)
    OR (ci.kind = $5 AND ci.target_person_id = $1)
  )
ORDER BY ci.kind, ci.created_at DESC
''',
      variables: [
        Variable<String>(viewerUserId),
        Variable<String>(beaconId),
        const Variable<int>(coordinationItemKindAsk),
        const Variable<int>(coordinationItemKindPromise),
        const Variable<int>(coordinationItemKindBlocker),
        const Variable<int>(coordinationItemStatusOpen),
        const Variable<int>(coordinationItemStatusAccepted),
      ],
    ).get();

    if (idRows.isEmpty) {
      return const [];
    }

    final ids = idRows.map((r) => r.read<String>('id')).toList();
    final items = await (_db.select(_db.coordinationItems)
          ..where((t) => t.id.isIn(ids)))
        .get();

    final order = {for (var i = 0; i < ids.length; i++) ids[i]: i};
    items.sort((a, b) => order[a.id]!.compareTo(order[b.id]!));

    final countRows = await _db.customSelect(
      r'''
      SELECT ci.id AS item_id,
        (SELECT COUNT(*)::bigint FROM beacon_room_message m
         WHERE m.thread_item_id = ci.id
           AND ci.kind <> $3) AS message_count,
        (SELECT COUNT(*)::bigint FROM beacon_room_message m
         WHERE m.thread_item_id = ci.id
           AND ci.kind <> $3
           AND m.author_id <> $2
           AND (s.last_seen_at IS NULL OR m.created_at > s.last_seen_at)
        ) AS unread_count
      FROM coordination_item ci
      LEFT JOIN beacon_room_seen s
        ON s.thread_item_id = ci.id AND s.user_id = $2
      WHERE ci.id = ANY($1::text[])
      ''',
      variables: [
        Variable(TypedValue(Type.textArray, ids)),
        Variable<String>(viewerUserId),
        const Variable<int>(coordinationItemKindPlan),
      ],
    ).get();

    final seenRows = await (_db.select(_db.beaconRoomSeen)
          ..where((t) => t.userId.equals(viewerUserId))
          ..where((t) => t.threadItemId.isIn(ids)))
        .get();
    final lastSeenByItemId = {
      for (final row in seenRows)
        if (row.threadItemId != null) row.threadItemId!: row.lastSeenAt.dateTime,
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
          item: item.toRecord(),
          messageCount: countsByItemId[item.id]?.messageCount ?? 0,
          unreadCount: countsByItemId[item.id]?.unreadCount ?? 0,
          lastSeenAt: lastSeenByItemId[item.id],
        ),
    ];
  }

  @override
  Future<DateTime?> getBeaconItemsSeen({
    required String userId,
    required String beaconId,
  }) async {
    final row = await (_db.select(_db.beaconItemsSeen)
          ..where((t) => t.userId.equals(userId))
          ..where((t) => t.beaconId.equals(beaconId)))
        .getSingleOrNull();
    return row?.lastSeenAt.dateTime.toUtc();
  }

  @override
  Future<DateTime> markBeaconItemsSeen({
    required String userId,
    required String beaconId,
  }) async {
    return _db.withMutatingUser(userId, () async {
      final existing = await getBeaconItemsSeen(userId: userId, beaconId: beaconId);

      final maxRow = await _db.customSelect(
        r'''
SELECT floor(extract(epoch from max(COALESCE(ci.published_at, ci.created_at))) * 1000)::bigint AS max_ms
FROM coordination_item ci
WHERE ci.beacon_id = $2
  AND ci.published = true
  AND ci.status IN ($6, $7)
  AND (
    (ci.kind = $3 AND ci.target_person_id = $1)
    OR (ci.kind = $4 AND ci.creator_id = $1)
    OR (ci.kind = $5 AND ci.target_person_id = $1)
  )
''',
        variables: [
          Variable<String>(userId),
          Variable<String>(beaconId),
          const Variable<int>(coordinationItemKindAsk),
          const Variable<int>(coordinationItemKindPromise),
          const Variable<int>(coordinationItemKindBlocker),
          const Variable<int>(coordinationItemStatusOpen),
          const Variable<int>(coordinationItemStatusAccepted),
        ],
      ).getSingleOrNull();

      var at = maxRow?.read<int?>('max_ms') != null
          ? DateTime.fromMillisecondsSinceEpoch(
              maxRow!.read<int>('max_ms'),
              isUtc: true,
            )
          : DateTime.fromMillisecondsSinceEpoch(0, isUtc: true);

      if (at.millisecondsSinceEpoch == 0) {
        at = DateTime.timestamp().toUtc();
      }
      if (existing != null && existing.isAfter(at)) {
        at = existing.toUtc();
      }

      final seenAtIso = at.toUtc().toIso8601String();
      await _db.customStatement(
        'INSERT INTO beacon_items_seen (user_id, beacon_id, last_seen_at) '
        r'VALUES ($1, $2, $3::timestamptz) '
        'ON CONFLICT (user_id, beacon_id) '
        'DO UPDATE SET last_seen_at = GREATEST(beacon_items_seen.last_seen_at, EXCLUDED.last_seen_at)',
        [userId, beaconId, seenAtIso],
      );

      final persisted = await getBeaconItemsSeen(userId: userId, beaconId: beaconId);
      return persisted ?? at;
    });
  }
}

BeaconThreadRecord _mapBeaconThreadRow(
  QueryRow row,
  int excerptCharacters,
) {
  final messageCount = row.read<int>('message_count');
  final unreadCount = row.read<int>('unread_count');
  final lastSeenAt = _readOptionalEpochMs(row, 'thread_last_seen_at_ms');
  final lastMessageAt = _readOptionalEpochMs(row, 'last_message_at_ms');
  final lastMessageAuthorId = row.readNullable<String>('last_message_author_id');

  final preview = lastMessageAuthorId != null
      ? _mapThreadMessagePreview(
          body: row.readNullable<String>('lm_body'),
          semanticMarker: row.readNullable<int>('lm_semantic_marker'),
          linkedItemId: row.readNullable<String>('lm_linked_item_id'),
          linkedEventKind: row.readNullable<int>('lm_linked_event_kind'),
          hasAttachment: row.read<bool>('lm_has_attachment'),
          systemPayloadJson: row.readNullable<String>('lm_system_payload_json'),
          linkedItemKind: row.readNullable<int>('lm_linked_item_kind'),
          linkedItemTitle: row.readNullable<String>('lm_linked_item_title'),
          pollTitle: row.readNullable<String>('lm_poll_title'),
          factTitle: row.readNullable<String>('lm_fact_title'),
          factVisibility: row.readNullable<int>('lm_fact_visibility'),
          excerptCharacters: excerptCharacters,
        )
      : null;

  final itemId = row.readNullable<String>('ci_id');
  CoordinationItemWithCounts? item;
  if (itemId != null) {
    item = CoordinationItemWithCounts(
      item: CoordinationItemRecord(
        id: itemId,
        beaconId: row.read<String>('ci_beacon_id'),
        kind: row.read<int>('ci_kind'),
        status: row.read<int>('ci_status'),
        title: row.read<String>('ci_title'),
        body: row.read<String>('ci_body'),
        creatorId: row.read<String>('ci_creator_id'),
        targetPersonId: row.readNullable<String>('ci_target_person_id'),
        acceptedById: row.readNullable<String>('ci_accepted_by_id'),
        targetItemId: row.readNullable<String>('ci_target_item_id'),
        targetMessageId: row.readNullable<String>('ci_target_message_id'),
        linkedMessageId: row.readNullable<String>('ci_linked_message_id'),
        linkedParentItemId: row.readNullable<String>('ci_linked_parent_item_id'),
        ordering: row.read<int>('ci_ordering'),
        source: row.read<int>('ci_source'),
        published: row.read<bool>('ci_published'),
        createdAt: _readEpochMs(row, 'ci_created_at_ms'),
        updatedAt: _readEpochMs(row, 'ci_updated_at_ms'),
        publishedAt: _readOptionalEpochMs(row, 'ci_published_at_ms'),
        resolvedAt: _readOptionalEpochMs(row, 'ci_resolved_at_ms'),
        cancelledAt: _readOptionalEpochMs(row, 'ci_cancelled_at_ms'),
        staleAt: _readOptionalEpochMs(row, 'ci_stale_at_ms'),
        lastRemindedAt: _readOptionalEpochMs(row, 'ci_last_reminded_at_ms'),
        staleAfterDays: row.readNullable<int>('ci_stale_after_days'),
      ),
      messageCount: messageCount,
      unreadCount: unreadCount,
      lastSeenAt: lastSeenAt,
    );
  }

  return BeaconThreadRecord(
    threadId: row.read<String>('thread_id'),
    threadKind: row.read<String>('thread_kind'),
    unreadCount: unreadCount,
    messageCount: messageCount,
    lastSeenAt: lastSeenAt,
    lastMessageAt: lastMessageAt,
    lastMessageAuthorId: lastMessageAuthorId,
    lastMessagePreview: preview,
    item: item,
  );
}

ThreadMessagePreviewRecord _mapThreadMessagePreview({
  required String? body,
  required int? semanticMarker,
  required String? linkedItemId,
  required int? linkedEventKind,
  required bool hasAttachment,
  required String? systemPayloadJson,
  required int? linkedItemKind,
  required String? linkedItemTitle,
  required String? pollTitle,
  required String? factTitle,
  required int? factVisibility,
  required int excerptCharacters,
}) {
  final payload = _readSystemPayload(systemPayloadJson);
  final joinedUserId = payload?['joinedUserId'] as String?;
  final admissionReason = payload?['admissionReason'] as String?;

  if (semanticMarker == null &&
      linkedItemId != null &&
      linkedItemId.isNotEmpty &&
      linkedEventKind != null) {
    return ThreadMessagePreviewRecord(
      kind: ThreadMessagePreviewKind.coordination,
      hasAttachment: hasAttachment,
      linkedItemId: linkedItemId,
      linkedEventKind: linkedEventKind,
      itemKind: linkedItemKind,
      itemTitle: linkedItemTitle,
    );
  }

  if (semanticMarker != null) {
    final kind = _previewKindForSemanticMarker(semanticMarker);
    return ThreadMessagePreviewRecord(
      kind: kind,
      hasAttachment: hasAttachment,
      joinedUserId: kind == ThreadMessagePreviewKind.join ? joinedUserId : null,
      admissionReason:
          kind == ThreadMessagePreviewKind.join ? admissionReason : null,
      linkedItemId: kind == ThreadMessagePreviewKind.coordination
          ? linkedItemId
          : null,
      linkedEventKind: kind == ThreadMessagePreviewKind.coordination
          ? linkedEventKind
          : null,
      itemKind: _itemKindForPreview(kind, linkedItemKind),
      itemTitle: _itemTitleForPreview(kind, linkedItemTitle),
      pollTitle: kind == ThreadMessagePreviewKind.poll ? pollTitle : null,
      factTitle: kind == ThreadMessagePreviewKind.factPinned ? factTitle : null,
      factVisibility:
          kind == ThreadMessagePreviewKind.factPinned ? factVisibility : null,
    );
  }

  final trimmedBody = body?.trim() ?? '';
  if (trimmedBody.isNotEmpty) {
    return ThreadMessagePreviewRecord(
      kind: ThreadMessagePreviewKind.text,
      excerpt: _truncateExcerpt(trimmedBody, excerptCharacters),
      hasAttachment: hasAttachment,
    );
  }

  if (hasAttachment) {
    return const ThreadMessagePreviewRecord(
      kind: ThreadMessagePreviewKind.attachment,
      hasAttachment: true,
    );
  }

  throw StateError('Unmapped last-message preview family');
}

int _previewKindForSemanticMarker(int marker) => switch (marker) {
      BeaconRoomSemanticMarker.updatePlan => ThreadMessagePreviewKind.planUpdated,
      BeaconRoomSemanticMarker.pinFactPublic ||
      BeaconRoomSemanticMarker.pinFactPrivate =>
        ThreadMessagePreviewKind.factPinned,
      BeaconRoomSemanticMarker.participantStatusChanged =>
        ThreadMessagePreviewKind.participantStatus,
      BeaconRoomSemanticMarker.blocker => ThreadMessagePreviewKind.coordination,
      BeaconRoomSemanticMarker.needInfo => ThreadMessagePreviewKind.needInfo,
      BeaconRoomSemanticMarker.done => ThreadMessagePreviewKind.done,
      BeaconRoomSemanticMarker.poll => ThreadMessagePreviewKind.poll,
      BeaconRoomSemanticMarker.participantJoined => ThreadMessagePreviewKind.join,
      _ => throw StateError('Unknown semantic marker: $marker'),
    };

int? _itemKindForPreview(int kind, int? linkedItemKind) =>
    kind == ThreadMessagePreviewKind.coordination ? linkedItemKind : null;

String? _itemTitleForPreview(int kind, String? linkedItemTitle) =>
    kind == ThreadMessagePreviewKind.coordination ? linkedItemTitle : null;

String _truncateExcerpt(String body, int excerptCharacters) {
  if (body.length <= excerptCharacters) {
    return body;
  }
  return body.substring(0, excerptCharacters);
}

DateTime _readEpochMs(QueryRow row, String name) =>
    DateTime.fromMillisecondsSinceEpoch(row.read<int>(name), isUtc: true);

DateTime? _readOptionalEpochMs(QueryRow row, String name) {
  final value = row.readNullable<int>(name);
  if (value == null) {
    return null;
  }
  return DateTime.fromMillisecondsSinceEpoch(value, isUtc: true);
}

Map<String, Object?>? _readSystemPayload(String? raw) {
  if (raw == null || raw.isEmpty || raw == 'null') {
    return null;
  }
  final decoded = jsonDecode(raw);
  if (decoded is Map) {
    return Map<String, Object?>.from(decoded);
  }
  return null;
}
