import 'package:drift/drift.dart';
import 'package:injectable/injectable.dart';
import 'package:tentura_root/domain/entity/beacon_child_command_outcome.dart';
import 'package:tentura_root/domain/entity/beacon_creation_context.dart';

import 'package:tentura_server/consts/beacon_hierarchy_consts.dart';
import 'package:tentura_server/domain/port/beacon_hierarchy_command_port.dart';

import '../database/tentura_db.dart';

@Singleton(as: BeaconHierarchyCommandPort)
class BeaconHierarchyCommandRepository implements BeaconHierarchyCommandPort {
  const BeaconHierarchyCommandRepository(this._database);

  final TenturaDb _database;

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

    final parentId = switch (creationContext) {
      BeaconCreationContextStandalone() => null,
      BeaconCreationContextChild(:final parentBeaconId) => parentBeaconId,
      BeaconCreationContextPromotedChild(:final parentBeaconId) => parentBeaconId,
    };
    final sourceMessageId = creationContext is BeaconCreationContextPromotedChild
        ? creationContext.sourceMessageId
        : null;

    if (resultBeaconId != null &&
        parentId != null &&
        outcome == BeaconChildCommandOutcome.created &&
        creationContext is BeaconCreationContextPromotedChild) {
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
  published_at = COALESCE(public.beacon_promotions.published_at, EXCLUDED.published_at)
''',
        [
          resultBeaconId,
          parentId,
        sourceMessageId,
        actorUserId,
      ],
    );
    }

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
