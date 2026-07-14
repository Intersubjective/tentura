import 'package:injectable/injectable.dart';

import 'package:tentura_server/domain/entity/realtime_watch_grant.dart';
import 'package:tentura_server/domain/port/realtime_watch_authorization_port.dart';

import '../database/tentura_db.dart';

@LazySingleton(as: RealtimeWatchAuthorizationPort)
final class RealtimeWatchAuthorizationRepository
    implements RealtimeWatchAuthorizationPort {
  const RealtimeWatchAuthorizationRepository(this._database);

  final TenturaDb _database;

  @override
  Future<Set<String>> authorizeSubjects({
    required String viewerId,
    required RealtimeWatchDescriptor descriptor,
  }) => switch (descriptor.scope) {
    RealtimeWatchScope.graph => _authorizeGraph(viewerId, descriptor),
    RealtimeWatchScope.profile => _authorizeProfiles(descriptor),
    RealtimeWatchScope.people => _authorizePeople(viewerId, descriptor),
  };

  Future<Set<String>> _authorizeGraph(
    String viewerId,
    RealtimeWatchDescriptor descriptor,
  ) async {
    if (descriptor.requestedSubjectIds.isEmpty) return {};
    final requested = descriptor.requestedSubjectIds.toList()..sort();
    final placeholders = _placeholders(requested.length, start: 5);
    final rows = await _database
        .customSelect(
          '''
WITH graph_rows AS MATERIALIZED (
  SELECT *
  FROM public.graph(
    \$1, \$2, \$3, json_build_object('x-hasura-user-id', \$4)::json
  )
), candidates AS (
  SELECT src AS subject_id FROM graph_rows
  UNION
  SELECT dst AS subject_id FROM graph_rows
)
SELECT DISTINCT subject_id
FROM candidates
WHERE subject_id LIKE 'U%'
  AND subject_id IN ($placeholders)
''',
          variables: [
            Variable(descriptor.focusId),
            Variable(descriptor.context),
            Variable(descriptor.positiveOnly),
            Variable(viewerId),
            ...requested.map(Variable.new),
          ],
        )
        .get();
    return rows.map((row) => row.read<String>('subject_id')).toSet();
  }

  Future<Set<String>> _authorizeProfiles(
    RealtimeWatchDescriptor descriptor,
  ) async {
    if (descriptor.requestedSubjectIds.isEmpty) return {};
    // User rows are globally selectable by the authenticated Hasura `user`
    // role. The authorization adapter mirrors that live permission and still
    // intersects against existing rows rather than trusting client IDs.
    final requested = descriptor.requestedSubjectIds.toList()..sort();
    final rows = await _database.customSelect(
      '''
SELECT id AS subject_id
FROM public."user"
WHERE id IN (${_placeholders(requested.length)})
''',
      variables: requested.map(Variable.new).toList(),
    ).get();
    return rows.map((row) => row.read<String>('subject_id')).toSet();
  }

  Future<Set<String>> _authorizePeople(
    String viewerId,
    RealtimeWatchDescriptor descriptor,
  ) async {
    if (descriptor.requestedSubjectIds.isEmpty) return {};
    final canRead = await _database
        .customSelect(
          '''
SELECT public.beacon_can_read_involvement(\$1, \$2) AS allowed
''',
          variables: [Variable(descriptor.beaconId), Variable(viewerId)],
        )
        .getSingle();
    if (!canRead.read<bool>('allowed')) return {};

    final requested = descriptor.requestedSubjectIds.toList()..sort();
    final rows = await _database
        .customSelect(
          '''
WITH involved AS (
  SELECT b.user_id AS subject_id
  FROM public.beacon b
  WHERE b.id = \$1
  UNION
  SELECT bp.user_id
  FROM public.beacon_participant bp
  WHERE bp.beacon_id = \$1
  UNION
  SELECT ho.user_id
  FROM public.beacon_help_offer ho
  WHERE ho.beacon_id = \$1
  UNION
  SELECT fe.sender_id
  FROM public.beacon_forward_edge fe
  WHERE fe.beacon_id = \$1 AND fe.cancelled_at IS NULL
  UNION
  SELECT fe.recipient_id
  FROM public.beacon_forward_edge fe
  WHERE fe.beacon_id = \$1 AND fe.cancelled_at IS NULL
  UNION
  SELECT ii.user_id
  FROM public.inbox_item ii
  WHERE ii.beacon_id = \$1
)
SELECT subject_id
FROM involved
WHERE subject_id IN (${_placeholders(requested.length, start: 2)})
''',
          variables: [
            Variable(descriptor.beaconId),
            ...requested.map(Variable.new),
          ],
        )
        .get();
    return rows.map((row) => row.read<String>('subject_id')).toSet();
  }

  static String _placeholders(int count, {int start = 1}) =>
      List.generate(count, (index) => '\$${start + index}').join(', ');
}
