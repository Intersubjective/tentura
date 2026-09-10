import 'package:injectable/injectable.dart';

import 'package:tentura_server/domain/port/attention_system_settlement_port.dart';

import '_use_case_base.dart';

/// Idempotent sweep for review windows closed before obligation settlement shipped.
@Singleton(order: 2)
final class ReviewObligationBackfillCase extends UseCaseBase {
  ReviewObligationBackfillCase(
    this._systemSettlement, {
    required super.env,
    required super.logger,
  });

  final AttentionSystemSettlementPort _systemSettlement;

  /// Returns total notification_outbox rows updated across all closed windows.
  Future<int> run() async {
    final beaconIds =
        await _systemSettlement.listBeaconIdsWithClosedReviewWindows();
    var total = 0;
    for (final beaconId in beaconIds) {
      total += await _systemSettlement.settleReviewObligationsAfterWindowClose(
        beaconId,
      );
    }
    return total;
  }
}
