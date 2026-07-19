import 'package:freezed_annotation/freezed_annotation.dart';

import 'trust_bin.dart';
import 'trust_context.dart';
import 'trust_evidence_metadata.dart';
import 'trust_source_type.dart';

part 'trust_evidence.freezed.dart';

@freezed
abstract class TrustEvidence with _$TrustEvidence {
  const factory TrustEvidence({
    required String targetUserId,
    required TrustBin bin,
    required double count,
    required TrustContext context,
    required TrustSourceType sourceType,
    String? requestId,
    String? sourceId,
    @Default(TrustEvidenceMetadata()) TrustEvidenceMetadata metadata,
  }) = _TrustEvidence;
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
