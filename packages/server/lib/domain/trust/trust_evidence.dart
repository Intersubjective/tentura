import 'trust_bin.dart';

/// One piece of trust evidence targeting a single outgoing edge.
final class TrustEvidence {
  const TrustEvidence({
    required this.targetUserId,
    required this.bin,
    required this.count,
  });

  final String targetUserId;
  final TrustBin bin;
  final double count;
}

/// Batch of evidence from one source user at a point in time.
final class TrustEvidenceBatch {
  const TrustEvidenceBatch({
    required this.sourceUserId,
    required this.at,
    required this.items,
  });

  final String sourceUserId;
  final DateTime at;
  final List<TrustEvidence> items;
}
