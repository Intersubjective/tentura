import 'package:freezed_annotation/freezed_annotation.dart';

import '../entity/forward_attribution_method.dart';

part 'trust_evidence_metadata.freezed.dart';

/// Typed audit metadata stored in `trust_evidence_event.metadata` jsonb.
@freezed
abstract class TrustEvidenceMetadata with _$TrustEvidenceMetadata {
  const factory TrustEvidenceMetadata({
    @Default(0) int algorithmVersion,
    @Default(<String>[]) List<String> supportingCommitmentIds,
    ForwardAttributionMethod? attributionMethod,
  }) = _TrustEvidenceMetadata;

  const TrustEvidenceMetadata._();

  Map<String, Object?> toJson() => {
    if (algorithmVersion != 0) 'algorithm_version': algorithmVersion,
    if (supportingCommitmentIds.isNotEmpty)
      'supporting_commitment_ids': supportingCommitmentIds,
    if (attributionMethod != null)
      'attribution_method': attributionMethod!.key,
  };
}
