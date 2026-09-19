import 'package:injectable/injectable.dart';

import 'package:tentura_server/domain/attention/attention_clear_models.dart';
import 'package:tentura_server/domain/port/attention_clear_port.dart';

/// U08 — issue a capture, then apply it.
///
/// The case owns the token: encoding it at capture, decoding and *binding* it
/// at apply. Binding is two checks — the account inside the token must be the
/// caller, and (for a Request-scoped token) the beacon inside it is the only
/// scope the apply may touch. Everything else is re-authorized in the
/// repository against the same wall every other attention read uses.
@injectable
class AttentionClearCase {
  const AttentionClearCase(this._clear);

  final AttentionClearPort _clear;

  Future<AttentionClearSnapshot> captureSnapshot({
    required String accountId,
    required AttentionClearCaptureKind kind,
    String? beaconId,
    String? receiptId,
  }) async {
    if (beaconId == null && receiptId == null) {
      throw ArgumentError(
        'a clear snapshot must be scoped to a Request or to one receipt',
      );
    }
    final capture = await _clear.captureEligible(
      accountId: accountId,
      beaconId: beaconId,
      receiptId: receiptId,
    );
    return AttentionClearSnapshot(
      token: AttentionClearSnapshotToken(
        accountId: accountId,
        beaconId: beaconId,
        kind: kind,
        outcomeGeneration: capture.outcomeGeneration,
        decisionRevision: capture.decisionRevision,
        receiptIds: capture.receiptIds,
      ).encode(),
      receiptIds: capture.receiptIds,
      beaconId: beaconId,
      kind: kind,
      outcomeGeneration: capture.outcomeGeneration,
      decisionRevision: capture.decisionRevision,
    );
  }

  Future<AttentionClearResult> clear({
    required String accountId,
    required String operationId,
    required String snapshotToken,
  }) async {
    if (operationId.isEmpty || operationId.length > 64) {
      throw ArgumentError.value(
        operationId,
        'operationId',
        'must be 1..64 characters',
      );
    }
    final token = AttentionClearSnapshotToken.decode(snapshotToken);
    if (token.accountId != accountId) {
      // Somebody else's token. Refuse the whole thing, without touching
      // storage and without saying whether any of those receipts exist.
      return AttentionClearResult(
        operationId: operationId,
        appliedReceiptIds: const [],
        skippedReceiptIds: const [],
        deniedReceiptIds: [...token.receiptIds]..sort(),
        status: AttentionClearStatus.denied,
      );
    }
    return _clear.apply(
      accountId: accountId,
      operationId: operationId,
      beaconId: token.beaconId,
      kind: token.kind,
      outcomeGeneration: token.outcomeGeneration,
      receiptIds: token.receiptIds,
    );
  }
}
