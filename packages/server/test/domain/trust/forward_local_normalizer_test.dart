import 'package:test/test.dart';

import 'package:tentura_server/domain/trust/forward/forward_local_normalizer.dart';
import 'package:tentura_server/domain/trust/forward/forward_mass_propagator.dart';

void main() {
  test('per-sender shares sum to 1', () {
    final raw = <ForwardPair, double>{
      ('A', 'B'): 0.25,
      ('A', 'C'): 0.75,
      ('B', 'D'): 0.4,
      ('B', 'E'): 0.6,
    };
    final shares = ForwardLocalNormalizer().normalize(raw);
    expect(
      shares[('A', 'B')]! + shares[('A', 'C')]!,
      closeTo(1.0, 1e-9),
    );
    expect(
      shares[('B', 'D')]! + shares[('B', 'E')]!,
      closeTo(1.0, 1e-9),
    );
  });

  test('zero-sum sender is omitted', () {
    final shares = ForwardLocalNormalizer().normalize({
      ('A', 'B'): 0,
    });
    expect(shares, isEmpty);
  });
}
