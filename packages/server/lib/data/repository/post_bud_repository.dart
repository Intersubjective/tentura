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
