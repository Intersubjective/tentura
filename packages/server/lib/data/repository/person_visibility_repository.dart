import 'package:drift/drift.dart' hide Column;
import 'package:postgres/postgres.dart' show Type, TypedValue;
import 'package:injectable/injectable.dart';

import 'package:tentura_server/domain/port/person_visibility_repository_port.dart';

import '../database/tentura_db.dart';

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
SELECT p.peer_id::text AS peer_id
FROM public.person_visibility_peers($1, $2) p
WHERE p.is_mutually_visible
  AND p.peer_id = ANY($3::text[])
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
