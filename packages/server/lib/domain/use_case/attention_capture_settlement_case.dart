import 'package:injectable/injectable.dart';

import 'package:tentura_server/domain/port/attention_capture_settlement_port.dart';
import 'package:tentura_server/domain/use_case/_use_case_base.dart';

/// Settles "Dismiss all" captures whose caller went away mid-capture: resumed
/// once stale, expired once abandoned for a day. Runs from the task worker.
@Singleton(order: 2)
final class AttentionCaptureSettlementCase extends UseCaseBase {
  AttentionCaptureSettlementCase(
    this._port, {
    required super.env,
    required super.logger,
  });

  static const staleAfter = Duration(minutes: 10);
  static const expireAfter = Duration(days: 1);

  final AttentionCaptureSettlementPort _port;

  Future<int> runDue() => _port.settleAbandonedCaptures(
    staleAfter: staleAfter,
    expireAfter: expireAfter,
  );
}
