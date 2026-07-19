import 'package:freezed_annotation/freezed_annotation.dart';

import 'package:tentura_server/domain/trust/trust_bin.dart';
import 'package:tentura_server/domain/trust/trust_source_type.dart';

import 'forward_causal_graph_builder.dart';
import 'forward_graph_integrity_exception.dart';
import 'forward_local_normalizer.dart';
import 'forward_mass_propagator.dart';
import 'forward_outcome_policy.dart';
import 'forward_provenance.dart';
import 'forward_request_consolidator.dart';

part 'forward_outcome_finalizer.freezed.dart';

@freezed
sealed class ForwardFinalizationDiagnostics with _$ForwardFinalizationDiagnostics {
  const factory ForwardFinalizationDiagnostics({
    required int eligibleEdgeCount,
    required int rootlessEdgeCount,
    required List<String> integrityFailedCommitters,
    required Map<String, double> budgetBySender,
    required int observedPairCount,
    required int unsuccessfulPairCount,
  }) = _ForwardFinalizationDiagnostics;
}

final class EvaluatedOutcomeEvidence {
  const EvaluatedOutcomeEvidence({
    required this.senderId,
    required this.recipientId,
    required this.bin,
    required this.count,
    required this.sourceType,
    required this.provenance,
  });

  final String senderId;
  final String recipientId;
  final TrustBin bin;
  final double count;
  final TrustSourceType sourceType;
  final ForwardOutcomeProvenance provenance;
}

final class ForwardOutcomeResult {
  const ForwardOutcomeResult({
    required this.propagatedOutcomes,
    required this.unsuccessfulPairs,
    required this.diagnostics,
  });

  final List<EvaluatedOutcomeEvidence> propagatedOutcomes;
  final List<ForwardPair> unsuccessfulPairs;
  final ForwardFinalizationDiagnostics diagnostics;
}

/// Pure forward outcome finalization (§3, §9.1).
final class ForwardOutcomeFinalizer {
  ForwardOutcomeResult compute({
    required String authorId,
    required DateTime finalizedAt,
    required Map<String, int> authorEvaluationByCommitter,
    required Map<String, DateTime> commitmentAtByCommitter,
    required List<ForwardProvenanceEdge> allEdges,
    required Map<String, List<ForwardAttributionInput>> attributionsByBatchId,
    required Duration minOpportunity,
    required double unsuccessfulCount,
  }) {
    if (authorEvaluationByCommitter.isEmpty) {
      return ForwardOutcomeResult(
        propagatedOutcomes: const [],
        unsuccessfulPairs: const [],
        diagnostics: ForwardFinalizationDiagnostics(
          eligibleEdgeCount: 0,
          rootlessEdgeCount: 0,
          integrityFailedCommitters: const [],
          budgetBySender: const {},
          observedPairCount: 0,
          unsuccessfulPairCount: 0,
        ),
      );
    }

    final builder = ForwardCausalGraphBuilder();
    final propagator = ForwardMassPropagator();
    final normalizer = ForwardLocalNormalizer();
    final consolidator = ForwardRequestConsolidator();

    final buildStats = ForwardCausalBuildStats();
    final integrityFailed = <String>[];
    final perCommitmentShares =
        <
          (
            TrustBin bin,
            ForwardOutcomeProvenance provenance,
            Map<ForwardPair, double> sharesByPair,
          )
        >[];
    final observedPairs = <ForwardPair>{};
    var eligibleEdgeCount = 0;

    for (final entry in authorEvaluationByCommitter.entries) {
      final committerId = entry.key;
      final outcome = mapAuthorEvaluationToForwardOutcome(entry.value);
      if (outcome == null) continue;

      final commitmentAt =
          commitmentAtByCommitter[committerId] ?? finalizedAt;
      EligibleForwardDag? dag;
      try {
        dag = builder.build(
          authorId: authorId,
          committerId: committerId,
          commitmentAt: commitmentAt,
          allEdges: allEdges,
          stats: buildStats,
        );
      } on ForwardGraphIntegrityException {
        integrityFailed.add(committerId);
        continue;
      }
      if (dag == null) continue;
      eligibleEdgeCount += dag.edges.length;

      final raw = propagator.propagate(
        dag: dag,
        attributionsByBatchId: attributionsByBatchId,
      );
      final shares = normalizer.normalize(raw);
      perCommitmentShares.add((
        outcome.forwardBin,
        outcome.provenance,
        shares,
      ));
      observedPairs.addAll(shares.keys);
    }

    final support = consolidator.accumulate(perCommitmentShares);
    final deltas = consolidator.normalizePerSender(support);

    final propagated = <EvaluatedOutcomeEvidence>[];
    final budgetBySender = <String, double>{};
    for (final entry in deltas.entries) {
      final (sender, recipient, bin, provenance) = entry.key;
      final count = entry.value;
      if (count <= 0) continue;
      budgetBySender[sender] =
          (budgetBySender[sender] ?? 0) + count;
      propagated.add(
        EvaluatedOutcomeEvidence(
          senderId: sender,
          recipientId: recipient,
          bin: bin,
          count: count,
          sourceType: provenance == ForwardOutcomeProvenance.evaluated
              ? TrustSourceType.propagatedAuthorEvaluatedCommitment
              : TrustSourceType.negativeCommitmentRouteNoEffect,
          provenance: provenance,
        ),
      );
    }

    final eligiblePairs = _eligibleAuthorPairs(
      authorId: authorId,
      finalizedAt: finalizedAt,
      allEdges: allEdges,
      minOpportunity: minOpportunity,
    );
    final unsuccessful = eligiblePairs
        .where((p) => !observedPairs.contains(p))
        .toList();

    return ForwardOutcomeResult(
      propagatedOutcomes: propagated,
      unsuccessfulPairs: unsuccessful,
      diagnostics: ForwardFinalizationDiagnostics(
        eligibleEdgeCount: eligibleEdgeCount,
        rootlessEdgeCount: buildStats.rootlessEdgeCount,
        integrityFailedCommitters: integrityFailed,
        budgetBySender: budgetBySender,
        observedPairCount: observedPairs.length,
        unsuccessfulPairCount: unsuccessful.length,
      ),
    );
  }

  Set<ForwardPair> _eligibleAuthorPairs({
    required String authorId,
    required DateTime finalizedAt,
    required List<ForwardProvenanceEdge> allEdges,
    required Duration minOpportunity,
  }) {
    final pairs = <ForwardPair>{};
    for (final e in allEdges) {
      if (e.senderId != authorId && e.parentEdgeId != null) continue;
      if (!e.createdAt.isBefore(finalizedAt)) continue;
      if (e.cancelledAt != null && e.cancelledAt!.isBefore(finalizedAt)) {
        continue;
      }
      if (finalizedAt.difference(e.createdAt) < minOpportunity) continue;
      if (e.parentEdgeId == null && e.senderId != authorId) continue;
      pairs.add((e.senderId, e.recipientId));
    }
    return pairs;
  }
}
