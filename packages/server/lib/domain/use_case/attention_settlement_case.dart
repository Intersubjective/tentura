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
  }) {
    if (receiptId.trim().isEmpty || receiptId.length > 256) {
      throw ArgumentError.value(receiptId, 'receiptId', 'must be a receipt id');
    }
    if (kind != AttentionSettlementKind.resolved &&
        kind != AttentionSettlementKind.dismissed) {
      throw ArgumentError.value(kind, 'kind', 'must be user-settleable');
    }
    return _settlements.settle(
      accountId: accountId,
      receiptId: receiptId,
      kind: kind,
    );
  }
}
