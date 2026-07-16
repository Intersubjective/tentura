import 'entity/attention_receipt.dart';

/// Keeps local acknowledgement intent monotonic until the server confirms it.
final class AttentionAckStore {
  String _accountId = '';
  final Set<String> _optimisticallySeen = <String>{};

  void resetForAccount(String accountId) {
    if (_accountId == accountId) return;
    _accountId = accountId;
    _optimisticallySeen.clear();
  }

  void markSeen(Iterable<String> ids) => _optimisticallySeen.addAll(ids);

  void markAllSeen(Iterable<String> ids) => _optimisticallySeen.addAll(ids);

  AttentionReceipt apply(AttentionReceipt receipt) {
    if (!_optimisticallySeen.contains(receipt.id)) return receipt;
    if (receipt.isSeen) {
      _optimisticallySeen.remove(receipt.id);
      return receipt;
    }
    return receipt.copyWith(seenAt: DateTime.now().toUtc());
  }

  void discard(Iterable<String> ids) => _optimisticallySeen.removeAll(ids);

  bool isOptimisticallySeen(String id) => _optimisticallySeen.contains(id);
}
