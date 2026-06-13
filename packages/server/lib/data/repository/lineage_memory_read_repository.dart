import 'package:drift/drift.dart';
import 'package:drift_postgres/drift_postgres.dart';
import 'package:injectable/injectable.dart';

import 'package:tentura_server/domain/entity/lineage_memory_fact.dart';
import 'package:tentura_server/domain/evaluation/beacon_evaluation_row_status.dart';
import 'package:tentura_server/domain/port/lineage_memory_read_port.dart';

import '../database/tentura_db.dart';

@Injectable(
  as: LineageMemoryReadPort,
  env: [Environment.dev, Environment.prod],
  order: 1,
)
class LineageMemoryReadRepository implements LineageMemoryReadPort {
  const LineageMemoryReadRepository(this._database);

  final TenturaDb _database;

  @override
  Future<List<String>> fetchLineageBeaconIds({
    required String rootBeaconId,
  }) async {
    final rows = await _database.customSelect(
      r'''
      SELECT id FROM beacon
       WHERE id = $1 OR lineage_root_beacon_id = $1
      ''',
      variables: [Variable.withString(rootBeaconId)],
    ).get();
    return rows.map((r) => r.read<String>('id')).toList();
  }

  @override
  Future<Set<String>> fetchAuthorBeaconIdsInSet({
    required String userId,
    required Set<String> beaconIds,
  }) async {
    if (beaconIds.isEmpty) return {};
    final rows = await _database.customSelect(
      r'''
      SELECT id FROM beacon
       WHERE user_id = $1
         AND id = ANY($2::text[])
      ''',
      variables: [
        Variable.withString(userId),
        Variable(TypedValue(Type.textArray, beaconIds.toList())),
      ],
    ).get();
    return rows.map((r) => r.read<String>('id')).toSet();
  }

  @override
  Future<List<LineageForwardEdgeFact>> fetchMyLineageForwardEdges({
    required String userId,
    required Set<String> beaconIds,
  }) async {
    if (beaconIds.isEmpty) return const [];
    final rows = await _database.customSelect(
      r'''
      SELECT recipient_id, note, created_at, beacon_id, recipient_rejected
        FROM beacon_forward_edge
       WHERE sender_id = $1
         AND beacon_id = ANY($2::text[])
         AND cancelled_at IS NULL
      ''',
      variables: [
        Variable.withString(userId),
        Variable(TypedValue(Type.textArray, beaconIds.toList())),
      ],
    ).get();
    return [
      for (final row in rows)
        LineageForwardEdgeFact(
          recipientId: row.read<String>('recipient_id'),
          note: row.read<String>('note'),
          createdAt: row.read<DateTime>('created_at'),
          beaconId: row.read<String>('beacon_id'),
          rejected: row.read<bool>('recipient_rejected'),
        ),
    ];
  }

  @override
  Future<Set<String>> fetchRecipientsWhoHelped({
    required Set<String> myTouchedBeaconIds,
    required Set<String> recipientIds,
  }) async {
    if (myTouchedBeaconIds.isEmpty || recipientIds.isEmpty) return {};
    final rows = await _database.customSelect(
      r'''
      SELECT DISTINCT user_id
        FROM beacon_help_offer
       WHERE beacon_id = ANY($1::text[])
         AND user_id = ANY($2::text[])
         AND status = 0
      ''',
      variables: [
        Variable(TypedValue(Type.textArray, myTouchedBeaconIds.toList())),
        Variable(TypedValue(Type.textArray, recipientIds.toList())),
      ],
    ).get();
    return rows.map((r) => r.read<String>('user_id')).toSet();
  }

  @override
  Future<Set<String>> fetchRecipientsWhoRoutedToHelp({
    required String userId,
    required Set<String> myTouchedBeaconIds,
    required Set<String> recipientIds,
  }) async {
    if (myTouchedBeaconIds.isEmpty || recipientIds.isEmpty) return {};
    final rows = await _database.customSelect(
      r'''
      WITH RECURSIVE downstream AS (
        SELECT e.id,
               e.recipient_id AS direct_recipient_id,
               e.recipient_id AS current_recipient_id,
               e.beacon_id,
               1 AS depth
          FROM beacon_forward_edge e
         WHERE e.sender_id = $1
           AND e.beacon_id = ANY($2::text[])
           AND e.cancelled_at IS NULL
        UNION ALL
        SELECT child.id,
               d.direct_recipient_id,
               child.recipient_id,
               child.beacon_id,
               d.depth + 1
          FROM beacon_forward_edge child
          JOIN downstream d ON child.parent_edge_id = d.id
         WHERE child.cancelled_at IS NULL
           AND d.depth < 20
      )
      SELECT DISTINCT d.direct_recipient_id
        FROM downstream d
        JOIN beacon_help_offer h
          ON h.beacon_id = d.beacon_id
         AND h.user_id = d.current_recipient_id
         AND h.status = 0
       WHERE d.direct_recipient_id = ANY($3::text[])
      ''',
      variables: [
        Variable.withString(userId),
        Variable(TypedValue(Type.textArray, myTouchedBeaconIds.toList())),
        Variable(TypedValue(Type.textArray, recipientIds.toList())),
      ],
    ).get();
    return rows.map((r) => r.read<String>('direct_recipient_id')).toSet();
  }

  @override
  Future<List<LineageEvaluationFact>> fetchMyEvaluationsOnLineage({
    required String userId,
    required Set<String> beaconIds,
  }) async {
    if (beaconIds.isEmpty) return const [];
    final rows = await _database.customSelect(
      r'''
      SELECT evaluated_user_id, value, reason_tags
        FROM beacon_evaluation
       WHERE evaluator_id = $1
         AND beacon_id = ANY($2::text[])
         AND status IN ($3, $4)
      ''',
      variables: [
        Variable.withString(userId),
        Variable(TypedValue(Type.textArray, beaconIds.toList())),
        Variable.withInt(BeaconEvaluationRowStatus.submitted),
        Variable.withInt(BeaconEvaluationRowStatus.final_),
      ],
    ).get();
    return [
      for (final row in rows)
        LineageEvaluationFact(
          evaluatedUserId: row.read<String>('evaluated_user_id'),
          value: row.read<int>('value'),
          reasonTags: row.read<String>('reason_tags'),
        ),
    ];
  }

  @override
  Future<List<LineagePrivateTagFact>> fetchMyPrivateTags({
    required String userId,
  }) async {
    final rows = await _database.customSelect(
      r'''
      SELECT subject_user_id, tag_slug
        FROM person_capability_event
       WHERE observer_user_id = $1
         AND source_type = 0
         AND is_negative = false
         AND deleted_at IS NULL
      ''',
      variables: [Variable.withString(userId)],
    ).get();
    return [
      for (final row in rows)
        LineagePrivateTagFact(
          subjectUserId: row.read<String>('subject_user_id'),
          slug: row.read<String>('tag_slug'),
        ),
    ];
  }
}
