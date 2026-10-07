import 'package:flutter_test/flutter_test.dart';

import 'package:tentura/data/service/clock_service.dart';
import 'package:tentura/domain/port/clock_port.dart';

void main() {
  group('ClockService', () {
    test('is a ClockPort', () {
      expect(ClockService(), isA<ClockPort>());
    });

    test('reports the current wall-clock time', () {
      final before = DateTime.now();
      final reported = ClockService().now();
      final after = DateTime.now();

      expect(reported.isBefore(before), isFalse);
      expect(reported.isAfter(after), isFalse);
    });

    test('reads the clock on every call', () async {
      final clock = ClockService();
      final first = clock.now();
      await Future<void>.delayed(const Duration(milliseconds: 5));

      expect(clock.now().isAfter(first), isTrue);
    });
  });
}
