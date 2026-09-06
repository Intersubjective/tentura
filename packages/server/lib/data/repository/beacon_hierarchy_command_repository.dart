import 'dart:convert';

import 'package:drift/drift.dart';
import 'package:injectable/injectable.dart';
import 'package:postgres/postgres.dart' show Severity;
import 'package:tentura_root/domain/entity/beacon_child_command_outcome.dart';
import 'package:tentura_root/domain/entity/beacon_creation_context.dart';
import 'package:tentura_root/domain/entity/beacon_status.dart';

import 'package:tentura_server/consts/beacon_hierarchy_consts.dart';
import 'package:tentura_server/domain/policy/beacon_promotion_eligibility_policy.dart';
import 'package:tentura_server/domain/port/beacon_hierarchy_command_port.dart';
import 'package:tentura_server/utils/id.dart';

import '../database/tentura_db.dart';

@Singleton(as: BeaconHierarchyCommandPort)
class BeaconHierarchyCommandRepository implements BeaconHierarchyCommandPort {
  const BeaconHierarchyCommandRepository(this._database);

  final TenturaDb _database;

  static const _promotionSourceUniqueConstraint =
      'beacon_promotions_published_source_uidx';

  @override
  Future<BeaconChildCommandRecord?> findCommand({
    required String actorUserId,
    required String clientCommandId,
  }) async {
    final rows = await _database
        .customSelect(
          r'''
SELECT
  actor_user_id,
  client_command_id,
  normalized_input_hash,
  result_beacon_id,
  result_state,
  deleted
FROM public.beacon_child_commands
WHERE actor_user_id = $1 AND client_command_id = $2
''',
          variables: [
            Variable<String>(actorUserId),
            Variable<String>(clientCommandId),
          ],
        )
        .get();
    if (rows.isEmpty) {
      return null;
    }
    final row = rows.single;
    return BeaconChildCommandRecord(
      actorUserId: row.read<String>('actor_user_id'),
      clientCommandId: row.read<String>('client_command_id'),
      normalizedInputHash: row.read<String>('normalized_input_hash'),
      outcome: _outcomeFromDb(row.read<int>('result_state')),
      resultBeaconId: row.readNullable<String>('result_beacon_id'),
      deleted: row.read<bool>('deleted'),
    );
  }

  @override
  Future<BeaconChildCreateResult> recordCreateOutcome({
    required String actorUserId,
    required String clientCommandId,
    required String normalizedInputHash,
    required BeaconCreationContext creationContext,
    required BeaconChildCommandOutcome outcome,
    String? resultBeaconId,
  }) async {
    await _database.customStatement(
      r'''
INSERT INTO public.beacon_child_commands (
  actor_user_id,
  client_command_id,
  normalized_input_hash,
  result_beacon_id,
  result_state,
  deleted,
  updated_at
) VALUES (
  $1, $2, $3, $4, $5, false, now()
)
ON CONFLICT (actor_user_id, client_command_id) DO UPDATE
SET
  normalized_input_hash = EXCLUDED.normalized_input_hash,
  result_beacon_id = EXCLUDED.result_beacon_id,
  result_state = EXCLUDED.result_state,
  deleted = false,
  updated_at = now()
WHERE public.beacon_child_commands.normalized_input_hash = EXCLUDED.normalized_input_hash
''',
      [
        actorUserId,
        clientCommandId,
        normalizedInputHash,
        resultBeaconId,
        _outcomeToDb(outcome),
      ],
    );

    return BeaconChildCreateResult(outcome: outcome, beaconId: resultBeaconId);
  }

  @override
  Future<void> markCommandDeleted({
    required String actorUserId,
    required String clientCommandId,
  }) => _database.customStatement(
    r'''
UPDATE public.beacon_child_commands
SET deleted = true,
    result_beacon_id = NULL,
    updated_at = now()
WHERE actor_user_id = $1 AND client_command_id = $2
''',
    [actorUserId, clientCommandId],
  );

  @override
  Future<String?> findPublishedChildForSourceMessage({
    required String sourceMessageId,
  }) async {
    final rows = await _database
        .customSelect(
          r'''
SELECT child_beacon_id
FROM public.beacon_promotions
WHERE source_message_id = $1
  AND published_at IS NOT NULL
''',
          variables: [Variable<String>(sourceMessageId)],
        )
        .get();
    if (rows.isEmpty) {
      return null;
    }
    return rows.single.read<String>('child_beacon_id');
  }

  @override
  Future<void> lockBeaconRows(List<String> beaconIds) async {
    if (beaconIds.isEmpty) {
      return;
    }
    final sorted = [...beaconIds]..sort();
    await _database.customStatement(
      r'''
SELECT id
FROM public.beacon
WHERE id = ANY($1::text[])
ORDER BY id
FOR UPDATE
''',
      [sorted],
    );
  }

  @override
  Future<void> lockChildCommandRow({
    required String actorUserId,
    required String clientCommandId,
  }) => _database.customStatement(
    r'''
SELECT actor_user_id
FROM public.beacon_child_commands
WHERE actor_user_id = $1 AND client_command_id = $2
FOR UPDATE
''',
    [actorUserId, clientCommandId],
  );

  @override
  Future<void> lockPromotionRows({
    String? childBeaconId,
    String? sourceMessageId,
  }) async {
    if (childBeaconId != null) {
      await _database.customStatement(
        r'''
SELECT child_beacon_id
FROM public.beacon_promotions
WHERE child_beacon_id = $1
FOR UPDATE
''',
        [childBeaconId],
      );
    }
    if (sourceMessageId != null) {
      await _database.customStatement(
        r'''
SELECT child_beacon_id
FROM public.beacon_promotions
WHERE source_message_id = $1
FOR UPDATE
''',
        [sourceMessageId],
      );
    }
  }

  @override
  Future<bool> effectiveAdmission({
    required String beaconId,
    required String viewerId,
  }) async {
    final row = await _database
        .customSelect(
          'SELECT public.beacon_effective_admission(\$1, \$2) AS allowed',
          variables: [
            Variable<String>(beaconId),
            Variable<String>(viewerId),
          ],
        )
        .getSingle();
    return row.read<bool>('allowed');
  }

  @override
  Future<BeaconParentValidationRow?> loadParentValidationRow(
    String parentBeaconId,
  ) async {
    final rows = await _database
        .customSelect(
          r'''
SELECT id, user_id, status, published_at
FROM public.beacon
WHERE id = $1
''',
          variables: [Variable<String>(parentBeaconId)],
        )
        .get();
    if (rows.isEmpty) {
      return null;
    }
    final row = rows.single;
    final status = BeaconStatus.fromSmallint(row.read<int>('status'));
    return BeaconParentValidationRow(
      id: row.read<String>('id'),
      ownerId: row.read<String>('user_id'),
      status: status,
      isPublished:
          status != BeaconStatus.draft &&
          row.readNullable<String>('published_at') != null,
    );
  }

  @override
  Future<BeaconPromotionSourceFacts?> loadPromotionSourceFacts({
    required String parentBeaconId,
    required String sourceMessageId,
  }) async {
    final rows = await _database
        .customSelect(
          r'''
SELECT
  m.id,
  m.beacon_id,
  m.author_id,
  m.body,
  m.thread_item_id,
  m.system_message_kind,
  m.system_payload,
  m.semantic_marker,
  m.linked_item_id,
  m.linked_polling_id,
  m.linked_event_kind,
  m.linked_next_move_id,
  m.linked_fact_card_id
FROM public.beacon_room_message m
WHERE m.id = $1
  AND m.beacon_id = $2
''',
          variables: [
            Variable<String>(sourceMessageId),
            Variable<String>(parentBeaconId),
          ],
        )
        .get();
    if (rows.isEmpty) {
      return null;
    }
    final row = rows.single;
    return BeaconPromotionSourceFacts(
      messageId: row.read<String>('id'),
      beaconId: row.read<String>('beacon_id'),
      authorId: row.readNullable<String>('author_id'),
      body: row.read<String>('body'),
      threadItemId: row.readNullable<String>('thread_item_id'),
      systemMessageKind: row.readNullable<int>('system_message_kind'),
      systemPayload: _readJsonMap(row, 'system_payload'),
      semanticMarker: row.readNullable<int>('semantic_marker'),
      linkedItemId: row.readNullable<String>('linked_item_id'),
      linkedPollingId: row.readNullable<String>('linked_polling_id'),
      linkedEventKind: row.readNullable<int>('linked_event_kind'),
      linkedNextMoveId: row.readNullable<String>('linked_next_move_id'),
      linkedFactCardId: row.readNullable<String>('linked_fact_card_id'),
    );
  }

  @override
  Future<BeaconChildPromotionRow?> loadPromotionForChild(
    String childBeaconId,
  ) async {
    final rows = await _database
        .customSelect(
          r'''
SELECT child_beacon_id, parent_beacon_id, source_message_id, published_at
FROM public.beacon_promotions
WHERE child_beacon_id = $1
''',
          variables: [Variable<String>(childBeaconId)],
        )
        .get();
    if (rows.isEmpty) {
      return null;
    }
    final row = rows.single;
    final publishedRaw = row.readNullable<String>('published_at');
    return BeaconChildPromotionRow(
      childBeaconId: row.read<String>('child_beacon_id'),
      parentBeaconId: row.read<String>('parent_beacon_id'),
      sourceMessageId: row.readNullable<String>('source_message_id'),
      publishedAt: publishedRaw == null
          ? null
          : DateTime.parse(publishedRaw).toUtc(),
    );
  }

  @override
  Future<void> upsertDraftPromotion({
    required String childBeaconId,
    required String parentBeaconId,
    required String? sourceMessageId,
    required String promoterUserId,
  }) => _database.customStatement(
    r'''
INSERT INTO public.beacon_promotions (
  child_beacon_id,
  parent_beacon_id,
  source_message_id,
  promoter_user_id,
  published_at
) VALUES ($1, $2, $3, $4, NULL)
ON CONFLICT (child_beacon_id) DO UPDATE
SET
  parent_beacon_id = EXCLUDED.parent_beacon_id,
  source_message_id = EXCLUDED.source_message_id,
  promoter_user_id = EXCLUDED.promoter_user_id
WHERE public.beacon_promotions.published_at IS NULL
''',
    [childBeaconId, parentBeaconId, sourceMessageId, promoterUserId],
  );

  @override
  Future<void> markPromotionPublished({
    required String childBeaconId,
    required String parentBeaconId,
    required String? sourceMessageId,
    required String promoterUserId,
  }) async {
    try {
      await _database.customStatement(
        r'''
INSERT INTO public.beacon_promotions (
  child_beacon_id,
  parent_beacon_id,
  source_message_id,
  promoter_user_id,
  published_at
) VALUES ($1, $2, $3, $4, now())
ON CONFLICT (child_beacon_id) DO UPDATE
SET
  parent_beacon_id = EXCLUDED.parent_beacon_id,
  source_message_id = EXCLUDED.source_message_id,
  promoter_user_id = EXCLUDED.promoter_user_id,
  published_at = COALESCE(public.beacon_promotions.published_at, now())
WHERE public.beacon_promotions.published_at IS NULL
''',
        [childBeaconId, parentBeaconId, sourceMessageId, promoterUserId],
      );
    } on Object catch (error) {
      final existing = await _readPromotionConflictChildId(error);
      if (existing != null) {
        throw BeaconPromotionPublishConflict(existing);
      }
      rethrow;
    }
  }

  @override
  Future<String> insertChildCreationNotice({
    required String parentBeaconId,
    required String childBeaconId,
    String? sourceMessageId,
    required String actorUserId,
  }) async {
    final messageId = generateId('R');
    final identity = 'child_created:$childBeaconId';
    final payload = <String, Object?>{
      'version': 1,
      'kind': 'childCreated',
      'childBeaconId': childBeaconId,
      if (sourceMessageId != null) 'sourceMessageId': sourceMessageId,
    };
    await _database.customStatement(
      r'''
INSERT INTO public.beacon_room_message (
  id,
  beacon_id,
  author_id,
  body,
  thread_item_id,
  system_message_kind,
  hierarchy_notice_identity,
  system_payload,
  created_at
) VALUES (
  $1, $2, $3, '', NULL, $4, $5, $6::jsonb, now()
)
ON CONFLICT (hierarchy_notice_identity)
WHERE hierarchy_notice_identity IS NOT NULL
DO NOTHING
''',
      [
        messageId,
        parentBeaconId,
        actorUserId,
        BeaconRoomSystemMessageKind.childCreated,
        identity,
        jsonEncode(payload),
      ],
    );
    final rows = await _database
        .customSelect(
          r'''
SELECT id
FROM public.beacon_room_message
WHERE hierarchy_notice_identity = $1
''',
          variables: [Variable<String>(identity)],
        )
        .get();
    return rows.single.read<String>('id');
  }

  Future<String?> _readPromotionConflictChildId(Object error) async {
    final message = error.toString();
    if (!message.contains(_promotionSourceUniqueConstraint)) {
      return null;
    }
    final match = RegExp(
      r'Key \(source_message_id\)=\(([^)]+)\)',
    ).firstMatch(message);
    if (match == null) {
      return await _findConflictFromDetail(message);
    }
    final sourceMessageId = match.group(1);
    if (sourceMessageId == null) {
      return null;
    }
    return findPublishedChildForSourceMessage(
      sourceMessageId: sourceMessageId,
    );
  }

  Future<String?> _findConflictFromDetail(String message) async {
    final sourceMatch = RegExp(
      r'source_message_id[=:]+\s*([A-Za-z0-9]+)',
    ).firstMatch(message);
    final sourceId = sourceMatch?.group(1);
    if (sourceId == null) {
      return null;
    }
    return findPublishedChildForSourceMessage(sourceMessageId: sourceId);
  }

  static Map<String, Object?>? _readJsonMap(QueryRow row, String column) {
    final raw = row.readNullable<Object>(column);
    if (raw == null) {
      return null;
    }
    if (raw is Map<String, Object?>) {
      return raw;
    }
    if (raw is String) {
      final decoded = jsonDecode(raw);
      if (decoded is Map<String, Object?>) {
        return decoded;
      }
    }
    return null;
  }

  static int _outcomeToDb(BeaconChildCommandOutcome outcome) => switch (outcome) {
    BeaconChildCommandOutcome.created => BeaconChildCommandResultState.created,
    BeaconChildCommandOutcome.replayed => BeaconChildCommandResultState.replayed,
    BeaconChildCommandOutcome.alreadyPromoted =>
      BeaconChildCommandResultState.alreadyPromoted,
  };

  static BeaconChildCommandOutcome _outcomeFromDb(int value) => switch (value) {
    BeaconChildCommandResultState.created => BeaconChildCommandOutcome.created,
    BeaconChildCommandResultState.replayed => BeaconChildCommandOutcome.replayed,
    BeaconChildCommandResultState.alreadyPromoted =>
      BeaconChildCommandOutcome.alreadyPromoted,
    _ => BeaconChildCommandOutcome.created,
  };
}
