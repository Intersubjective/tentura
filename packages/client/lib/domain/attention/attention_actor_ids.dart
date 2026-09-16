import 'entity/attention_receipt.dart';

/// Collects non-empty [AttentionReceipt.actorUserId] values from [receipts]
/// and nested [AttentionReceipt.eventsPreview] children.
Set<String> attentionActorIds(Iterable<AttentionReceipt> receipts) {
  final ids = <String>{};
  for (final receipt in receipts) {
    _collect(receipt, ids);
  }
  return ids;
}

void _collect(AttentionReceipt receipt, Set<String> ids) {
  final actorId = receipt.actorUserId?.trim() ?? '';
  if (actorId.isNotEmpty) {
    ids.add(actorId);
  }
  for (final child in receipt.eventsPreview) {
    _collect(child, ids);
  }
}
