import 'package:postgres/postgres.dart' show Type, TypedValue;
import 'package:injectable/injectable.dart';
import 'package:logging/logging.dart';

import 'package:tentura_server/domain/port/person_visibility_repository_port.dart';

import '../database/tentura_db.dart';

/// Mutual IDs via symmetric `person_are_mutually_visible` (m0161 / D14);
/// co-participant bond via `person_bond*` (m0173).
@LazySingleton(as: PersonVisibilityRepositoryPort)
class PersonVisibilityRepository implements PersonVisibilityRepositoryPort {
  PersonVisibilityRepository(this._database);

  static final _log = Logger('PersonVisibilityRepository');

  final TenturaDb _database;

  Future<bool> _hasMeritRank() async {
    final row = await _database
        .customSelect(
          "SELECT to_regprocedure('public.mr_mutual_scores(text, text)') "
          'IS NOT NULL AS present',
        )
        .getSingle();
    return row.read<bool>('present');
  }

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

  @override
  Future<Set<String>> bondPeerIds({required String viewerId}) async {
    if (viewerId.isEmpty) {
      return {};
    }

    final rows = await _database
        .customSelect(
          r'SELECT peer_id FROM public.person_bond_peers($1)',
          variables: [Variable.withString(viewerId)],
        )
        .get();

    return rows.map((row) => row.read<String>('peer_id')).toSet();
  }

  @override
  Future<Set<String>> personVisiblePeerIds({
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

    // Checked up front (not by catching 42883): Post checks run inside the
    // publish transaction, where a failed statement would abort it.
    final hasMeritRank = await _hasMeritRank();
    if (!hasMeritRank) {
      _log.warning(
        'mr_mutual_scores() is missing: MeritRank is unavailable, so only '
        'reciprocal explicit trust and bonds make peers visible',
      );
    }
    final reach = hasMeritRank
        ? r'public.person_are_mutually_visible($1, c.peer_id, $2)'
        : r'public.person_reciprocal_explicit_trust($1, c.peer_id)';
    final rows = await _database
        .customSelect(
          r'''
SELECT DISTINCT c.peer_id
FROM unnest($3::text[]) AS c(peer_id)
WHERE c.peer_id <> $1
  AND NOT public.block_hides($1, c.peer_id)
  AND (''' +
              reach +
              r'''
       OR public.person_bond($1, c.peer_id))
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

  @override
  Future<List<({String beaconId, String title})>> sharedContexts({
    required String viewerId,
    required String peerId,
  }) async {
    if (viewerId.isEmpty || peerId.isEmpty) {
      return const [];
    }

    final rows = await _database
        .customSelect(
          r'SELECT beacon_id, title FROM public.person_shared_contexts($1, $2)',
          variables: [
            Variable.withString(viewerId),
            Variable.withString(peerId),
          ],
        )
        .get();

    return [
      for (final row in rows)
        (
          beaconId: row.read<String>('beacon_id'),
          title: row.read<String>('title'),
        ),
    ];
  }
}
