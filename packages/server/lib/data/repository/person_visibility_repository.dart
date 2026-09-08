import 'package:drift/drift.dart' hide Column;
import 'package:postgres/postgres.dart' show Type, TypedValue;
import 'package:injectable/injectable.dart';

import 'package:tentura_server/domain/port/person_visibility_repository_port.dart';

import '../database/tentura_db.dart';

/// Mutual IDs via symmetric `person_are_mutually_visible` (m0161 / D14).
@LazySingleton(as: PersonVisibilityRepositoryPort)
class PersonVisibilityRepository implements PersonVisibilityRepositoryPort {
  PersonVisibilityRepository(this._database);

  final TenturaDb _database;

  @override
  Future<Set<String>> mutuallyVisiblePeerIds({
    required String viewerId,
    required Iterable<String> peerIds,
    required String context,
  }) async {
    if (viewerId.isEmpty) {
      return {};
    }
    final candidates = peerIds
        .where((id) => id.isNotEmpty && id != viewerId)
        .toSet();
    if (candidates.isEmpty) {
      return {};
    }

    final rows = await _database
        .customSelect(
          r'''
SELECT DISTINCT c.peer_id
FROM unnest($3::text[]) AS c(peer_id)
WHERE c.peer_id <> $1
  AND public.person_are_mutually_visible($1, c.peer_id, $2)
  AND NOT public.block_hides($1, c.peer_id)
''',
          variables: [
            Variable.withString(viewerId),
            Variable.withString(context),
            Variable(TypedValue(Type.textArray, candidates.toList())),
          ],
        )
        .get();

    return rows.map((row) => row.read<String>('peer_id')).toSet();
  }
}
