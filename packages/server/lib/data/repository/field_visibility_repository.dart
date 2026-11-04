import 'package:injectable/injectable.dart';

import 'package:tentura_server/domain/entity/field_hidden_item.dart';
import 'package:tentura_server/domain/entity/field_search_result.dart';
import 'package:tentura_server/domain/entity/person_field_items_page.dart';
import 'package:tentura_server/domain/exception.dart';
import 'package:tentura_server/domain/port/field_visibility_repository_port.dart';

import '../database/tentura_db.dart';
import 'field_search_reader.dart';

@LazySingleton(as: FieldVisibilityRepositoryPort)
final class FieldVisibilityRepository implements FieldVisibilityRepositoryPort {
  const FieldVisibilityRepository(this._database);

  final TenturaDb _database;

  @override
  Future<FieldSearchResult> search({
    required String viewerId,
    required String context,
    required List<String> words,
  }) => FieldSearchReader(_database).read(
    viewerId: viewerId,
    context: context,
    words: words,
  );

  @override
  Future<PersonFieldItemsPage> personItems({
    required String viewerId,
    required String personId,
    required PersonFieldBucket bucket,
    required List<String> words,
    PersonFieldCursor? cursor,
  }) => FieldSearchReader(_database).readPersonItems(
    viewerId: viewerId,
    personId: personId,
    bucket: bucket,
    words: words,
    cursor: cursor,
  );

  @override
  Future<void> setHidden({
    required String viewerId,
    required FieldTargetKind targetKind,
    required String targetId,
    required bool hidden,
  }) => _database.withMutatingUser(viewerId, () async {
    final variables = [
      Variable.withString(viewerId),
      Variable.withInt(targetKind.value),
      Variable.withString(targetId),
    ];
    final readable = await _database.customSelect(
      r'''
SELECT b.id FROM public.beacon b
WHERE b.id = $3 AND b.kind = $2
  AND public.beacon_can_read_content(b.id, $1)
FOR SHARE
''',
      variables: variables,
    ).get();
    if (readable.isEmpty) {
      throw const UnauthorizedException(
        description: 'Viewer cannot read target',
      );
    }
    await _database.customUpdate(
      hidden
          ? r'''
INSERT INTO public.field_hidden (viewer_id, target_kind, target_id)
VALUES ($1, $2, $3)
ON CONFLICT (viewer_id, target_kind, target_id) DO UPDATE
SET hidden_at = EXCLUDED.hidden_at
WHERE NOT public.field_hide_is_effective(
  field_hidden.viewer_id, field_hidden.target_kind,
  field_hidden.target_id, field_hidden.hidden_at
)
'''
          : r'''
DELETE FROM public.field_hidden
WHERE viewer_id = $1 AND target_kind = $2 AND target_id = $3
''',
      variables: variables,
    );
  });

  @override
  Future<List<FieldHiddenItem>> hiddenItems({
    required String viewerId,
    DateTime? before,
  }) async {
    final rows = await _database
        .customSelect(
          r'''
SELECT h.target_kind::int, h.target_id, h.hidden_at::text,
       b.user_id AS author_id,
       CASE WHEN b.kind = 1 THEN COALESCE(root.body, '') ELSE b.title END AS title
FROM public.field_hidden h
JOIN public.beacon b ON b.id = h.target_id AND b.kind = h.target_kind
LEFT JOIN public.beacon_room_message root
  ON root.id = b.post_root_message_id AND root.beacon_id = b.id
WHERE h.viewer_id = $1
  AND ($2::timestamptz IS NULL OR h.hidden_at < $2::timestamptz)
  AND public.field_hide_is_effective(h.viewer_id, h.target_kind, h.target_id, h.hidden_at)
  AND public.beacon_can_read_content(b.id, $1)
ORDER BY h.hidden_at DESC, h.target_kind DESC, h.target_id DESC
''',
          variables: [
            Variable.withString(viewerId),
            Variable<String>(before?.toUtc().toIso8601String()),
          ],
        )
        .get();
    return [
      for (final row in rows)
        (
          targetKind: FieldTargetKind.parse(row.read<int>('target_kind')),
          targetId: row.read<String>('target_id'),
          title: row.read<String>('title'),
          authorId: row.read<String>('author_id'),
          hiddenAt: DateTime.parse(row.read<String>('hidden_at')).toUtc(),
        ),
    ];
  }
}
