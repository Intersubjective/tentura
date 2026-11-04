import 'package:postgres/postgres.dart' show Type, TypedValue;

import 'package:tentura_server/consts/constellation_consts.dart';
import 'package:tentura_server/domain/entity/constellation_anchor_projection.dart';
import 'package:tentura_server/domain/entity/field_search_result.dart';
import 'package:tentura_server/domain/entity/field_hidden_item.dart';
import 'package:tentura_server/domain/entity/person_field_items_page.dart';

import '../database/tentura_db.dart';
import 'constellation_field_repository.dart';

/// Uses the Field's existing population and read policies, without its display
/// caps, hide exclusion or active-only filters. Readability is one set operation
/// before ranking, never one database round trip per candidate or result.
final class FieldSearchReader {
  const FieldSearchReader(this._database);

  final TenturaDb _database;

  Future<PersonFieldItemsPage> readPersonItems({
    required String viewerId,
    required String personId,
    required PersonFieldBucket bucket,
    required List<String> words,
    PersonFieldCursor? cursor,
  }) => _database.withConnectionScope(
    () async {
      await _database
          .customSelect(
            r'SELECT public.person_visible_peer_ids_tx($1, $2)',
            variables: [Variable.withString(viewerId), Variable.withString('')],
          )
          .get();
      return _database.withReadSnapshot(() async {
        await _database.freezeVisibilityMemo();
        final rows = await _database
            .customSelect(
              '''
WITH candidates AS MATERIALIZED (
  SELECT b.id, b.user_id AS author_id, b.kind::int, b.title, b.status::int,
    $constellationLastActivitySql AS activity_at, b.expires_at,
    left(COALESCE(root.body, ''), $kConstellationPostExcerptLength) AS root_excerpt
  FROM public.beacon b
  LEFT JOIN public.beacon_room_message root
    ON root.id = b.post_root_message_id AND root.beacon_id = b.id
  WHERE b.user_id = \$2 AND b.published_at IS NOT NULL
    AND NOT public.block_hides(\$1, b.user_id)
    AND ((b.kind = 0 AND b.status IN (0, 5, 6, 7, 8))
      OR (b.kind = 1 AND b.status IN (0, 6)))
    AND ${_matches("CASE WHEN b.kind = 0 THEN b.title ELSE left(COALESCE(root.body, ''), $kConstellationPostExcerptLength) END")}
), readable AS MATERIALIZED (
  SELECT public.beacon_readable_ids(\$1, ARRAY(SELECT id FROM candidates)) AS id
), bucketed AS MATERIALIZED (
  SELECT c.*, NOT public.field_item_visible(\$1, c.kind, c.id) AS hidden,
    CASE WHEN NOT public.field_item_visible(\$1, c.kind, c.id) THEN 'hidden'
      WHEN (c.kind = 0 AND c.status IN (5, 6))
        OR (c.kind = 1 AND (c.status = 6 OR c.expires_at <= now())) THEN 'closed'
      ELSE 'active' END AS bucket
  FROM candidates c WHERE c.id IN (SELECT id FROM readable)
), totals AS (
  SELECT count(*) FILTER (WHERE bucket = 'active')::int AS active_count,
    count(*) FILTER (WHERE bucket = 'closed')::int AS closed_count,
    count(*) FILTER (WHERE bucket = 'hidden')::int AS hidden_count
  FROM bucketed
), page AS (
  SELECT * FROM bucketed
  WHERE bucket = \$4 AND (\$5::timestamptz IS NULL
    OR (activity_at, id) < (\$5::timestamptz, \$6::text))
  ORDER BY activity_at DESC, id DESC LIMIT 21
)
SELECT totals.*, page.id, page.author_id, page.kind, page.title, page.status,
  page.root_excerpt, page.hidden, page.activity_at::text AS activity_at,
  page.expires_at::text AS expires_at
FROM totals LEFT JOIN page ON true
ORDER BY page.activity_at DESC, page.id DESC
''',
              variables: [
                Variable.withString(viewerId),
                Variable.withString(personId),
                Variable(TypedValue(Type.textArray, words)),
                Variable.withString(bucket.name),
                Variable<String>(cursor?.activityAt.toUtc().toIso8601String()),
                Variable<String>(cursor?.id),
              ],
            )
            .get();
        final items = <PersonFieldItem>[
          for (final row in rows)
            if (row.readNullable<String>('id') case final String id)
              (
                id: id,
                kind: FieldTargetKind.parse(row.read<int>('kind')),
                authorId: row.read<String>('author_id'),
                title: row.read<String>('title'),
                rootExcerpt: row.read<String>('root_excerpt'),
                status: row.read<int>('status'),
                hidden: row.read<bool>('hidden'),
                lastActivityAt: DateTime.parse(
                  row.read<String>('activity_at'),
                ).toUtc(),
                expiresAt: switch (row.readNullable<String>('expires_at')) {
                  final String at => DateTime.parse(at).toUtc(),
                  null => null,
                },
              ),
        ];
        final page = items.take(20).toList();
        return (
          items: page,
          nextCursor: items.length > page.length
              ? (activityAt: page.last.lastActivityAt, id: page.last.id)
              : null,
          counts: (
            active: rows.first.read<int>('active_count'),
            closed: rows.first.read<int>('closed_count'),
            hidden: rows.first.read<int>('hidden_count'),
          ),
        );
      });
    },
    actorUserId: viewerId,
  );

  Future<FieldSearchResult> read({
    required String viewerId,
    required String context,
    required List<String> words,
  }) => _database.withConnectionScope(
    () async {
      // As in the Field snapshot reader, fill visibility before READ ONLY, then
      // keep people, items and their readability decisions in one MVCC snapshot.
      await _database
          .customSelect(
            r'SELECT public.person_visible_peer_ids_tx($1, $2)',
            variables: [
              Variable.withString(viewerId),
              Variable.withString(context),
            ],
          )
          .get();
      return _database.withReadSnapshot(() async {
        await _database.freezeVisibilityMemo();
        final variables = [
          Variable.withString(viewerId),
          Variable.withString(context),
          Variable(TypedValue(Type.textArray, words)),
        ];
        final people = await _database.customSelect(
          '''
WITH visible AS MATERIALIZED (
  SELECT unnest(public.person_visible_peer_ids_tx(\$1, \$2)) AS id
), bond AS MATERIALIZED (
  SELECT peer_id AS id FROM public.person_bond_peers(\$1)
), temporary AS MATERIALIZED (
  SELECT peer_id AS id FROM public.person_temporary_forward_peers(\$1)
), population AS (
  SELECT id FROM visible UNION SELECT id FROM bond UNION SELECT id FROM temporary
  UNION SELECT object FROM public.vote_user WHERE subject = \$1 AND amount > 0
  UNION SELECT \$1
), profiles AS (
  SELECT u.id, u.display_name,
    CASE WHEN u.id = \$1 OR u.id IN (SELECT id FROM visible UNION SELECT id FROM bond UNION SELECT id FROM temporary)
      THEN u.handle END AS handle
  FROM public."user" u
  WHERE u.id IN (SELECT id FROM population)
    AND NOT public.block_hides(\$1, u.id)
)
SELECT id, display_name, handle FROM profiles
WHERE ${_matches("COALESCE(display_name, '') || ' ' || COALESCE(handle, '')")}
ORDER BY lower(display_name), id
LIMIT 20
''',
          variables: variables,
        ).get();
        final statuses = constellationFieldBeaconStatuses(
          showClosed: true,
        ).toList()..sort();
        final items = await _database
            .customSelect(
              '''
WITH visible AS MATERIALIZED (
  SELECT unnest(public.person_visible_peer_ids_tx(\$1, \$2)) AS id
), candidates AS MATERIALIZED (
  SELECT b.id, b.user_id AS author_id, b.kind::int, b.title, b.status::int,
    $constellationLastActivitySql AS activity_at,
    b.expires_at,
    left(COALESCE(root.body, ''), $kConstellationPostExcerptLength) AS root_excerpt
  FROM public.beacon b
  LEFT JOIN public.beacon_room_message root
    ON root.id = b.post_root_message_id AND root.beacon_id = b.id
  WHERE b.published_at IS NOT NULL AND NOT public.block_hides(\$1, b.user_id)
    AND (
      (b.kind = 0 AND b.status = ANY(\$4::int[]) AND (
        b.user_id = \$1
        OR (b.is_discoverable AND b.user_id IN (SELECT id FROM visible))
        OR EXISTS (SELECT 1 FROM public.beacon_forward_edge f
                   WHERE f.beacon_id = b.id AND f.recipient_id = \$1 AND f.cancelled_at IS NULL)
        OR EXISTS (SELECT 1 FROM public.constellation_anchor a
                   WHERE a.viewer_id = \$1 AND a.beacon_id = b.id AND a.tombstone_at IS NULL)
      ))
      OR (b.kind = 1 AND b.status IN (0, 6) AND (
        b.user_id = \$1
        OR EXISTS (SELECT 1 FROM public.beacon_participant p
                   WHERE p.beacon_id = b.id AND p.user_id = \$1 AND p.role = 6 AND p.room_access = 3)
      ))
    )
    AND ${_matches("CASE WHEN b.kind = 0 THEN b.title ELSE left(COALESCE(root.body, ''), $kConstellationPostExcerptLength) END")}
), readable AS MATERIALIZED (
  SELECT public.beacon_readable_ids(\$1, ARRAY(SELECT id FROM candidates)) AS id
), ranked AS (
  SELECT c.*, row_number() OVER (PARTITION BY kind ORDER BY activity_at DESC, c.id) AS rank
  FROM candidates c WHERE c.id IN (SELECT id FROM readable)
)
SELECT id, author_id, kind, title, status, root_excerpt,
       activity_at::text AS activity_at, expires_at::text AS expires_at,
       NOT public.field_item_visible(\$1, kind, id) AS hidden
FROM ranked WHERE rank <= 20
ORDER BY kind, rank
''',
              variables: [
                ...variables,
                Variable(TypedValue(Type.integerArray, statuses)),
              ],
            )
            .get();
        return (
          people: [
            for (final row in people)
              (
                id: row.read<String>('id'),
                displayName: row.readNullable<String>('display_name'),
                handle: row.readNullable<String>('handle'),
              ),
          ],
          requests: [
            for (final row in items)
              if (row.read<int>('kind') == 0)
                (
                  id: row.read<String>('id'),
                  authorId: row.read<String>('author_id'),
                  title: row.read<String>('title'),
                  status: row.read<int>('status'),
                  hidden: row.read<bool>('hidden'),
                  lastActivityAt: DateTime.parse(
                    row.read<String>('activity_at'),
                  ).toUtc(),
                ),
          ],
          posts: [
            for (final row in items)
              if (row.read<int>('kind') == 1)
                (
                  id: row.read<String>('id'),
                  authorId: row.read<String>('author_id'),
                  rootExcerpt: row.read<String>('root_excerpt'),
                  status: row.read<int>('status'),
                  hidden: row.read<bool>('hidden'),
                  lastActivityAt: DateTime.parse(
                    row.read<String>('activity_at'),
                  ).toUtc(),
                  expiresAt: switch (row.readNullable<String>('expires_at')) {
                    final String at => DateTime.parse(at).toUtc(),
                    null => null,
                  },
                ),
          ],
        );
      });
    },
    actorUserId: viewerId,
  );
}

/// strpos treats percent/underscore as literal text, unlike LIKE. The same
/// fold is used for every group and every word must match, as on the client.
String _matches(String text) =>
    '''
NOT EXISTS (
  SELECT 1 FROM unnest(\$3::text[]) word
  WHERE strpos(replace(replace(lower(COALESCE($text, '')), 'ё', 'е'), '@', ''), word) = 0
)''';
