import 'package:injectable/injectable.dart';

import 'package:tentura_server/domain/entity/help_offer_admission_event.dart';
import 'package:tentura_server/domain/port/help_offer_admission_repository_port.dart';

import '../database/tentura_db.dart';

Future<void> insertHelpOfferAdmissionEvent(
  TenturaDb db, {
  required String beaconId,
  required String offerUserId,
  required String actorUserId,
  required HelpOfferAdmissionAction action,
  String? reason,
}) => db.customInsert(
  r'''
INSERT INTO public.beacon_help_offer_admission_event
  (id, beacon_id, offer_user_id, actor_user_id, action, reason)
VALUES ($1, $2, $3, $4, $5, $6)
''',
  variables: [
    Variable<String>(HelpOfferAdmissionEvent.newId),
    Variable<String>(beaconId),
    Variable<String>(offerUserId),
    Variable<String>(actorUserId),
    Variable<int>(action.smallintValue),
    Variable<String>(reason),
  ],
  updates: {db.beaconHelpOfferAdmissionEvents},
);

@Injectable(
  as: HelpOfferAdmissionRepositoryPort,
  env: [Environment.dev, Environment.prod],
  order: 1,
)
class HelpOfferAdmissionRepository implements HelpOfferAdmissionRepositoryPort {
  HelpOfferAdmissionRepository(this._database);

  final TenturaDb _database;

  @override
  Future<void> record({
    required String beaconId,
    required String offerUserId,
    required String actorUserId,
    required HelpOfferAdmissionAction action,
    String? reason,
  }) => _database.withMutatingUser(
    actorUserId,
    () => insertHelpOfferAdmissionEvent(
      _database,
      beaconId: beaconId,
      offerUserId: offerUserId,
      actorUserId: actorUserId,
      action: action,
      reason: reason,
    ),
  );

  @override
  Future<HelpOfferAdmissionEvent?> latestFor({
    required String beaconId,
    required String offerUserId,
  }) async {
    final rows = await _latestRows(
      whereSql: 'beacon_id = \$1 AND offer_user_id = \$2',
      variables: [
        Variable<String>(beaconId),
        Variable<String>(offerUserId),
      ],
      limitSql: 'LIMIT 1',
    );
    return rows.isEmpty ? null : _mapRow(rows.single);
  }

  @override
  Future<Map<String, HelpOfferAdmissionEvent>> latestForBeacon(
    String beaconId,
  ) async {
    final rows = await _database
        .customSelect(
          r'''
SELECT DISTINCT ON (beacon_id, offer_user_id)
  id,
  seq,
  beacon_id,
  offer_user_id,
  actor_user_id,
  action,
  reason,
  created_at::text AS created_at
FROM public.beacon_help_offer_admission_event
WHERE beacon_id = $1
ORDER BY beacon_id, offer_user_id, seq DESC
''',
          variables: [Variable<String>(beaconId)],
          readsFrom: {_database.beaconHelpOfferAdmissionEvents},
        )
        .get();
    return {
      for (final row in rows) row.read<String>('offer_user_id'): _mapRow(row),
    };
  }

  Future<List<QueryRow>> _latestRows({
    required String whereSql,
    required List<Variable> variables,
    required String limitSql,
  }) => _database
      .customSelect(
        '''
SELECT
  id,
  seq,
  beacon_id,
  offer_user_id,
  actor_user_id,
  action,
  reason,
  created_at::text AS created_at
FROM public.beacon_help_offer_admission_event
WHERE $whereSql
ORDER BY seq DESC
$limitSql
''',
        variables: variables,
        readsFrom: {_database.beaconHelpOfferAdmissionEvents},
      )
      .get();

  HelpOfferAdmissionEvent _mapRow(QueryRow row) => HelpOfferAdmissionEvent(
    id: row.read<String>('id'),
    seq: row.read<int>('seq'),
    beaconId: row.read<String>('beacon_id'),
    offerUserId: row.read<String>('offer_user_id'),
    actorUserId: row.read<String>('actor_user_id'),
    action: HelpOfferAdmissionAction.tryFromInt(row.read<int>('action'))!,
    reason: row.readNullable<String>('reason'),
    createdAt: DateTime.parse(row.read<String>('created_at')).toUtc(),
  );
}
