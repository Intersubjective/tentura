import 'package:logging/logging.dart';
import 'package:test/test.dart';

import 'package:tentura_server/domain/port/attention_capture_settlement_port.dart';
import 'package:tentura_server/domain/use_case/attention_capture_settlement_case.dart';
import 'package:tentura_server/env.dart';

void main() {
  test('runDue settles abandoned captures with the stale/expire horizons', () {
    final port = _RecordingPort(settled: 3);
    final job = AttentionCaptureSettlementCase(
      port,
      env: Env.test(),
      logger: Logger('attention_capture_settlement_case_test'),
    );

    return job.runDue().then((settled) {
      expect(settled, 3);
      expect(port.calls, [
        (
          staleAfter: const Duration(minutes: 10),
          expireAfter: const Duration(days: 1),
        ),
      ]);
    });
  });
}

class _RecordingPort implements AttentionCaptureSettlementPort {
  _RecordingPort({required this.settled});

  final int settled;
  final calls = <({Duration staleAfter, Duration expireAfter})>[];

  @override
  Future<int> settleAbandonedCaptures({
    required Duration staleAfter,
    required Duration expireAfter,
  }) async {
    calls.add((staleAfter: staleAfter, expireAfter: expireAfter));
    return settled;
  }
}
