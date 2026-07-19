import 'package:test/test.dart';

import 'package:tentura_server/domain/trust/forward/forward_outcome_finalizer.dart';
import 'package:tentura_server/domain/trust/forward/forward_outcome_policy.dart';
import 'package:tentura_server/domain/trust/forward/forward_provenance.dart';
import 'package:tentura_server/domain/trust/trust_bin.dart';
import 'package:tentura_server/domain/trust/trust_source_type.dart';

void main() {
  ForwardProvenanceEdge edge({
    required String id,
    required String sender,
    required String recipient,
    String? parent,
  }) =>
      ForwardProvenanceEdge(
        id: id,
        senderId: sender,
        recipientId: recipient,
        createdAt: DateTime.utc(2026, 1, int.parse(id)),
        parentEdgeId: parent,
        batchId: 'B$id',
      );

  final author = 'A';
  final committer = 'D';
  final finalizedAt = DateTime.utc(2026, 1, 20);
  final commitmentAt = DateTime.utc(2026, 1, 10);
  const minOpportunity = Duration(hours: 24);

  List<ForwardProvenanceEdge> chainEdges() => [
    edge(id: '1', sender: 'A', recipient: 'B'),
    edge(id: '2', sender: 'B', recipient: 'C', parent: '1'),
    edge(id: '3', sender: 'C', recipient: 'D', parent: '2'),
  ];

  ForwardOutcomeResult finalize({
    required Map<String, int> evaluations,
    List<ForwardProvenanceEdge>? edges,
  }) =>
      ForwardOutcomeFinalizer().compute(
        authorId: author,
        finalizedAt: finalizedAt,
        authorEvaluationByCommitter: evaluations,
        commitmentAtByCommitter: {committer: commitmentAt},
        allEdges: edges ?? chainEdges(),
        attributionsByBatchId: const {},
        minOpportunity: minOpportunity,
        unsuccessfulCount: 1,
      );

  test('noBasis-only evaluations yield empty forward result', () {
    final result = finalize(evaluations: {committer: 0});
    expect(result.propagatedOutcomes, isEmpty);
    expect(result.unsuccessfulPairs, isEmpty);
  });

  test('negative evaluation emits negativeRoute no_effect on observed path', () {
    final result = finalize(evaluations: {committer: 2});
    expect(result.propagatedOutcomes, isNotEmpty);
    for (final o in result.propagatedOutcomes) {
      expect(o.bin, TrustBin.noEffect);
      expect(o.sourceType, TrustSourceType.negativeCommitmentRouteNoEffect);
      expect(o.provenance, ForwardOutcomeProvenance.negativeRoute);
    }
    expect(result.diagnostics.observedPairCount, greaterThan(0));
  });

  test('positive evaluation preserves evaluated bins', () {
    final result = finalize(evaluations: {committer: 5});
    expect(
      result.propagatedOutcomes.any((o) => o.bin == TrustBin.veryGood),
      isTrue,
    );
    expect(
      result.propagatedOutcomes.every(
        (o) =>
            o.sourceType == TrustSourceType.propagatedAuthorEvaluatedCommitment,
      ),
      isTrue,
    );
  });

  test('observed pairs are excluded from unsuccessful set', () {
    final result = finalize(evaluations: {committer: 4});
    for (final pair in result.unsuccessfulPairs) {
      expect(
        result.propagatedOutcomes.any(
          (o) => o.senderId == pair.$1 && o.recipientId == pair.$2,
        ),
        isFalse,
      );
    }
  });

  test('per-sender budget sums to 1', () {
    final result = finalize(evaluations: {committer: 4});
    for (final total in result.diagnostics.budgetBySender.values) {
      expect(total, closeTo(1.0, 1e-6));
    }
  });

  test('§3 mapping table values 1-5', () {
    const expectedBins = {
      1: TrustBin.noEffect,
      2: TrustBin.noEffect,
      3: TrustBin.noEffect,
      4: TrustBin.good,
      5: TrustBin.veryGood,
    };
    for (final entry in expectedBins.entries) {
      final outcome = mapAuthorEvaluationToForwardOutcome(entry.key)!;
      expect(outcome.forwardBin, entry.value);
    }
  });
}
