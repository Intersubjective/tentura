import 'package:injectable/injectable.dart';

import 'package:tentura_server/domain/attention/attention_sweep_models.dart';
import 'package:tentura_server/domain/port/attention_sweep_port.dart';

/// U09b — *Dismiss all*.
///
/// There is no token to bind here, which is the point: the membership of a
/// sweep is never supplied by the caller. The account is the caller's JWT
/// subject and everything else is decided server-side against
/// `AttentionDismissibleSql`, so the only thing a client can influence is
/// *which operation* it is resuming.
@injectable
class AttentionSweepCase {
  const AttentionSweepCase(this._sweep);

  final AttentionSweepPort _sweep;

  Future<AttentionSweepResult> dismissAll({
    required String accountId,
    required String operationId,
    int? batchSize,
    int? maxBatches,
  }) {
    if (operationId.isEmpty || operationId.length > 64) {
      throw ArgumentError.value(
        operationId,
        'operationId',
        'must be 1..64 characters',
      );
    }
    if (maxBatches != null && maxBatches < 1) {
      throw ArgumentError.value(maxBatches, 'maxBatches', 'must be at least 1');
    }
    return _sweep.dismissAll(
      accountId: accountId,
      operationId: operationId,
      batchSize: batchSize ?? AttentionSweepLimits.batchSize,
      maxBatches: maxBatches,
    );
  }
}
