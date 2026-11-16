import 'package:drift_postgres/drift_postgres.dart';
import 'package:injectable/injectable.dart';

import 'package:tentura_server/domain/notification/notification_identity.dart';
import 'package:tentura_server/domain/notification/notification_text.dart';

import '../database/tentura_db.dart';

const _actorNameLimit = 32;
const _requestLabelLimit = 32;
const _postLabelLimit = 40;

@Singleton(as: NotificationIdentityPort)
class NotificationIdentityRepository implements NotificationIdentityPort {
  const NotificationIdentityRepository(this._db);

  final TenturaDb _db;

  // Absent actor/related ids travel as '' (no beacon or user has that id).
  static const _sql = r'''
SELECT
  r.ord,
  b.kind AS kind,
  b.status AS status,
  b.title AS title,
  (b.id IS NOT NULL AND public.beacon_can_read_content(b.id, $1)) AS readable,
  (b.id IS NOT NULL AND public.beacon_can_read_tombstone(b.id, $1))
    AS tombstone,
  root.body AS root_body,
  EXISTS (
    SELECT 1 FROM public.beacon_room_message_attachment att
    WHERE att.message_id = root.id AND att.kind = 1
  ) AS root_has_image,
  public.block_hides(r.actor_id, $1) AS actor_hidden,
  u.display_name AS actor_name,
  rb.title AS related_title,
  au.display_name AS author_name
FROM unnest($2::text[], $3::text[], $4::text[])
  WITH ORDINALITY AS r(beacon_id, actor_id, related_id, ord)
LEFT JOIN public.beacon b ON b.id = r.beacon_id
LEFT JOIN public."user" au ON au.id = b.user_id
LEFT JOIN public.beacon_room_message root
  ON root.id = b.post_root_message_id AND root.beacon_id = b.id
LEFT JOIN public."user" u ON u.id = r.actor_id
LEFT JOIN public.beacon rb
  ON rb.id = r.related_id AND rb.kind = 0
  AND public.beacon_can_read_content(rb.id, $1)
ORDER BY r.ord
''';

  @override
  Future<List<NotificationIdentity>> resolve(
    String recipientId,
    List<IdentityRequest> requests,
  ) async {
    if (requests.isEmpty) return const [];
    final rows = await _db
        .customSelect(
          _sql,
          variables: [
            Variable<String>(recipientId),
            for (final column in [
              [for (final q in requests) q.beaconId],
              [for (final q in requests) q.actorId ?? ''],
              [for (final q in requests) q.relatedBeaconId ?? ''],
            ])
              Variable<List<String>>(column, PgTypes.textArray),
          ],
        )
        .get();
    return [for (final row in rows) _identity(row)];
  }

  static String? _clean(String? raw, int limit) {
    final text = NotificationText.truncate(
      NotificationText.normalize(raw ?? ''),
      limit,
    );
    return text.isEmpty ? null : text;
  }

  static NotificationIdentity _identity(QueryRow row) {
    final isPost = row.read<int?>('kind') == 1;
    final readable = row.read<bool>('readable');
    final hidden = row.read<bool>('actor_hidden');
    final rawTitle = row.read<String?>('title');
    final rootBody = row.read<String?>('root_body');
    return NotificationIdentity(
      entityKind:
          isPost ? NotificationEntityKind.post : NotificationEntityKind.request,
      label: !readable
          ? null
          : isPost
          ? _clean(rootBody, _postLabelLimit)
          : _clean(rawTitle, _requestLabelLimit),
      tombstone: row.read<bool>('tombstone'),
      readable: readable,
      actorName: hidden
          ? null
          : _clean(row.read<String?>('actor_name'), _actorNameLimit),
      actorHidden: hidden,
      relatedLabel: _clean(
        row.read<String?>('related_title'),
        _requestLabelLimit,
      ),
      expired: readable && isPost && row.read<int?>('status') == 6,
      hasImage:
          readable && isPost && row.read<bool>('root_has_image'),
      deleted: row.read<int?>('status') == 2,
      authorName: readable && isPost
          ? _clean(row.read<String?>('author_name'), _actorNameLimit)
          : null,
    );
  }
}
