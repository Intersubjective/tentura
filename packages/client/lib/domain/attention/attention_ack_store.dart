import 'entity/attention_receipt.dart';

enum AttentionAckIntent { seen, unseen }

/// Keeps local acknowledgement intent until the matching generation confirms.
final class AttentionAckStore {
  String _accountId = '';
  int _clock = 0;
  final Map<String, _PendingAck> _pending = {};

  void resetForAccount(String accountId) {
    if (_accountId == accountId) return;
    _accountId = accountId;
    _clock = 0;
    _pending.clear();
  }

  int markSeen(Iterable<String> ids) => _set(ids, AttentionAckIntent.seen);

  int markUnseen(Iterable<String> ids) => _set(ids, AttentionAckIntent.unseen);

  int markAllSeen(Iterable<String> ids) => _set(ids, AttentionAckIntent.seen);

  int _set(Iterable<String> ids, AttentionAckIntent intent) {
    final token = ++_clock;
    for (final id in ids) {
      _pending[id] = _PendingAck(intent: intent, token: token);
    }
    return token;
  }

  void markCommitted(Iterable<String> ids, int token) {
    for (final id in ids) {
      final ack = _pending[id];
      if (ack == null || ack.token != token) continue;
      _pending[id] = ack.copyWith(committed: true);
    }
  }

  void discard(Iterable<String> ids, {int? token}) {
    for (final id in ids) {
      final ack = _pending[id];
      if (ack == null) continue;
      if (token == null || ack.token == token) _pending.remove(id);
    }
  }

  bool hasToken(String id, int token) {
    final ack = _pending[id];
    return ack != null && ack.token == token;
  }

  AttentionReceipt apply(AttentionReceipt receipt) {
    final ack = _pending[receipt.id];
    if (ack == null) return receipt;
    final matches = ack.intent == AttentionAckIntent.seen
        ? receipt.isSeen
        : !receipt.isSeen;
    if (ack.committed && matches) {
      _pending.remove(receipt.id);
      return receipt;
    }
    return switch (ack.intent) {
      AttentionAckIntent.seen => receipt.copyWith(seenAt: DateTime.now().toUtc()),
      AttentionAckIntent.unseen => receipt.copyWith(seenAt: null),
    };
  }

  int pendingUnreadDelta(Map<String, AttentionReceipt> receiptsById) {
    var n = 0;
    for (final entry in _pending.entries) {
      final raw = receiptsById[entry.key];
      if (raw == null) continue;
      final wantSeen = entry.value.intent == AttentionAckIntent.seen;
      if (wantSeen && !raw.isSeen) n--;
      if (!wantSeen && raw.isSeen) n++;
    }
    return n;
  }

  bool isOptimisticallySeen(String id) =>
      _pending[id]?.intent == AttentionAckIntent.seen;

  bool isOptimisticallyUnseen(String id) =>
      _pending[id]?.intent == AttentionAckIntent.unseen;
}

final class _PendingAck {
  const _PendingAck({
    required this.intent,
    required this.token,
    this.committed = false,
  });

  final AttentionAckIntent intent;
  final int token;
  final bool committed;

  _PendingAck copyWith({bool? committed}) => _PendingAck(
    intent: intent,
    token: token,
    committed: committed ?? this.committed,
  );
}
