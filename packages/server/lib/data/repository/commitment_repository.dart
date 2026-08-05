import 'package:drift/drift.dart';
import 'package:injectable/injectable.dart';

import 'package:tentura_server/domain/commitment/commitment_event.dart';
import 'package:tentura_server/domain/commitment/commitment_event_kind.dart';
import 'package:tentura_server/domain/commitment/commitment_state.dart';
import 'package:tentura_server/domain/port/commitment_repository_port.dart';

import '../database/tentura_db.dart';

Future<void> insertCommitmentEvent(
  TenturaDb db, {
  required String beaconId,
  required String userId,
  required String actorUserId,
  required CommitmentEventKind kind,
  String? reason,
}) => db.customInsert(
  r'''
INSERT INTO public.beacon_commitment_event
  (id, beacon_id, user_id, actor_user_id, kind, reason)
VALUES ($1, $2, $3, $4, $5, $6)
''',
  variables: [
    Variable<String>(CommitmentEvent.newId),
    Variable<String>(beaconId),
    Variable<String>(userId),
    Variable<String>(actorUserId),
    Variable<int>(kind.smallintValue),
    Variable<String>(reason),
  ],
  updates: {db.beaconCommitmentEvents},
);

@Injectable(
  as: CommitmentRepositoryPort,
  env: [Environment.dev, Environment.prod],
  order: 1,
)
class CommitmentRepository implements CommitmentRepositoryPort {
  CommitmentRepository(this._database);

  final TenturaDb _database;

  @override
  Future<void> record({
    required String beaconId,
    required String userId,
    required String actorUserId,
    required CommitmentEventKind kind,
    String? reason,
  }) => _database.withMutatingUser(
    actorUserId,
    () async {
      await insertCommitmentEvent(
        _database,
        beaconId: beaconId,
        userId: userId,
        actorUserId: actorUserId,
        kind: kind,
        reason: reason,
      );
      final events = await eventsForPair(beaconId: beaconId, userId: userId);
      final stakeState = currentStakeState(events).index;
      await _database.customUpdate(
        r'''
UPDATE public.beacon_help_offer
SET stake_state = $1
WHERE beacon_id = $2 AND user_id = $3
''',
        variables: [
          Variable<int>(stakeState),
          Variable<String>(beaconId),
          Variable<String>(userId),
        ],
        updates: {_database.beaconHelpOffers},
      );
    },
  );

  @override
  Future<Map<String, List<CommitmentEvent>>> eventsByUser(
    String beaconId,
  ) async {
    final rows = await _selectRows(
      whereSql: 'beacon_id = \$1',
      variables: [Variable<String>(beaconId)],
      orderSql: 'ORDER BY user_id, seq ASC',
    );
    final grouped = <String, List<CommitmentEvent>>{};
    for (final row in rows) {
      final event = _mapRow(row);
      grouped.putIfAbsent(event.userId, () => []).add(event);
    }
    return grouped;
  }

  @override
  Future<List<CommitmentEvent>> eventsForPair({
    required String beaconId,
    required String userId,
  }) async {
    final rows = await _selectRows(
      whereSql: 'beacon_id = \$1 AND user_id = \$2',
      variables: [
        Variable<String>(beaconId),
        Variable<String>(userId),
      ],
      orderSql: 'ORDER BY seq ASC',
    );
    return rows.map(_mapRow).toList();
  }

  Future<List<QueryRow>> _selectRows({
    required String whereSql,
    required List<Variable> variables,
    required String orderSql,
  }) => _database
      .customSelect(
        '''
SELECT
  id,
  seq,
  beacon_id,
  user_id,
  actor_user_id,
  kind,
  reason,
  created_at::text AS created_at
FROM public.beacon_commitment_event
WHERE $whereSql
$orderSql
''',
        variables: variables,
        readsFrom: {_database.beaconCommitmentEvents},
      )
      .get();

  CommitmentEvent _mapRow(QueryRow row) => CommitmentEvent(
    id: row.read<String>('id'),
    seq: row.read<int>('seq'),
    beaconId: row.read<String>('beacon_id'),
    userId: row.read<String>('user_id'),
    actorUserId: row.read<String>('actor_user_id'),
    kind: CommitmentEventKind.tryFromInt(row.read<int>('kind'))!,
    reason: row.readNullable<String>('reason'),
    createdAt: DateTime.parse(row.read<String>('created_at')).toUtc(),
  );
}
