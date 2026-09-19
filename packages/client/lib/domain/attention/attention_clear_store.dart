import 'entity/attention_clear.dart';
import 'entity/attention_receipt.dart';

/// Local clear intent, kept per operation until the server confirms it.
///
/// Clearing is a **different axis** from reading, so this store is separate
/// from [AttentionAckStore] rather than an extra intent on it (§3 product
/// contract).
///
/// Two rules give D14 its teeth:
///
/// * membership is owned by an operation, so a rollback can only ever undo
///   the optimism of *that* operation — never another device's, never another
///   gesture's;
/// * rolling back removes the **overlay**, never the receipt's own
///   `clearedAt`. A row the server has already cleared therefore stays
///   cleared when our own optimism is withdrawn.
final class AttentionClearStore {
  String _accountId = '';
  final Map<String, _PendingClear> _byOperation = {};

  void resetForAccount(String accountId) {
    if (_accountId == accountId) return;
    _accountId = accountId;
    _byOperation.clear();
  }

  /// Registers the membership [receiptIds] optimism covers for [operationId].
  void begin(String operationId, Iterable<String> receiptIds) {
    _byOperation[operationId] = _PendingClear(
      memberIds: receiptIds.toSet(),
      committedIds: <String>{},
    );
  }

  Set<String> membersOf(String operationId) =>
      _byOperation[operationId]?.memberIds ?? const {};

  /// Marks the members the server actually applied. Everything else in the
  /// operation is dropped: a `partial` answer must never commit a skipped
  /// member.
  void commit(String operationId, Iterable<String> appliedIds) {
    final pending = _byOperation[operationId];
    if (pending == null) return;
    final applied = appliedIds.toSet().intersection(pending.memberIds);
    pending.memberIds
      ..clear()
      ..addAll(applied);
    pending.committedIds
      ..clear()
      ..addAll(applied);
    if (pending.memberIds.isEmpty) _byOperation.remove(operationId);
  }

  /// Withdraws optimism for [receiptIds] within [operationId] only.
  void rollback(String operationId, Iterable<String> receiptIds) {
    final pending = _byOperation[operationId];
    if (pending == null) return;
    for (final id in receiptIds) {
      pending.memberIds.remove(id);
      pending.committedIds.remove(id);
    }
    if (pending.memberIds.isEmpty) _byOperation.remove(operationId);
  }

  void discard(String operationId) => _byOperation.remove(operationId);

  bool isOptimisticallyCleared(String id) =>
      _byOperation.values.any((pending) => pending.memberIds.contains(id));

  /// Stamps the overlay onto [receipt], and drops a committed overlay once the
  /// server's own `clearedAt` has caught up with it.
  AttentionReceipt apply(AttentionReceipt receipt) {
    var covered = false;
    for (final entry in _byOperation.entries.toList()) {
      final pending = entry.value;
      if (!pending.memberIds.contains(receipt.id)) continue;
      if (pending.committedIds.contains(receipt.id) && receipt.isCleared) {
        pending.memberIds.remove(receipt.id);
        pending.committedIds.remove(receipt.id);
        if (pending.memberIds.isEmpty) _byOperation.remove(entry.key);
        continue;
      }
      covered = true;
    }
    if (!covered || receipt.isCleared) return receipt;
    return receipt.copyWith(
      clearedAt: DateTime.now().toUtc(),
      clearReason: receipt.clearReason ?? AttentionClearReason.explicit,
    );
  }
}

final class _PendingClear {
  _PendingClear({required this.memberIds, required this.committedIds});

  final Set<String> memberIds;
  final Set<String> committedIds;
}
