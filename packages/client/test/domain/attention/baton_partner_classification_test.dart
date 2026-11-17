import 'package:flutter_test/flutter_test.dart';
import 'package:tentura/domain/attention/attention_event_classification.dart';

void main() {
  for (final type in ['batonPartnerAsked', 'batonPartnerAnswered']) {
    test('$type renders with the Request headline and may be coalesced', () {
      final c = attentionEventClassifications[type];
      expect(c, isNotNull);
      expect(c!.headlineTreatment, AttentionHeadlineTreatment.beacon);
      expect(c.coalescible, isTrue);
    });
  }
}
