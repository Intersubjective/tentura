import 'package:injectable/injectable.dart';
import 'package:tentura_server/domain/attention/attention_models.dart';
import 'package:tentura_server/domain/port/attention_settlement_port.dart';

import '_use_case_base.dart';

/// Settles an authorized recipient's live obligation without changing read state.
@Singleton(order: 2)
final class AttentionSettlementCase extends UseCaseBase {
  AttentionSettlementCase(
    this._settlements, {
    required super.env,
    required super.logger,
  });

  final AttentionSettlementPort _settlements;

  Future<int> settle({
    required String accountId,
    required String receiptId,
    required AttentionSettlementKind kind,
  }) async {
    if (receiptId.trim().isEmpty || receiptId.length > 256) {
      throw ArgumentError.value(receiptId, 'receiptId', 'must be a receipt id');
    }
    if (kind != AttentionSettlementKind.resolved &&
        kind != AttentionSettlementKind.dismissed) {
      throw ArgumentError.value(kind, 'kind', 'must be user-settleable');
    }
    final eventType = await _settlements.liveObligationEventType(
      accountId: accountId,
      receiptId: receiptId,
    );
    // D04 / §5, owner decision C (U07b2): nothing in the product can be
    // honestly resolved by acknowledgment, so *no* obligation kind ends
    // through this generic path — each one ends through its own domain
    // transition (answer the offer, send the package, window close).
    // `liveObligationEventType` only ever names a receipt that still
    // `requires_action`, so a non-null answer here is by definition a live
    // obligation, whatever kind it is.
    if (eventType != null) {
      throw ArgumentError.value(
        receiptId,
        'receiptId',
        '$eventType obligations are not user-settleable; '
            'they end through their own domain transition',
      );
    }
    return _settlements.settle(
      accountId: accountId,
      receiptId: receiptId,
      kind: kind,
    );
  }
}
