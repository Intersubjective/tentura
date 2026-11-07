import 'package:injectable/injectable.dart';
import 'package:postgres/postgres.dart' show Type, TypedValue;

import 'package:tentura_server/domain/port/constellation_new_people_repository_port.dart';
import 'package:tentura_server/consts/people_tag_consts.dart'
    show kPersonTagSourceInherited;

import '../database/tentura_db.dart';
import 'people_tags_repository.dart';

/// Copies the viewer's own tag rows on each newcomer's direct inviter to the
/// newcomer. Nothing moves when the viewer is the inviter or a block stands
/// either way between the viewer and the inviter or the newcomer; a tag left
/// with less room than candidates admits them in person id order.
const _inheritSql = r'''
WITH candidate AS (
  SELECT m.tag_id, g.descendant_user_id AS person_id
    FROM public.invite_genealogy g
    JOIN public.person_tag_member m
      ON m.owner_id = $1 AND m.person_id = g.ancestor_user_id
   WHERE g.descendant_user_id = ANY($2::text[])
     AND g.ancestor_user_id <> $1
     AND NOT EXISTS (
       SELECT 1 FROM public.user_block ub
        WHERE (ub.blocker_id = $1
               AND ub.blocked_id IN (g.ancestor_user_id, g.descendant_user_id))
           OR (ub.blocked_id = $1
               AND ub.blocker_id IN (g.ancestor_user_id, g.descendant_user_id)))
     AND NOT EXISTS (
       SELECT 1 FROM public.person_tag_member x
        WHERE x.tag_id = m.tag_id AND x.person_id = g.descendant_user_id)
), ranked AS (
  SELECT c.tag_id, c.person_id,
         row_number() OVER (PARTITION BY c.tag_id ORDER BY c.person_id) +
         (SELECT count(*) FROM public.person_tag_member t
           WHERE t.tag_id = c.tag_id) AS size_after
    FROM candidate c
)
INSERT INTO public.person_tag_member (tag_id, owner_id, person_id, source)
SELECT tag_id, $1, person_id, $4 FROM ranked WHERE size_after <= $3
ON CONFLICT DO NOTHING
''';

@LazySingleton(as: ConstellationNewPeopleRepositoryPort)
final class ConstellationNewPeopleRepository
    implements ConstellationNewPeopleRepositoryPort {
  ConstellationNewPeopleRepository(this._database);

  final TenturaDb _database;

  @override
  Future<void> recordFirstSeen({
    required String viewerId,
    required List<String> peerIds,
    required bool backfill,
  }) async {
    if (peerIds.isEmpty) return;
    await _database.withMutatingSystem(() async {
      final inserted = await _database.customWriteReturning(
        r'''
INSERT INTO public.person_field_first_seen (viewer_id, peer_id, first_seen_at)
SELECT $1, p, CASE WHEN $3::boolean THEN '-infinity'::timestamptz
                     ELSE now() END
FROM unnest($2::text[]) AS p
ON CONFLICT DO NOTHING
RETURNING peer_id
''',
        variables: [
          Variable.withString(viewerId),
          Variable(TypedValue(Type.textArray, peerIds)),
          Variable.withBool(backfill),
        ],
      );
      if (backfill || inserted.isEmpty) return;
      await _inheritInviterTags(viewerId, {
        for (final r in inserted) r.read<String>('peer_id'),
      });
    });
  }

  /// Newcomers inherit level by level, each after their inviter when the
  /// inviter is a newcomer too, so a chain passes freshly inherited tags on.
  Future<void> _inheritInviterTags(
    String viewerId,
    Set<String> newcomers,
  ) async {
    final inviterOf = {
      for (final r
          in await _database
              .customSelect(
                r'''
SELECT descendant_user_id, ancestor_user_id FROM public.invite_genealogy
 WHERE descendant_user_id = ANY($1::text[]) AND ancestor_user_id IS NOT NULL
''',
                variables: [
                  Variable(TypedValue(Type.textArray, newcomers.toList())),
                ],
              )
              .get())
        r.read<String>('descendant_user_id'): r.read<String>(
          'ancestor_user_id',
        ),
    };
    if (inviterOf.isEmpty) return;
    await PeopleTagsRepository.lockOwner(_database, viewerId);
    // invite_genealogy__chronology keeps the chain acyclic, so every round
    // finds a newcomer whose inviter is not still pending.
    var pending = inviterOf.keys.toSet();
    while (pending.isNotEmpty) {
      final level = {
        for (final p in pending)
          if (!pending.contains(inviterOf[p])) p,
      };
      await _database.customStatement(_inheritSql, [
        viewerId,
        TypedValue(Type.textArray, level.toList()),
        PeopleTagsRepository.maxMembers,
        kPersonTagSourceInherited,
      ]);
      pending = pending.difference(level);
    }
  }

  @override
  Future<void> acknowledge({
    required String viewerId,
    required List<String> peerIds,
  }) async {
    if (peerIds.isEmpty) return;
    await _database.withMutatingUser(viewerId, () async {
      await _database.customUpdate(
        r'''
UPDATE public.person_field_first_seen
SET acknowledged_at = now()
WHERE viewer_id = $1 AND peer_id = ANY($2::text[])
  AND acknowledged_at IS NULL
''',
        variables: [
          Variable.withString(viewerId),
          Variable(TypedValue(Type.textArray, peerIds)),
        ],
      );
    });
  }
}
