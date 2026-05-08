part of '_migrations.dart';

/// Strip NULL entries from `beacon_room_message.mentions` (`text[]`).
///
/// Postgres allows NULL elements inside text arrays. The Dart `postgres`
/// driver decodes those as `List<String?>`, which then fails Drift's
/// `PgTypes.textArray` read (`fromSql as List<String>`) when loading room
/// messages — surfacing as GraphQL
/// `type 'List<String?>' is not a subtype of type 'List<String>' in type cast`.
final m0060 = Migration('0060', [
  '''
UPDATE public.beacon_room_message
SET mentions = array_remove(mentions, NULL::text);
''',
]);
