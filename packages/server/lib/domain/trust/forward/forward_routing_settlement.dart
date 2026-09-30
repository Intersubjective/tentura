import 'package:tentura_server/domain/trust/ledger_evidence.dart';
import 'package:tentura_server/domain/trust/trust_evidence_kind.dart';

import 'forward_causal_graph_builder.dart';
import 'forward_graph_integrity_exception.dart';
import 'forward_local_normalizer.dart';
import 'forward_mass_propagator.dart';
import 'forward_provenance.dart';
import 'forward_request_consolidator.dart';

final class RoutingInput {
  const RoutingInput({
    required this.beaconId,
    required this.epoch,
    required this.authorId,
    required this.seedOfferAt,
    required this.edges,
    required this.attributionByBatch,
    required this.budget,
  });

  final String beaconId;
  final int epoch;
  final String authorId;

  /// M_route member → offer created_at.
  final Map<String, DateTime> seedOfferAt;

  /// All provenance edges of the request.
  final List<ForwardProvenanceEdge> edges;
  final Map<String, List<ForwardAttributionInput>> attributionByBatch;

  /// Per-sender budget per episode (rho * B).
  final double budget;
}

/// Pure routing settlement (arch §5.8): every seed carries mass 1.0
/// regardless of outcome; each sender spends at most [RoutingInput.budget].
final class ForwardRoutingSettlement {
  List<LedgerEvidence> settle(RoutingInput input) {
    final builder = ForwardCausalGraphBuilder();
    final propagator = ForwardMassPropagator();
    final normalizer = ForwardLocalNormalizer();
    final consolidator = ForwardRequestConsolidator();

    final perSeedShares = <Map<ForwardPair, double>>[];
    for (final seed in input.seedOfferAt.entries) {
      EligibleForwardDag? dag;
      try {
        dag = builder.build(
          authorId: input.authorId,
          committerId: seed.key,
          commitmentAt: seed.value,
          allEdges: input.edges,
        );
      } on ForwardGraphIntegrityException {
        continue;
      }
      if (dag == null) continue;
      final raw = propagator.propagate(
        dag: dag,
        attributionsByBatchId: input.attributionByBatch,
      );
      perSeedShares.add(normalizer.normalize(raw));
    }

    final deltas = consolidator.normalizePerSender(
      consolidator.accumulate(perSeedShares),
      budget: input.budget,
    );

    return [
      for (final entry in deltas.entries)
        if (entry.value > 0 && entry.key.$1 != entry.key.$2)
          LedgerEvidence(
            subjectId: entry.key.$1,
            objectId: entry.key.$2,
            kind: TrustEvidenceKind.routed,
            count: entry.value,
            sourceKey:
                'closure:${input.beaconId}:${input.epoch}:routed:'
                '${entry.key.$1}:${entry.key.$2}',
            beaconId: input.beaconId,
            epoch: input.epoch,
          ),
    ];
  }
}
