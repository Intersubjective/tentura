import 'package:meta/meta.dart';

/// Matches Hasura `mutual_score` (`src_score`, `dst_score`).
@immutable
class MutualScoreRecord {
  const MutualScoreRecord({
    this.srcScore,
    this.dstScore,
  });

  final double? srcScore;
  final double? dstScore;
}
