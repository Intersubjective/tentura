import 'package:freezed_annotation/freezed_annotation.dart';

import 'package:tentura_server/domain/trust/dirichlet_counts.dart';

part 'trust_edge.freezed.dart';

@freezed
abstract class TrustEdge with _$TrustEdge {
  const factory TrustEdge({
    required String subject,
    required String object,
    required DirichletCounts counts,
    required DateTime lastDecayAt,
    required double prevSentWeight,
  }) = _TrustEdge;

  const TrustEdge._();
}
