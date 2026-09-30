import 'package:test/test.dart';

import 'package:tentura_server/domain/trust/forward/forward_request_consolidator.dart';

void main() {
  final consolidator = ForwardRequestConsolidator();

  test('accumulates support keyed by (sender, recipient) only', () {
    final support = consolidator.accumulate([
      {('A', 'B'): 0.5, ('A', 'C'): 0.5},
      {('A', 'B'): 1.0},
    ]);
    expect(support.keys.toSet(), {('A', 'B'), ('A', 'C')});
    expect(support[('A', 'B')], 1.5);
    expect(support[('A', 'C')], 0.5);
  });

  test('normalizePerSender spends the given budget per sender', () {
    final deltas = consolidator.normalizePerSender(
      {('A', 'B'): 1.0, ('A', 'C'): 3.0, ('B', 'C'): 2.0},
      budget: 0.3,
    );
    expect(deltas[('A', 'B')], closeTo(0.075, 1e-9));
    expect(deltas[('A', 'C')], closeTo(0.225, 1e-9));
    expect(deltas[('B', 'C')], closeTo(0.3, 1e-9));
  });

  test('Z = 0 yields empty deltas', () {
    expect(consolidator.normalizePerSender({}, budget: 0.3), isEmpty);
  });
}
