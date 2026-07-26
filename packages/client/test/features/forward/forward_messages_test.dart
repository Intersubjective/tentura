import 'package:flutter_test/flutter_test.dart';

import 'package:tentura/features/forward/ui/message/forward_messages.dart';

void main() {
  group('ForwardSentMessage', () {
    test('single recipient copy', () {
      const message = ForwardSentMessage(1);
      expect(message.toEn, 'Request forwarded to 1 person');
      expect(message.toRu, 'Запрос переслан: 1 человеку');
    });

    test('multiple recipients copy', () {
      const message = ForwardSentMessage(3);
      expect(message.toEn, 'Request forwarded to 3 people');
      expect(message.toRu, 'Запрос переслан: 3 людям');
    });
  });
}
