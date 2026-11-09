import 'package:tentura_server/consts/coordination_item_consts.dart';

/// Everyone Request Questions of [beaconId] may reach, before the policy
/// (`questions_access_levels`) narrows it to access > 0: every standing
/// source, plus whoever has written in Questions. Someone who merely can
/// find a discoverable Request joins only once they write there, so a
/// stranger's question fans out to nobody who never took part (#526).
///
/// One list for `questions_audience` (mentions, reply notices, realtime
/// hints) and Questions unread.
String questionsAudienceCandidateIdsSql(String beaconId) =>
    '''
SELECT qa_b.user_id FROM public.beacon qa_b
WHERE qa_b.id = $beaconId AND qa_b.user_id IS NOT NULL
UNION
SELECT qa_bs.user_id FROM public.beacon_steward qa_bs
WHERE qa_bs.beacon_id = $beaconId
UNION
SELECT qa_bp.user_id FROM public.beacon_participant qa_bp
WHERE qa_bp.beacon_id = $beaconId
  AND (qa_bp.role IN (1, 6) OR qa_bp.room_access = 3)
UNION
SELECT qa_fe.recipient_id FROM public.beacon_forward_edge qa_fe
WHERE qa_fe.beacon_id = $beaconId AND qa_fe.cancelled_at IS NULL
UNION
SELECT qa_ho.user_id FROM public.beacon_help_offer qa_ho
WHERE qa_ho.beacon_id = $beaconId
UNION
SELECT qa_o.user_id FROM public.beacon_bud_observer qa_o
WHERE qa_o.beacon_id = $beaconId
UNION
SELECT qa_m.author_id FROM public.coordination_item qa_ci
JOIN public.beacon_room_message qa_m ON qa_m.thread_item_id = qa_ci.id
WHERE qa_ci.beacon_id = $beaconId AND qa_ci.kind = ${CoordinationItemKind.lobby.smallintValue}
  AND qa_m.author_id IS NOT NULL
''';

/// [viewer] is in the Questions audience list of the Questions scope
/// [lobbyId] (the caller has checked their access level).
String questionsAudienceCandidateSql({
  required String lobbyId,
  required String viewer,
}) =>
    '''
EXISTS (
  SELECT 1 FROM public.coordination_item qa_lobby
  WHERE qa_lobby.id = $lobbyId
    AND $viewer IN (${questionsAudienceCandidateIdsSql('qa_lobby.beacon_id')})
)''';
