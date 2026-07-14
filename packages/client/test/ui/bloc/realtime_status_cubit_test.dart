import 'package:flutter_test/flutter_test.dart';

import 'package:tentura/domain/entity/realtime/realtime_connection_status.dart';
import 'package:tentura/ui/bloc/realtime_status_cubit.dart';

import '../../support/test_realtime_sync.dart';

const _pausedDelay = Duration(milliseconds: 30);

Future<void> _waitFor(bool Function() condition) async {
  final deadline = DateTime.now().add(const Duration(seconds: 1));
  while (DateTime.now().isBefore(deadline)) {
    if (condition()) return;
    await Future<void>.delayed(const Duration(milliseconds: 5));
  }
  fail('Timed out waiting for realtime status transition.');
}

void main() {
  test('brief reconnect stays quiet', () async {
    final realtime = buildTestRealtimeSync();
    final cubit = RealtimeStatusCubit.forTesting(
      realtime.case_,
      pausedDelay: _pausedDelay,
    );

    realtime.port.emitStatus(_status(RealtimeConnectionPhase.disconnected));
    await Future<void>.delayed(const Duration(milliseconds: 10));
    realtime.port.emitStatus(_status(RealtimeConnectionPhase.authenticated));
    await Future<void>.delayed(_pausedDelay);

    expect(cubit.state.showPausedBanner, isFalse);
    await cubit.close();
    await realtime.port.dispose();
  });

  test('sustained outage shows banner and authentication hides it', () async {
    final realtime = buildTestRealtimeSync();
    final cubit = RealtimeStatusCubit.forTesting(
      realtime.case_,
      pausedDelay: _pausedDelay,
    );

    realtime.port.emitStatus(_status(RealtimeConnectionPhase.disconnected));
    await _waitFor(() => cubit.state.showPausedBanner);

    expect(cubit.state.showPausedBanner, isTrue);

    realtime.port.emitStatus(_status(RealtimeConnectionPhase.authenticated));
    await _waitFor(
      () => cubit.state.phase == RealtimeConnectionPhase.authenticated,
    );

    expect(cubit.state.showPausedBanner, isFalse);
    await cubit.close();
    await realtime.port.dispose();
  });

  test('unbound and accountless states never show outage UI', () async {
    final realtime = buildTestRealtimeSync();
    final cubit = RealtimeStatusCubit.forTesting(
      realtime.case_,
      pausedDelay: _pausedDelay,
    );

    realtime.port.emitStatus(
      const RealtimeConnectionStatus(
        connectionEpoch: 1,
        phase: RealtimeConnectionPhase.disconnected,
      ),
    );
    await Future<void>.delayed(_pausedDelay * 2);

    expect(cubit.state.showPausedBanner, isFalse);
    await cubit.close();
    await realtime.port.dispose();
  });
}

RealtimeConnectionStatus _status(RealtimeConnectionPhase phase) =>
    RealtimeConnectionStatus(
      connectionEpoch: 1,
      phase: phase,
      accountId: 'U-me',
    );
