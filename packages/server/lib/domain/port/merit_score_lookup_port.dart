import 'package:tentura_server/domain/entity/gql_public/mutual_score_record.dart';

abstract class MeritScoreLookupPort {
  /// Reciprocal-positive MeritRank scores for [viewerId] in [context], keyed
  /// by peer id. `dstScore` is viewer→peer, `srcScore` is peer→viewer
  /// (same "mutual" semantics as `mutual_friends`: a peer only appears when
  /// both directions are positive).
  Future<Map<String, MutualScoreRecord>> reciprocalScoresForViewer({
    required String viewerId,
    required String context,
  });
}
