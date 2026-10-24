import 'dart:convert';

import 'package:injectable/injectable.dart';

import 'package:tentura_server/domain/entity/person_tag.dart';
import 'package:tentura_server/domain/exception.dart';
import 'package:tentura_server/domain/exception_codes.dart';
import 'package:tentura_server/domain/port/people_tags_repository_port.dart';
import 'package:tentura_server/utils/id.dart';

import '../database/tentura_db.dart';

const _maxTags = 50;
const _colors = 8;

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
  Future<List<PersonTag>> list(String ownerId) => _list(ownerId);

  @override
  Future<PersonTag> create({
    required String ownerId,
    required String clientOpId,
    required String fingerprint,
    required String name,
    required String glyph,
    int? color,
  }) => _idempotent(
    ownerId,
    clientOpId,
    fingerprint,
    decode: PersonTag.fromJson,
    run: () async {
      final tags = await _list(ownerId);
      _checkRoom(tags);
      await _checkNameFree(ownerId, name);
      final tag = PersonTag(
        id: generateId('PT'),
        name: name,
        glyph: glyph,
        color: color ?? tags.length % _colors,
        ord: tags.length + 1,
      );
      await _insert(ownerId, tag);
      return tag;
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
      return (await _list(ownerId)).singleWhere((t) => t.id == id);
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
      final tags = await _list(ownerId);
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
    encode: (s) => s.toJson(),
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
      return (await _list(ownerId)).singleWhere((t) => t.id == snapshot.tag.id);
    },
    encode: (t) => t.toJson(),
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

  Future<List<PersonTag>> _list(String ownerId) async {
    final rows = await _database
        .customSelect(
          'SELECT id, name, glyph, color, ord FROM public.person_tag '
          r'WHERE owner_id = $1 ORDER BY ord, created_at, id',
          variables: [Variable.withString(ownerId)],
        )
        .get();
    return [
      for (final r in rows)
        PersonTag(
          id: r.read<String>('id'),
          name: r.read<String>('name'),
          glyph: r.read<String>('glyph'),
          color: r.read<int>('color'),
          ord: r.read<int>('ord'),
        ),
    ];
  }

  PersonTag _find(List<PersonTag> tags, String id) => tags.firstWhere(
    (t) => t.id == id,
    orElse: () => throw PeopleTagsException(
      peopleTagsCode: PeopleTagsExceptionCode.tagNotFound,
    ),
  );

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
