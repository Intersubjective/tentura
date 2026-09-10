import 'package:test/test.dart';

import 'package:tentura_server/domain/attention/attention_models.dart';

void main() {
  group('AttentionSettlementKind wire names', () {
    test('round-trips every known kind', () {
      for (final kind in AttentionSettlementKind.values) {
        expect(attentionSettlementKindFromWireName(kind.wireName), kind);
      }
    });

    test('expired round-trips explicitly', () {
      expect(
        attentionSettlementKindFromWireName('expired'),
        AttentionSettlementKind.expired,
      );
      expect(AttentionSettlementKind.expired.wireName, 'expired');
    });

    test('unknown wire name throws StateError', () {
      expect(
        () => attentionSettlementKindFromWireName('unknown'),
        throwsA(isA<StateError>()),
      );
    });
  });
}
