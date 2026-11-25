import 'package:tentura_server/domain/port/owner_graph_transaction_port.dart';

import '../database/tentura_db.dart';
import 'owner_graph_unit_of_work.dart';

/// Copies a private entry's tag memberships and records which rows Undo owns.
/// A tag edit that arrived before the merge can transfer just its new row.
Future<bool> transferPhantomTags(
  TenturaDb database,
  OwnerGraphScope scope, {
  required String ownerId,
  required String mergeId,
  String? tagId,
}) async {
  requireOwnerGraphScope(database, scope, ownerId);
  final updated = await database.customUpdate(
    r'''
WITH target AS MATERIALIZED (
  SELECT m.id, m.owner_id, m.phantom_id, m.user_id
    FROM public.phantom_merge m
    JOIN public."user" u ON u.id = m.user_id
   WHERE m.id = $1 AND m.owner_id = $2 AND m.undone_at IS NULL
   FOR KEY SHARE OF u
), original AS MATERIALIZED (
  SELECT member.* FROM public.phantom_tag_member member
  JOIN target t USING (owner_id, phantom_id)
  WHERE $3::text IS NULL OR member.tag_id = $3
), inserted AS (
  INSERT INTO public.person_tag_member (tag_id, owner_id, person_id, source)
  SELECT o.tag_id, t.owner_id, t.user_id, o.source FROM original o
  CROSS JOIN target t
  WHERE NOT public.block_hides(t.owner_id, t.user_id)
  ON CONFLICT (tag_id, person_id) DO NOTHING
  RETURNING membership_id
)
UPDATE public.phantom_merge m
SET undo = m.undo || jsonb_build_object(
  'phantomMemberships',
    COALESCE(m.undo->'phantomMemberships', '[]'::jsonb)
    || COALESCE((SELECT jsonb_agg(to_jsonb(original) ORDER BY tag_id) FROM original), '[]'::jsonb),
  'insertedMembershipIds',
    COALESCE(m.undo->'insertedMembershipIds', '[]'::jsonb)
    || COALESCE((SELECT jsonb_agg(membership_id ORDER BY membership_id) FROM inserted), '[]'::jsonb)
)
FROM target t WHERE m.id = t.id
''',
    variables: [
      Variable.withString(mergeId),
      Variable.withString(ownerId),
      Variable<String>(tagId),
    ],
  );
  return updated != 0;
}
