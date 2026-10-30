import 'dart:convert';

import 'package:injectable/injectable.dart';
import 'package:postgres/postgres.dart' show Type, TypedValue;
import 'package:tentura_root/domain/entity/person_auto_tag_kind.dart';

import 'package:tentura_server/domain/entity/person_tag.dart';
import 'package:tentura_server/domain/exception.dart';
import 'package:tentura_server/domain/exception_codes.dart';
import 'package:tentura_server/domain/port/people_tags_repository_port.dart';
import 'package:tentura_server/utils/id.dart';

import '../database/tentura_db.dart';

const _maxTags = 50;
const _colors = 8;
const _maxMembers = 1000;

/// The two-way block test of `block_hides`, as an anti-join on a member row.
const _notBlockedSql = r'''
NOT EXISTS (
  SELECT 1 FROM public.user_block ub
   WHERE (ub.blocker_id = $1 AND ub.blocked_id = m.person_id)
      OR (ub.blocker_id = m.person_id AND ub.blocked_id = $1))
''';

const _skippedSql = r'''
UPDATE public.person_tag_suggestion_state
   SET consecutive_skips = CASE WHEN consecutive_skips + 1 >= 3
                                THEN 0 ELSE consecutive_skips + 1 END,
       silenced_until = CASE WHEN consecutive_skips + 1 >= 3
                             THEN now() + interval '30 days'
                             ELSE silenced_until END,
       updated_at = now()
 WHERE owner_id = $1
''';

const _acceptedSql = r'''
UPDATE public.person_tag_suggestion_state
   SET consecutive_skips = 0, updated_at = now() WHERE owner_id = $1
''';

const _disabledSql = r'''
UPDATE public.person_tag_suggestion_state
   SET disabled = true, updated_at = now() WHERE owner_id = $1
''';

const _enabledSql = r'''
UPDATE public.person_tag_suggestion_state
   SET disabled = false, silenced_until = NULL, updated_at = now()
 WHERE owner_id = $1
''';

/// `person_tag`, `person_tag_member`, `person_tag_revision` and
/// `person_tag_op_log` (m0261). Each mutation is one transaction under a
/// per-owner advisory lock, so replays and order changes never interleave.
@Injectable(
  as: PeopleTagsRepositoryPort,
  env: [Environment.dev, Environment.prod],
  order: 1,
)
class PeopleTagsRepository implements PeopleTagsRepositoryPort {
  const PeopleTagsRepository(this._database);

  final TenturaDb _database;

  @override
  Future<List<PersonTag>> list(String ownerId) =>
      _list(ownerId, withCounts: true);

  @override
  Future<PersonTag> create({
    required String ownerId,
    required String clientOpId,
    required String fingerprint,
    required String name,
    required String glyph,
    int? color,
    int? fromAutoKind,
    String? fromBeaconId,
  }) => _idempotent(
    ownerId,
    clientOpId,
    fingerprint,
    decode: PersonTag.fromJson,
    run: () async {
      final tags = await _list(ownerId);
      _checkRoom(tags);
      await _checkNameFree(ownerId, name);
      final copied = await _sourcePeople(
        ownerId,
        fromAutoKind: fromAutoKind,
        fromBeaconId: fromBeaconId,
      );
      final tag = PersonTag(
        id: generateId('PT'),
        name: name,
        glyph: glyph,
        color: color ?? tags.length % _colors,
        ord: tags.length + 1,
      );
      await _insert(ownerId, tag);
      if (copied != null) {
        await _database.customStatement(
          r'''
INSERT INTO public.person_tag_member (tag_id, owner_id, person_id, source)
SELECT $1::text, $2::text, p, $4::int FROM unnest($3::text[]) AS p
''',
          [
            tag.id,
            ownerId,
            TypedValue(Type.textArray, copied.personIds),
            copied.source,
          ],
        );
      }
      return PersonTag(
        id: tag.id,
        name: tag.name,
        glyph: tag.glyph,
        color: tag.color,
        ord: tag.ord,
        count: copied?.personIds.length ?? 0,
      );
    },
    encode: (t) => t.toJson(),
  );

  @override
  Future<PersonTag> update({
    required String ownerId,
    required String clientOpId,
    required String fingerprint,
    required String id,
    String? name,
    String? glyph,
    int? color,
    int? ord,
  }) => _idempotent(
    ownerId,
    clientOpId,
    fingerprint,
    decode: PersonTag.fromJson,
    run: () async {
      final tags = await _list(ownerId);
      final current = _find(tags, id);
      if (name != null) await _checkNameFree(ownerId, name, exceptId: id);
      await _database.customStatement(
        r'''
UPDATE public.person_tag
   SET name = $3, glyph = $4, color = $5, updated_at = now()
 WHERE owner_id = $1 AND id = $2
''',
        [
          ownerId,
          id,
          name ?? current.name,
          glyph ?? current.glyph,
          color ?? current.color,
        ],
      );
      if (ord != null) {
        final ids = [for (final t in tags) t.id]
          ..remove(id)
          ..insert(ord.clamp(1, tags.length) - 1, id);
        await _writeOrder(ownerId, ids);
      }
      return (await _list(ownerId, withCounts: true)).singleWhere(
        (t) => t.id == id,
      );
    },
    encode: (t) => t.toJson(),
  );

  @override
  Future<PersonTagSnapshot> delete({
    required String ownerId,
    required String clientOpId,
    required String fingerprint,
    required String id,
  }) => _idempotent(
    ownerId,
    clientOpId,
    fingerprint,
    decode: PersonTagSnapshot.fromJson,
    run: () async {
      final tags = await _list(ownerId, withCounts: true);
      final tag = _find(tags, id);
      final members = await _database
          .customSelect(
            'SELECT person_id, source FROM public.person_tag_member '
            r'WHERE tag_id = $1 ORDER BY person_id',
            variables: [Variable.withString(id)],
          )
          .get();
      await _database.customStatement(
        r'DELETE FROM public.person_tag WHERE owner_id = $1 AND id = $2',
        [ownerId, id],
      );
      await _writeOrder(ownerId, [
        for (final t in tags)
          if (t.id != id) t.id,
      ]);
      return PersonTagSnapshot(
        tag: tag,
        memberIds: [for (final m in members) m.read<String>('person_id')],
        sources: [for (final m in members) m.read<int>('source')],
      );
    },
    encode: (s) => s.toGraphQL(),
  );

  @override
  Future<PersonTag> restore({
    required String ownerId,
    required String clientOpId,
    required String fingerprint,
    required PersonTagSnapshot snapshot,
  }) => _idempotent(
    ownerId,
    clientOpId,
    fingerprint,
    decode: PersonTag.fromJson,
    run: () async {
      final tags = await _list(ownerId);
      _checkRoom(tags);
      await _checkNameFree(ownerId, snapshot.tag.name);
      final taken = await _database
          .customSelect(
            r'SELECT 1 FROM public.person_tag WHERE id = $1',
            variables: [Variable.withString(snapshot.tag.id)],
          )
          .get();
      if (taken.isNotEmpty) {
        throw PeopleTagsException(
          peopleTagsCode: PeopleTagsExceptionCode.invalidTag,
        );
      }
      final position = snapshot.tag.ord.clamp(1, tags.length + 1);
      await _insert(
        ownerId,
        PersonTag(
          id: snapshot.tag.id,
          name: snapshot.tag.name,
          glyph: snapshot.tag.glyph,
          color: snapshot.tag.color,
          ord: tags.length + 1,
        ),
      );
      for (var i = 0; i < snapshot.memberIds.length; i++) {
        await _database.customStatement(
          r'''
INSERT INTO public.person_tag_member (tag_id, owner_id, person_id, source)
SELECT $1, $2, u.id, $4
  FROM public."user" u
 WHERE u.id = $3 AND u.id <> $2
ON CONFLICT DO NOTHING
''',
          [
            snapshot.tag.id,
            ownerId,
            snapshot.memberIds[i],
            snapshot.sources[i],
          ],
        );
      }
      final ids = [for (final t in tags) t.id]
        ..insert(position - 1, snapshot.tag.id);
      await _writeOrder(ownerId, ids);
      return (await _list(ownerId, withCounts: true)).singleWhere(
        (t) => t.id == snapshot.tag.id,
      );
    },
    encode: (t) => t.toJson(),
  );

  @override
  Future<void> applyMembers({
    required String ownerId,
    required String clientOpId,
    required String fingerprint,
    required List<PersonTagMemberOp> ops,
  }) => _idempotent<bool>(
    ownerId,
    clientOpId,
    fingerprint,
    decode: (_) => true,
    run: () async {
      final tagIds = {for (final t in await _list(ownerId)) t.id};
      if (ops.any((o) => !tagIds.contains(o.tagId))) {
        throw PeopleTagsException(
          peopleTagsCode: PeopleTagsExceptionCode.tagNotFound,
        );
      }
      final added = {
        for (final o in ops)
          if (o.add) o.personId,
      }.toList();
      final known = await _database
          .customSelect(
            r'SELECT id FROM public."user" WHERE id = ANY($1::text[])',
            variables: [Variable(TypedValue(Type.textArray, added))],
          )
          .get();
      if (known.length != added.length) {
        throw PeopleTagsException(
          peopleTagsCode: PeopleTagsExceptionCode.invalidTag,
        );
      }
      for (final o in ops) {
        if (o.add) {
          await _database.customStatement(
            r'''
INSERT INTO public.person_tag_member (tag_id, owner_id, person_id, source)
SELECT $1::text, $2::text, $3::text, $4::int
 WHERE NOT EXISTS (
   SELECT 1 FROM public.user_block ub
    WHERE (ub.blocker_id = $2 AND ub.blocked_id = $3)
       OR (ub.blocker_id = $3 AND ub.blocked_id = $2))
ON CONFLICT DO NOTHING
''',
            [o.tagId, ownerId, o.personId, o.source],
          );
        } else {
          await _database.customStatement(
            r'''
DELETE FROM public.person_tag_member
 WHERE tag_id = $1 AND owner_id = $2 AND person_id = $3
''',
            [o.tagId, ownerId, o.personId],
          );
        }
      }
      final over = await _database
          .customSelect(
            'SELECT 1 FROM public.person_tag_member '
            r'WHERE owner_id = $1 AND tag_id = ANY($2::text[]) '
            r'GROUP BY tag_id HAVING count(*) > $3',
            variables: [
              Variable.withString(ownerId),
              Variable(
                TypedValue(
                  Type.textArray,
                  {
                    for (final o in ops) o.tagId,
                  }.toList(),
                ),
              ),
              Variable.withInt(_maxMembers),
            ],
          )
          .get();
      if (over.isNotEmpty) {
        throw PeopleTagsException(
          peopleTagsCode: PeopleTagsExceptionCode.memberLimitReached,
        );
      }
      return true;
    },
    encode: (ok) => {'ok': ok},
  );

  @override
  Future<List<PersonTagMembers>> memberships(String ownerId) async {
    final rows = await _database
        .customSelect(
          '''
SELECT t.id AS tag_id,
       coalesce(
         array_agg(m.person_id ORDER BY m.person_id)
           FILTER (WHERE m.person_id IS NOT NULL),
         '{}'::text[]) AS person_ids
  FROM public.person_tag t
  LEFT JOIN public.person_tag_member m
    ON m.tag_id = t.id AND $_notBlockedSql
 WHERE t.owner_id = \$1
 GROUP BY t.id, t.ord, t.created_at
 ORDER BY t.ord, t.created_at, t.id
''',
          variables: [Variable.withString(ownerId)],
        )
        .get();
    return [
      for (final r in rows)
        PersonTagMembers(
          tagId: r.read<String>('tag_id'),
          personIds: r.read<List<dynamic>>('person_ids').cast<String>(),
        ),
    ];
  }

  @override
  Future<List<String>> tagIdsOf(String ownerId, String personId) async {
    final rows = await _database
        .customSelect(
          '''
SELECT t.id
  FROM public.person_tag t
  JOIN public.person_tag_member m ON m.tag_id = t.id
 WHERE t.owner_id = \$1 AND m.person_id = \$2 AND $_notBlockedSql
 ORDER BY t.ord, t.created_at, t.id
''',
          variables: [
            Variable.withString(ownerId),
            Variable.withString(personId),
          ],
        )
        .get();
    return [for (final r in rows) r.read<String>('id')];
  }

  @override
  Future<List<PersonAutoTagSummary>> autoTags(String ownerId) async {
    final rows = await _database
        .customSelect(
          r'''
SELECT a.kind::int AS kind, count(*)::int AS count, p.show_in_filters
  FROM public.person_auto_tags($1, NULL) a
  LEFT JOIN public.person_auto_tag_pref p
    ON p.owner_id = $1 AND p.kind = a.kind
 GROUP BY a.kind, p.show_in_filters
 ORDER BY a.kind
''',
          variables: [Variable.withString(ownerId)],
        )
        .get();
    return [
      for (final r in rows)
        PersonAutoTagSummary(
          kind: r.read<int>('kind'),
          count: r.read<int>('count'),
          showInFilters:
              r.readNullable<bool>('show_in_filters') ??
              PersonAutoTagKind.fromSmallint(
                r.read<int>('kind'),
              ).defaultShowInFilters,
        ),
    ];
  }

  @override
  Future<PersonAutoTagSummary> setAutoTagPref({
    required String ownerId,
    required int kind,
    required bool showInFilters,
  }) => _database.withMutatingUser(ownerId, () async {
    await _database.customStatement(
      'INSERT INTO public.person_auto_tag_pref '
      r'(owner_id, kind, show_in_filters) VALUES ($1, $2, $3) '
      'ON CONFLICT (owner_id, kind) '
      'DO UPDATE SET show_in_filters = EXCLUDED.show_in_filters',
      [ownerId, kind, showInFilters],
    );
    final count = await _database
        .customSelect(
          'SELECT count(*)::int AS c '
          r'FROM public.person_auto_tags($1, NULL) WHERE kind = $2',
          variables: [Variable.withString(ownerId), Variable.withInt(kind)],
        )
        .getSingle();
    return PersonAutoTagSummary(
      kind: kind,
      count: count.read<int>('c'),
      showInFilters: showInFilters,
    );
  });

  @override
  Future<List<String>> autoTagMembers(String ownerId, int kind) async {
    final rows = await _database
        .customSelect(
          r'SELECT peer_id FROM public.person_auto_tags($1, NULL) '
          r'WHERE kind = $2 ORDER BY peer_id',
          variables: [Variable.withString(ownerId), Variable.withInt(kind)],
        )
        .get();
    return [for (final r in rows) r.read<String>('peer_id')];
  }

  @override
  Future<List<PersonAutoTagOf>> autoTagsOf(
    String ownerId,
    String personId,
  ) async {
    final rows = await _database
        .customSelect(
          'SELECT kind::int AS kind, n, direction::int AS direction '
          r'FROM public.person_auto_tags($1, ARRAY[$2]::text[]) '
          'ORDER BY kind',
          variables: [
            Variable.withString(ownerId),
            Variable.withString(personId),
          ],
        )
        .get();
    return [
      for (final r in rows)
        PersonAutoTagOf(
          kind: r.read<int>('kind'),
          n: r.read<int>('n'),
          direction: r.read<int>('direction'),
        ),
    ];
  }

  @override
  Future<PersonTagSuggestionState> suggestionState(String ownerId) async {
    final rows = await _database
        .customSelect(
          r'''
SELECT NOT disabled AND (silenced_until IS NULL OR silenced_until <= now())
         AS can_suggest,
       silenced_until::text AS silenced_until,
       disabled
  FROM public.person_tag_suggestion_state
 WHERE owner_id = $1
''',
          variables: [Variable.withString(ownerId)],
        )
        .get();
    if (rows.isEmpty) {
      return const PersonTagSuggestionState(canSuggest: true, disabled: false);
    }
    final r = rows.single;
    final until = r.readNullable<String>('silenced_until');
    return PersonTagSuggestionState(
      canSuggest: r.read<bool>('can_suggest'),
      disabled: r.read<bool>('disabled'),
      silencedUntil: until == null ? null : DateTime.parse(until).toUtc(),
    );
  }

  @override
  Future<PersonTagSuggestionState> recordSuggestion({
    required String ownerId,
    required String clientOpId,
    required String fingerprint,
    required String outcome,
  }) => _idempotent(
    ownerId,
    clientOpId,
    fingerprint,
    decode: PersonTagSuggestionState.fromJson,
    run: () async {
      await _database.customStatement(
        r'''
INSERT INTO public.person_tag_suggestion_state (owner_id)
VALUES ($1) ON CONFLICT (owner_id) DO NOTHING
''',
        [ownerId],
      );
      await _database.customStatement(
        switch (outcome) {
          'skipped' => _skippedSql,
          'accepted' => _acceptedSql,
          'disabled' => _disabledSql,
          _ => _enabledSql,
        },
        [ownerId],
      );
      return suggestionState(ownerId);
    },
    encode: (s) => s.toJson(),
  );

  Future<T> _idempotent<T>(
    String ownerId,
    String clientOpId,
    String fingerprint, {
    required T Function(Map<String, dynamic>) decode,
    required Future<T> Function() run,
    required Map<String, dynamic> Function(T) encode,
  }) => _database.withMutatingUser(ownerId, () async {
    await _database.customStatement(
      r"SELECT pg_advisory_xact_lock(hashtextextended('person_tags:' || $1, 4242))",
      [ownerId],
    );
    final logged = await _database
        .customSelect(
          'SELECT fingerprint, result::text AS result '
          'FROM public.person_tag_op_log '
          r'WHERE owner_id = $1 AND client_op_id = $2',
          variables: [
            Variable.withString(ownerId),
            Variable.withString(clientOpId),
          ],
        )
        .get();
    if (logged.isNotEmpty) {
      if (logged.single.read<String>('fingerprint') != fingerprint) {
        throw PeopleTagsException(
          peopleTagsCode: PeopleTagsExceptionCode.opIdReused,
        );
      }
      return decode(
        jsonDecode(logged.single.read<String>('result'))
            as Map<String, dynamic>,
      );
    }
    final result = await run();
    await _database.customStatement(
      r'''
INSERT INTO public.person_tag_op_log
  (owner_id, client_op_id, fingerprint, result)
VALUES ($1, $2, $3, $4::jsonb)
''',
      [ownerId, clientOpId, fingerprint, jsonEncode(encode(result))],
    );
    return result;
  });

  Future<List<PersonTag>> _list(
    String ownerId, {
    bool withCounts = false,
  }) async {
    final rows = await _database
        .customSelect(
          'SELECT id, name, glyph, color, ord FROM public.person_tag '
          r'WHERE owner_id = $1 ORDER BY ord, created_at, id',
          variables: [Variable.withString(ownerId)],
        )
        .get();
    final counts = withCounts && rows.isNotEmpty
        ? await _counts(ownerId)
        : const <String, ({int count, int off})>{};
    return [
      for (final r in rows)
        PersonTag(
          id: r.read<String>('id'),
          name: r.read<String>('name'),
          glyph: r.read<String>('glyph'),
          color: r.read<int>('color'),
          ord: r.read<int>('ord'),
          count: counts[r.read<String>('id')]?.count ?? 0,
          countOffField: counts[r.read<String>('id')]?.off ?? 0,
        ),
    ];
  }

  /// Members per tag, blocked people left out, and of those the ones off the
  /// owner's Field: not visible (the transaction-memoised closed form, no
  /// MeritRank call of its own), not a bond, contact or pinned person. The
  /// visible set is only read when some member is left.
  Future<Map<String, ({int count, int off})>> _counts(String ownerId) async {
    final rows = await _database
        .customSelect(
          '''
WITH live AS MATERIALIZED (
  SELECT m.tag_id, m.person_id FROM public.person_tag_member m
   WHERE m.owner_id = \$1 AND $_notBlockedSql
),
visible AS MATERIALIZED (
  SELECT public.person_visible_peer_ids_tx(\$1, '') AS ids
   WHERE EXISTS (SELECT 1 FROM live)
),
near AS MATERIALIZED (
  SELECT vu.object AS id FROM public.vote_user vu
   WHERE vu.subject = \$1 AND vu.amount > 0
  UNION
  SELECT b.peer_id FROM public.person_bond_peers(\$1) b
  UNION
  SELECT a.person_id FROM public.constellation_anchor a
   WHERE a.viewer_id = \$1 AND a.person_id IS NOT NULL
)
SELECT l.tag_id,
       count(*) AS member_count,
       count(*) FILTER (
         WHERE NOT (l.person_id = ANY(
                 coalesce((SELECT v.ids FROM visible v), '{}'::text[])))
           AND NOT EXISTS (SELECT 1 FROM near n WHERE n.id = l.person_id)
       ) AS off_field_count
  FROM live l
 GROUP BY l.tag_id
''',
          variables: [Variable.withString(ownerId)],
        )
        .get();
    return {
      for (final r in rows)
        r.read<String>('tag_id'): (
          count: r.read<int>('member_count'),
          off: r.read<int>('off_field_count'),
        ),
    };
  }

  PersonTag _find(List<PersonTag> tags, String id) => tags.firstWhere(
    (t) => t.id == id,
    orElse: () => throw PeopleTagsException(
      peopleTagsCode: PeopleTagsExceptionCode.tagNotFound,
    ),
  );

  /// The people a new tag is pre-filled with, or null for an empty tag.
  /// Blocked people (either direction) and the owner are left out; more than
  /// 1000 left throws memberLimitReached instead of truncating.
  Future<({List<String> personIds, int source})?> _sourcePeople(
    String ownerId, {
    int? fromAutoKind,
    String? fromBeaconId,
  }) async {
    if (fromAutoKind == null && fromBeaconId == null) return null;
    final int source;
    final List<String> candidates;
    if (fromAutoKind != null) {
      source = 2;
      candidates = await autoTagMembers(ownerId, fromAutoKind);
    } else {
      source = 3;
      final beacon = await _database
          .customSelect(
            r'''
SELECT EXISTS (
  SELECT 1 FROM public.beacon b
    JOIN public.beacon_member me
      ON me.beacon_id = b.id AND me.user_id = $2
   WHERE b.id = $1 AND b.kind = 0) AS ok
''',
            variables: [
              Variable.withString(fromBeaconId!),
              Variable.withString(ownerId),
            ],
          )
          .getSingle();
      if (!beacon.read<bool>('ok')) {
        throw PeopleTagsException(
          peopleTagsCode: PeopleTagsExceptionCode.invalidTag,
        );
      }
      final rows = await _database
          .customSelect(
            r'''
SELECT DISTINCT user_id FROM public.beacon_member
 WHERE beacon_id = $1 AND user_id <> $2
 ORDER BY user_id
''',
            variables: [
              Variable.withString(fromBeaconId),
              Variable.withString(ownerId),
            ],
          )
          .get();
      candidates = [for (final r in rows) r.read<String>('user_id')];
    }
    final rows = await _database
        .customSelect(
          r'''
SELECT p AS person_id FROM unnest($2::text[]) AS m(p)
 WHERE p <> $1
   AND NOT EXISTS (
     SELECT 1 FROM public.user_block ub
      WHERE (ub.blocker_id = $1 AND ub.blocked_id = m.p)
         OR (ub.blocker_id = m.p AND ub.blocked_id = $1))
 ORDER BY p
''',
          variables: [
            Variable.withString(ownerId),
            Variable(TypedValue(Type.textArray, candidates)),
          ],
        )
        .get();
    if (rows.length > _maxMembers) {
      throw PeopleTagsException(
        peopleTagsCode: PeopleTagsExceptionCode.memberLimitReached,
      );
    }
    return (
      personIds: [for (final r in rows) r.read<String>('person_id')],
      source: source,
    );
  }

  void _checkRoom(List<PersonTag> tags) {
    if (tags.length >= _maxTags) {
      throw PeopleTagsException(
        peopleTagsCode: PeopleTagsExceptionCode.tagLimitReached,
      );
    }
  }

  Future<void> _checkNameFree(
    String ownerId,
    String name, {
    String? exceptId,
  }) async {
    final rows = await _database
        .customSelect(
          'SELECT 1 FROM public.person_tag '
          r'WHERE owner_id = $1 AND lower(name) = lower($2) AND id <> $3',
          variables: [
            Variable.withString(ownerId),
            Variable.withString(name),
            Variable.withString(exceptId ?? ''),
          ],
        )
        .get();
    if (rows.isNotEmpty) {
      throw PeopleTagsException(
        peopleTagsCode: PeopleTagsExceptionCode.tagNameTaken,
      );
    }
  }

  /// Also creates the owner's revision row with their first tag.
  Future<void> _insert(String ownerId, PersonTag tag) async {
    await _database.customStatement(
      r'''
INSERT INTO public.person_tag (id, owner_id, name, glyph, color, ord)
VALUES ($1, $2, $3, $4, $5, $6)
''',
      [tag.id, ownerId, tag.name, tag.glyph, tag.color, tag.ord],
    );
    await _database.customStatement(
      r'''
INSERT INTO public.person_tag_revision (owner_id) VALUES ($1)
ON CONFLICT (owner_id) DO NOTHING
''',
      [ownerId],
    );
  }

  /// Dense `ord` 1..n following [orderedIds].
  Future<void> _writeOrder(String ownerId, List<String> orderedIds) async {
    for (var i = 0; i < orderedIds.length; i++) {
      await _database.customStatement(
        r'''
UPDATE public.person_tag SET ord = $3
 WHERE owner_id = $1 AND id = $2 AND ord <> $3
''',
        [ownerId, orderedIds[i], i + 1],
      );
    }
  }
}
