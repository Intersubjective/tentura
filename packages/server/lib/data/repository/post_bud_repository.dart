import 'package:injectable/injectable.dart';

import 'package:tentura_server/domain/entity/post_bud_invite_candidate.dart';
import 'package:tentura_server/domain/port/person_visibility_repository_port.dart';
import 'package:tentura_server/domain/port/post_bud_port.dart';

import '../database/tentura_db.dart';

/// `post_effective_members`, `post_bud_invite_facts` and `post_bud_pretick`
/// (m0240). Visibility stays in Dart: the SQL makes no `mr_*` calls.
@Injectable(as: PostBudPort)
class PostBudRepository implements PostBudPort {
  const PostBudRepository(this._database, this._personVisibility);

  final TenturaDb _database;

  final PersonVisibilityRepositoryPort _personVisibility;

  @override
  Future<List<String>> effectiveMemberIds(String postId) async {
    final rows = await _database
        .customSelect(
          r'SELECT user_id FROM public.post_effective_members($1) '
          'ORDER BY user_id',
          variables: [Variable.withString(postId)],
        )
        .get();
    return [for (final r in rows) r.read<String>('user_id')];
  }

  @override
  Future<List<PostBudInviteCandidate>> inviteCandidates({
    required String postId,
    required String budderId,
  }) async {
    final rows = await _database
        .customSelect(
          r'''
SELECT f.user_id, f.warm, f.reason, f.has_written, f.via_user_id,
       p.user_id IS NOT NULL AS pretick
FROM public.post_bud_invite_facts($1, $2) f
LEFT JOIN public.post_bud_pretick($1, $2) p ON p.user_id = f.user_id
ORDER BY f.user_id
''',
          variables: [
            Variable.withString(postId),
            Variable.withString(budderId),
          ],
        )
        .get();
    final coldIds = [
      for (final r in rows)
        if (!r.read<bool>('warm') && r.read<int>('reason') == 0)
          r.read<String>('user_id'),
    ];
    final visible = coldIds.isEmpty
        ? const <String>{}
        : await _personVisibility.personVisiblePeerIds(
            viewerId: budderId,
            peerIds: coldIds,
            context: '',
          );
    return [
      for (final r in rows)
        _candidate(
          userId: r.read<String>('user_id'),
          warm: r.read<bool>('warm'),
          reason: PostBudInviteReason.fromCode(r.read<int>('reason')),
          hasWritten: r.read<bool>('has_written'),
          pretick: r.read<bool>('pretick'),
          viaUserId: r.readNullable<String>('via_user_id'),
          visible: visible,
        ),
    ];
  }

  @override
  Future<int> writeObservers({
    required String childId,
    required String postId,
    required String budderId,
  }) => _database.customUpdate(
    r'''
INSERT INTO public.beacon_bud_observer (beacon_id, user_id)
SELECT $1, m.user_id
FROM public.post_effective_members($2) m
WHERE m.user_id <> $3
  AND NOT public.block_hides($3, m.user_id)
ON CONFLICT DO NOTHING
''',
    variables: [
      Variable.withString(childId),
      Variable.withString(postId),
      Variable.withString(budderId),
    ],
  );

  @override
  Future<String?> insertInvite({
    required String beaconId,
    required String inviterId,
    required String inviteeId,
    required String sourcePostId,
    required String? forwardEdgeId,
    required bool warm,
    String? note,
  }) async {
    final rows = await _database
        .customSelect(
          r'''
INSERT INTO public.beacon_author_invite
  (beacon_id, inviter_id, invitee_id, source_post_id, forward_edge_id,
   arrival_post_edge_id, warm, note)
SELECT $1, $2, $3, $4, $5,
  (SELECT e.id
   FROM public.beacon_forward_edge e
   JOIN public.beacon p ON p.id = e.beacon_id
   WHERE e.beacon_id = $4
     AND e.recipient_id = $3
     AND e.cancelled_at IS NULL
     AND p.user_id <> $3
   ORDER BY e.created_at DESC, e.id DESC
   LIMIT 1),
  $6, $7
ON CONFLICT DO NOTHING
RETURNING id
''',
          variables: [
            Variable.withString(beaconId),
            Variable.withString(inviterId),
            Variable.withString(inviteeId),
            Variable.withString(sourcePostId),
            Variable<String>(forwardEdgeId),
            Variable.withBool(warm),
            Variable<String>(note),
          ],
        )
        .getSingleOrNull();
    return rows?.read<String>('id');
  }

  @override
  Future<PostBudInviteCandidate?> laterInviteCandidate({
    required String childId,
    required String postId,
    required String inviterId,
    required String inviteeId,
  }) async {
    final row = await _database
        .customSelect(
          r'''
SELECT
  (p.user_id = $4
     OR EXISTS (
       SELECT 1 FROM public.post_first_response fr
       WHERE fr.beacon_id = p.id AND fr.user_id = $4)) AS warm,
  (CASE
     WHEN public.block_hides($3, $4) OR public.block_hides(p.user_id, $4)
       THEN 2
     WHEN EXISTS (
       SELECT 1 FROM public.user_availability ua
       WHERE ua.user_id = $4
         AND ua.resume_on > public.utc_today()) THEN 4
     WHEN EXISTS (
       SELECT 1 FROM public.beacon_author_invite i
       WHERE i.status = 0
         AND i.invitee_id = $4
         AND (i.beacon_id = $1
              OR (i.inviter_id = $3 AND i.source_post_id = p.id))) THEN 5
     ELSE 0
   END)::smallint AS reason
FROM public.beacon_bud_observer o
JOIN public.beacon p ON p.id = $2
WHERE o.beacon_id = $1 AND o.user_id = $4 AND o.user_id <> $3
''',
          variables: [
            Variable.withString(childId),
            Variable.withString(postId),
            Variable.withString(inviterId),
            Variable.withString(inviteeId),
          ],
        )
        .getSingleOrNull();
    if (row == null) return null;
    final warm = row.read<bool>('warm');
    final reason = PostBudInviteReason.fromCode(row.read<int>('reason'));
    final visible = warm || reason != PostBudInviteReason.eligible
        ? const <String>{}
        : await _personVisibility.personVisiblePeerIds(
            viewerId: inviterId,
            peerIds: [inviteeId],
            context: '',
          );
    return _candidate(
      userId: inviteeId,
      warm: warm,
      reason: reason,
      hasWritten: false,
      pretick: false,
      viaUserId: null,
      visible: visible,
    );
  }

  @override
  Future<List<String>> observerIdsForAuthor({
    required String childId,
    required String authorId,
  }) async {
    final rows = await _database
        .customSelect(
          r'''
SELECT o.user_id
FROM public.beacon_bud_observer o
JOIN public.beacon b ON b.id = o.beacon_id
WHERE o.beacon_id = $1
  AND b.user_id = $2
  AND o.user_id <> $2
  AND NOT public.block_hides($2, o.user_id)
ORDER BY o.user_id
''',
          variables: [
            Variable.withString(childId),
            Variable.withString(authorId),
          ],
        )
        .get();
    return [for (final r in rows) r.read<String>('user_id')];
  }

  static PostBudInviteCandidate _candidate({
    required String userId,
    required bool warm,
    required PostBudInviteReason reason,
    required bool hasWritten,
    required bool pretick,
    required String? viaUserId,
    required Set<String> visible,
  }) => PostBudInviteCandidate(
    userId: userId,
    warm: warm,
    reason:
        reason == PostBudInviteReason.eligible &&
            !warm &&
            !visible.contains(userId)
        ? PostBudInviteReason.notVisible
        : reason,
    hasWritten: hasWritten,
    pretick: pretick,
    viaUserId: viaUserId,
  );
}
