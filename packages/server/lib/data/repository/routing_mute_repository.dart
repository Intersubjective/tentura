import 'package:drift/drift.dart' show Variable;
import 'package:drift_postgres/drift_postgres.dart';
import 'package:injectable/injectable.dart';

import 'package:tentura_server/domain/port/routing_mute_port.dart';

import '../database/tentura_db.dart';

@Injectable(
  as: RoutingMutePort,
  env: [Environment.dev, Environment.prod],
  order: 1,
)
class RoutingMuteRepository implements RoutingMutePort {
  const RoutingMuteRepository(this._database);

  final TenturaDb _database;

  @override
  Future<Map<String, Set<String>>> mutedSlugsFor({
    required List<String> subjectIds,
  }) async {
    if (subjectIds.isEmpty) return const {};

    final rows = await _database
        .customSelect(
          r'''
SELECT user_id, tag_slug
FROM public.capability_routing_mute
WHERE user_id = ANY($1::text[])
ORDER BY user_id, tag_slug
''',
          variables: [
            Variable<List<String>>(subjectIds, PgTypes.textArray),
          ],
          readsFrom: {_database.capabilityRoutingMutes},
        )
        .get();

    final result = <String, Set<String>>{};
    for (final row in rows) {
      final userId = row.read<String>('user_id');
      result.putIfAbsent(userId, () => {}).add(row.read<String>('tag_slug'));
    }
    return result;
  }

  @override
  Future<Set<String>> mutedSlugsForUser(String userId) async {
    final rows = await _database
        .customSelect(
          r'''
SELECT tag_slug
FROM public.capability_routing_mute
WHERE user_id = $1
ORDER BY tag_slug
''',
          variables: [Variable<String>(userId)],
          readsFrom: {_database.capabilityRoutingMutes},
        )
        .get();

    return {for (final row in rows) row.read<String>('tag_slug')};
  }

  @override
  Future<void> setMute({
    required String userId,
    required String tagSlug,
    required bool muted,
  }) async {
    if (muted) {
      await _database.customStatement(
        r'''
INSERT INTO public.capability_routing_mute (user_id, tag_slug)
VALUES ($1, $2)
ON CONFLICT (user_id, tag_slug) DO NOTHING
''',
        [userId, tagSlug],
      );
      return;
    }

    await _database.customStatement(
      r'''
DELETE FROM public.capability_routing_mute
WHERE user_id = $1 AND tag_slug = $2
''',
      [userId, tagSlug],
    );
  }
}
