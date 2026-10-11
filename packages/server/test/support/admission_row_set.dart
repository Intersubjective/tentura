import 'package:postgres/postgres.dart';

import 'package:tentura_server/consts/beacon_activity_event_consts.dart';

/// Arch §5.3 / plan A2, reused by C4 (I7): the rows one admission of
/// [helperId] into [beaconId] leaves behind, reduced to their kind, user,
/// actor and role columns. Ids, sequence numbers and timestamps are left out,
/// so two admissions reached through different entry points (offer + accept,
/// invite accept) compare equal when they write the same facts.
///
/// Attention receipts are deliberately not part of the set: offer + accept
/// creates and settles `helpOfferSubmitted` and sends `offerAccepted`, while
/// invite accept sends different attention.
///
/// Each line is `table|col=value|…`. Event tables keep their `seq` order; the
/// other tables are sorted.
Future<List<String>> collectAdmissionRowSet(
  Connection writer, {
  required String beaconId,
  required String helperId,
}) async {
  final params = {'b': beaconId, 'h': helperId};

  Future<List<String>> lines(
    String table,
    String sql,
    List<String> columns, {
    bool sort = true,
  }) async {
    final result = await writer.execute(Sql.named(sql), parameters: params);
    final out = [
      for (final row in result)
        [
          table,
          for (var i = 0; i < columns.length; i++) '${columns[i]}=${row[i]}',
        ].join('|'),
    ];
    if (sort) out.sort();
    return out;
  }

  return [
    ...await lines(
      'beacon_help_offer',
      '''
SELECT user_id, status, offer_kind, stake_state
FROM public.beacon_help_offer
WHERE beacon_id = @b AND user_id = @h
''',
      ['user', 'status', 'offer_kind', 'stake_state'],
    ),
    ...await lines(
      'beacon_commitment_event',
      '''
SELECT user_id, actor_user_id, kind
FROM public.beacon_commitment_event
WHERE beacon_id = @b AND user_id = @h
ORDER BY seq
''',
      ['user', 'actor', 'kind'],
      sort: false,
    ),
    ...await lines(
      'beacon_help_offer_coordination',
      '''
SELECT offer_user_id, author_user_id, response_type
FROM public.beacon_help_offer_coordination
WHERE offer_beacon_id = @b AND offer_user_id = @h
''',
      ['user', 'author', 'response_type'],
    ),
    ...await lines(
      'beacon_help_offer_admission_event',
      '''
SELECT offer_user_id, actor_user_id, action
FROM public.beacon_help_offer_admission_event
WHERE beacon_id = @b AND offer_user_id = @h
ORDER BY seq
''',
      ['user', 'actor', 'action'],
      sort: false,
    ),
    ...await lines(
      'beacon_participant',
      '''
SELECT user_id, role, status, room_access
FROM public.beacon_participant
WHERE beacon_id = @b AND user_id = @h
''',
      ['user', 'role', 'status', 'room_access'],
    ),
    ...await lines(
      'beacon_activity_event',
      '''
SELECT target_user_id, actor_id, visibility, diff->>'admissionReason'
FROM public.beacon_activity_event
WHERE beacon_id = @b AND target_user_id = @h
  AND type = ${BeaconActivityEventTypeBits.participantJoined}
''',
      ['user', 'actor', 'visibility', 'reason'],
    ),
    ...await lines(
      'trust_evidence',
      '''
SELECT subject_user_id, object_user_id, related_user_id, kind, count,
       retracted_at IS NOT NULL
FROM public.trust_evidence
WHERE (beacon_id = @b OR source_key LIKE 'approval:' || @b || ':%')
  AND (subject_user_id = @h OR object_user_id = @h)
''',
      ['subject', 'object', 'related', 'kind', 'count', 'retracted'],
    ),
  ];
}
