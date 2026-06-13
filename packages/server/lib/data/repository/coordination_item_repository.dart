import 'dart:convert';

import 'package:injectable/injectable.dart';
import 'package:meta/meta.dart';
import 'package:drift_postgres/drift_postgres.dart';

import 'package:tentura_server/consts/coordination_item_consts.dart';
import 'package:tentura_server/domain/coordination_stale_rules.dart';
import 'package:tentura_server/domain/entity/beacon_activity_event_entity.dart';
import 'package:tentura_server/domain/entity/coordination_item_entity.dart';
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
                  ));

          final roomMsgIdForActivity = await _emitCreatedRoomNotify(
            itemId: id,
            beaconId: beaconId,
            kind: kind,
            creatorId: creatorId,
            linkedMessageId: linkedMessageId,
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
    final anchorId = existing.linkedMessageId?.trim();
    final hasAnchor = anchorId != null && anchorId.isNotEmpty;
    final nowIso = DateTime.timestamp().toUtc().toIso8601String();

    final roomMsgId = generateId('R');
    await _db.managers.beaconRoomMessages.createReturning((o) => o(
          id: roomMsgId,
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
        sourceMessageId: Value(roomMsgId),
        coordinationItemId: Value(existing.id),
        diff: _activityEventDiff(title: existing.title, body: existing.body),
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
    int? staleAfterDays,
  }) =>
      _db.withMutatingUser(creatorId, () async {
        final id = CoordinationItemEntity.newId;
        final now = PgDateTime(DateTime.timestamp());
        final days = validateStaleAfterDays(staleAfterDays);
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
            staleAfterDays: Value(days),
            source: const Value(coordinationItemSourceDefault),
            published: const Value(false),
          ),
        );
      });

  @override
  Future<CoordinationItem> createDraftPromise({
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
        return _db.managers.coordinationItems.createReturning(
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
        );
      });

  @override
  Future<CoordinationItem> publishDraft({
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
              targetPersonId: Value(targetPersonId),
              updatedAt: Value(now),
              staleAfterDays: Value(days),
              staleAt: Value(
                staleAtValue == null ? null : PgDateTime(staleAtValue),
              ),
            ),
          );

          final updated =
              await (_db.select(_db.coordinationItems)..where((t) => t.id.equals(id))).getSingle();

          final roomMsgIdForActivity = await _emitCreatedRoomNotify(
            itemId: id,
            beaconId: updated.beaconId,
            kind: updated.kind,
            creatorId: actorId,
            linkedMessageId: updated.linkedMessageId,
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
                      currentLine: Value(planText),
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
    String? targetPersonId,
    int? staleAfterDays,
  }) =>
      _db.withMutatingUser(creatorId, () async {
        final id = CoordinationItemEntity.newId;
        final now = PgDateTime(DateTime.timestamp());
        final days = validateStaleAfterDays(staleAfterDays);
        return _db.managers.coordinationItems.createReturning(
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
        );
      });

  @override
  Future<CoordinationItem> publishDraftBlocker({
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
            targetPersonId: null,
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

          return updated;
        });
      });

  @override
  Future<CoordinationItem> updateDraftBlocker({
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
  Future<CoordinationItem?> tryClaimRemind({
    required String itemId,
    required String actorId,
  }) =>
      _db.withMutatingUser(actorId, () async {
        final now = PgDateTime(DateTime.timestamp());
        final cooldownBefore = PgDateTime(
          DateTime.timestamp().subtract(
            Duration(hours: kCoordinationItemRemindCooldownHours),
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
          item: item,
          messageCount: countsByItemId[item.id]?.messageCount ?? 0,
          unreadCount: countsByItemId[item.id]?.unreadCount ?? 0,
          lastSeenAt: lastSeenByItemId[item.id],
        ),
    ];
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
  Future<CoordinationItem> publishRootPlan({
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
    final standaloneBody = roomBodyForCreatedItem(title: title, body: body);
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
    Map<String, Object?> base = {};
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
}
