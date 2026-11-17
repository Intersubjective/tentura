import 'dart:convert';

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
  final partnerId = batonPartnerUserId(receipt.presentationPayloadJson);
  if (partnerId != null) ids.add(partnerId);
  for (final child in receipt.eventsPreview) {
    _collect(child, ids);
  }
}

/// The partner a pair `batonTaken` receipt names (`withUserId`); null when the
/// receipt is solo or carries no readable payload.
String? batonPartnerUserId(String presentationPayloadJson) {
  final trimmed = presentationPayloadJson.trim();
  if (trimmed.isEmpty || trimmed == '{}') return null;
  try {
    final decoded = jsonDecode(trimmed);
    final id = decoded is Map ? decoded['withUserId'] : null;
    return id is String && id.trim().isNotEmpty ? id.trim() : null;
  } on Object {
    return null;
  }
}
