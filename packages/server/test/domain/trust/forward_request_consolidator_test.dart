import 'package:test/test.dart';

import 'package:tentura_server/domain/trust/forward/forward_mass_propagator.dart';
import 'package:tentura_server/domain/trust/forward/forward_outcome_policy.dart';
import 'package:tentura_server/domain/trust/forward/forward_request_consolidator.dart';
import 'package:tentura_server/domain/trust/trust_bin.dart';

void main() {
  final consolidator = ForwardRequestConsolidator();

  test('accumulates per-cell support without collapsing bins', () {
    final support = consolidator.accumulate([
      (
        TrustBin.good,
        ForwardOutcomeProvenance.evaluated,
        {('A', 'B'): 0.5, ('A', 'C'): 0.5},
      ),
      (
        TrustBin.veryGood,
        ForwardOutcomeProvenance.evaluated,
        {('A', 'B'): 1.0},
      ),
    ]);
    expect(support[('A', 'B', TrustBin.good, ForwardOutcomeProvenance.evaluated)], 0.5);
    expect(
      support[('A', 'B', TrustBin.veryGood, ForwardOutcomeProvenance.evaluated)],
      1.0,
    );
  });

  test('provenance separation keeps evaluated and negativeRoute cells', () {
    final support = consolidator.accumulate([
      (
        TrustBin.noEffect,
        ForwardOutcomeProvenance.evaluated,
        {('A', 'B'): 1.0},
      ),
      (
        TrustBin.noEffect,
        ForwardOutcomeProvenance.negativeRoute,
        {('A', 'B'): 1.0},
      ),
    ]);
    expect(
      support[('A', 'B', TrustBin.noEffect, ForwardOutcomeProvenance.evaluated)],
      1.0,
    );
    expect(
      support[('A', 'B', TrustBin.noEffect, ForwardOutcomeProvenance.negativeRoute)],
      1.0,
    );
  });

  test('normalizePerSender budgets sum to 1 per sender', () {
    final support = {
      ('A', 'B', TrustBin.good, ForwardOutcomeProvenance.evaluated): 1.0,
      ('A', 'C', TrustBin.good, ForwardOutcomeProvenance.evaluated): 1.0,
    };
    final deltas = consolidator.normalizePerSender(support);
    final total = deltas.values.fold<double>(0, (a, b) => a + b);
    expect(total, closeTo(1.0, 1e-9));
  });

  test('Z = 0 yields empty deltas', () {
    expect(consolidator.normalizePerSender({}), isEmpty);
  });
}
