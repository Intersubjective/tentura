import 'package:fake_async/fake_async.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:tentura/domain/util/burst_coalescer.dart';

/// Default [Future.timeout] for refresh work scheduled through [BurstCoalescer].
Duration get burstCoalescerSettleTimeout =>
    BurstCoalescer.window + const Duration(milliseconds: 500);

/// Advances fake time through one coalesced hint batch and drains callbacks.
void elapseAfterHintBurst(FakeAsync async) {
  async
    ..elapse(BurstCoalescer.window)
    ..flushMicrotasks();
}

/// Delivers async invalidation stream events to listeners.
Future<void> pumpHintDelivery() async {
  await Future<void>.delayed(Duration.zero);
  await Future<void>.delayed(Duration.zero);
}

/// Waits for one [BurstCoalescer] batch to flush and refresh work to start.
Future<void> pumpCoalescedHintRefresh({int times = 30}) =>
    pumpAfterHintBurst(times: times);

/// Wall-clock counterpart for cubit/unit tests outside [fakeAsync].
///
/// Drains hint delivery first so the coalescer's window timer is scheduled
/// before this wait's equal-length timer, and therefore fires first.
Future<void> pumpAfterHintBurst({int times = 30}) async {
  await pumpEventQueue(times: times);
  await Future<void>.delayed(BurstCoalescer.window);
  await pumpEventQueue(times: times);
}
