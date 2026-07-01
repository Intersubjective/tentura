import 'package:injectable/injectable.dart';

import 'package:tentura_server/domain/entity/gql_public/mutual_score_record.dart';
import 'package:tentura_server/domain/port/merit_score_lookup_port.dart';

import '../database/tentura_db.dart';

/// Batch MeritRank reciprocal-positive scores for one viewer, shared by any
/// feature that needs to attach `Profile.score`/`Profile.rScore` to a list of
/// users relative to the signed-in viewer (mutual friends, invite genealogy).
@LazySingleton(as: MeritScoreLookupPort)
class MeritScoreLookup implements MeritScoreLookupPort {
  MeritScoreLookup(this._database);

  final TenturaDb _database;

  /// Viewer→peer (fwd) and peer→viewer (rev) from `mr_mutual_scores`, same
  /// semantics as `mutual_friends` SQL (`alice_peers` CTE).
  @override
  Future<Map<String, MutualScoreRecord>> reciprocalScoresForViewer({
    required String viewerId,
    required String context,
  }) async {
    final scoreRows = await _database
        .customSelect(
          r'''
SELECT
  CASE WHEN ms.src = $1 THEN ms.dst::text ELSE ms.src::text END AS peer_id,
  CASE WHEN ms.src = $1 THEN ms.score_value_of_dst
       ELSE ms.score_value_of_src END AS fwd_alice,
  CASE WHEN ms.src = $1 THEN ms.score_value_of_src
       ELSE ms.score_value_of_dst END AS rev_alice
FROM mr_mutual_scores($1, $2) ms
WHERE (ms.src = $1 OR ms.dst = $1)
  AND ms.score_value_of_src > 0::double precision
  AND ms.score_value_of_dst > 0::double precision
''',
          variables: [
            Variable<String>(viewerId),
            Variable<String>(context),
          ],
        )
        .get();

    final out = <String, MutualScoreRecord>{};
    for (final row in scoreRows) {
      final peerId = row.data['peer_id']! as String;
      out[peerId] = MutualScoreRecord(
        dstScore: _asDouble(row.data['fwd_alice']),
        srcScore: _asDouble(row.data['rev_alice']),
      );
    }
    return out;
  }

  static double _asDouble(Object? value) {
    if (value == null) {
      return 0;
    }
    if (value is num) {
      return value.toDouble();
    }
    throw StateError('Expected num, got ${value.runtimeType}');
  }
}
