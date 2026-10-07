// fake_async ships with flutter_test; same import as the sibling tests.
// ignore: depend_on_referenced_packages
import 'package:fake_async/fake_async.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:tentura/data/service/wake_up_service.dart';
import 'package:tentura/domain/port/wake_up_port.dart';

void main() {
  group('WakeUpService', () {
    test('is a WakeUpPort', () {
      expect(WakeUpService(), isA<WakeUpPort>());
    });

    test('runs the callback once after the delay', () {
      fakeAsync((async) {
        var calls = 0;
        final handle = WakeUpService().schedule(
          const Duration(seconds: 1),
          () => calls++,
        );

        async.elapse(const Duration(milliseconds: 999));
        expect(calls, 0);
        expect(handle.isActive, isTrue);

        async.elapse(const Duration(milliseconds: 1));
        expect(calls, 1);
        expect(handle.isActive, isFalse);

        async.elapse(const Duration(seconds: 10));
        expect(calls, 1);
      });
    });

    test('cancelled wake-up never runs its callback', () {
      fakeAsync((async) {
        var calls = 0;
        final handle = WakeUpService().schedule(
          const Duration(seconds: 1),
          () => calls++,
        )..cancel();

        async.elapse(const Duration(seconds: 5));

        expect(calls, 0);
        expect(handle.isActive, isFalse);
      });
    });

    test('keeps independent wake-ups independent', () {
      fakeAsync((async) {
        final fired = <String>[];
        WakeUpService()
          ..schedule(const Duration(seconds: 2), () => fired.add('b'))
          ..schedule(const Duration(seconds: 1), () => fired.add('a'))
          ..schedule(const Duration(seconds: 1), () => fired.add('x')).cancel();

        async.elapse(const Duration(seconds: 2));

        expect(fired, ['a', 'b']);
      });
    });
  });
}
