import 'package:flutter_test/flutter_test.dart';

import 'fake_clock_port.dart';
import 'fake_wake_up_port.dart';

void main() {
  group('FakeClockPort', () {
    test('only moves when advanced', () {
      final clock = FakeClockPort(DateTime.utc(2026, 5));

      expect(clock.now(), DateTime.utc(2026, 5));
      clock.advance(const Duration(seconds: 30));

      expect(clock.now(), DateTime.utc(2026, 5, 1, 0, 0, 30));
    });
  });

  group('FakeWakeUpPort', () {
    test('fires due wake-ups in due order and skips cancelled ones', () {
      final wakeUps = FakeWakeUpPort();
      final fired = <String>[];
      wakeUps
        ..schedule(const Duration(seconds: 2), () => fired.add('late'))
        ..schedule(const Duration(seconds: 1), () => fired.add('early'))
        ..schedule(
          const Duration(seconds: 1),
          () => fired.add('dropped'),
        ).cancel()
        ..elapse(const Duration(milliseconds: 999));
      expect(fired, isEmpty);

      wakeUps.elapse(const Duration(seconds: 2));
      expect(fired, ['early', 'late']);
      expect(wakeUps.pendingCount, 0);
    });
  });
}
