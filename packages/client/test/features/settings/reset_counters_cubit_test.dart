import 'dart:async';

import 'package:flutter_test/flutter_test.dart';

import 'package:tentura/domain/attention/port/attention_reconcile_port.dart';
import 'package:tentura/domain/attention/entity/attention_clear.dart';
import 'package:tentura/domain/attention/entity/attention_summary.dart';
import 'package:tentura/features/settings/ui/bloc/reset_counters_cubit.dart';

/// D15 — Reset counters runs a repair, reports progress, never claims the
/// user has no work, and fails out loud.
void main() {
  test('a run reports progress and then success', () async {
    final attention = _FakeReconcile();
    final cubit = ResetCountersCubit(attention: attention);
    addTearDown(cubit.close);

    final states = <ResetCountersState>[];
    final sub = cubit.stream.listen(states.add);
    addTearDown(sub.cancel);

    final run = cubit.resetCounters();
    await Future<void>.delayed(Duration.zero);
    expect(
      cubit.state.isRunning,
      isTrue,
      reason: 'the user sees the repair is running before it answers',
    );

    attention.pending.first.complete(_result());
    await run;
    // The cubit's own stream delivers asynchronously; the assertion below is
    // about what the UI got to see, so let it arrive.
    await Future<void>.delayed(Duration.zero);

    expect(cubit.state.isRunning, isFalse);
    expect(cubit.state.outcome, ResetCountersOutcome.refreshed);
    expect(
      states.map((s) => s.isRunning),
      containsAllInOrder([true, false]),
      reason: 'progress is a state the UI can observe, not an instant flip',
    );
  });

  test(
    'a result that still carries work is a success, not a failure',
    () async {
      // D15: "A correct result may still contain dots and counts." Reporting
      // a non-zero repair as failure — or as "all caught up" — are the two
      // ways this copy rule gets broken.
      final attention = _FakeReconcile();
      final cubit = ResetCountersCubit(attention: attention);
      addTearDown(cubit.close);

      final run = cubit.resetCounters();
      await Future<void>.delayed(Duration.zero);
      attention.pending.first.complete(
        _result(
          createdObligationCount: 3,
          unrepairableObligationCount: 2,
          needsYouTotal: 5,
          myDeskDot: true,
        ),
      );
      await run;

      expect(
        cubit.state.outcome,
        ResetCountersOutcome.refreshed,
        reason: 'work remaining is what the account owes, not a failed repair',
      );
    },
  );

  test('a failed repair says so instead of reporting success', () async {
    final attention = _FakeReconcile();
    final cubit = ResetCountersCubit(attention: attention);
    addTearDown(cubit.close);

    final run = cubit.resetCounters();
    await Future<void>.delayed(Duration.zero);
    attention.pending.first.completeError(StateError('offline'));
    await run;

    expect(cubit.state.outcome, ResetCountersOutcome.failed);
    expect(cubit.state.isRunning, isFalse);
  });

  test('a second tap while one run is in flight starts nothing', () async {
    final attention = _FakeReconcile();
    final cubit = ResetCountersCubit(attention: attention);
    addTearDown(cubit.close);

    final first = cubit.resetCounters();
    await Future<void>.delayed(Duration.zero);
    final second = cubit.resetCounters();
    await Future<void>.delayed(Duration.zero);

    expect(
      attention.calls,
      1,
      reason: 'a double tap must not fire a second repair',
    );

    attention.pending.first.complete(_result());
    await Future.wait([first, second]);
    expect(attention.calls, 1);
  });

  test('each outcome is observable even when it repeats', () async {
    // The surface shows the result once per run. Two identical outcomes in a
    // row are two events, so a listener keyed on the state alone would miss
    // the second — and the user would tap and see nothing.
    final attention = _FakeReconcile();
    final cubit = ResetCountersCubit(attention: attention);
    addTearDown(cubit.close);

    final first = cubit.resetCounters();
    await Future<void>.delayed(Duration.zero);
    attention.pending.removeAt(0).complete(_result());
    await first;
    final firstSerial = cubit.state.outcomeSerial;

    final second = cubit.resetCounters();
    await Future<void>.delayed(Duration.zero);
    attention.pending.removeAt(0).complete(_result());
    await second;

    expect(cubit.state.outcome, ResetCountersOutcome.refreshed);
    expect(cubit.state.outcomeSerial, greaterThan(firstSerial));
  });
}

AttentionReconcileResult _result({
  int createdObligationCount = 0,
  int unrepairableObligationCount = 0,
  int needsYouTotal = 0,
  bool myDeskDot = false,
}) => AttentionReconcileResult(
  summary: AttentionSurfaceSummary(
    activityUnreadTotal: 0,
    myWorkUnreadTotal: 0,
    needsYouTotal: needsYouTotal,
    myDeskDot: myDeskDot,
  ),
  createdObligationCount: createdObligationCount,
  unrepairableObligationCount: unrepairableObligationCount,
);

final class _FakeReconcile implements AttentionReconcilePort {
  final List<Completer<AttentionReconcileResult>> pending = [];
  int calls = 0;

  @override
  Future<AttentionReconcileResult> reconcile() {
    calls++;
    final completer = Completer<AttentionReconcileResult>();
    pending.add(completer);
    return completer.future;
  }
}
