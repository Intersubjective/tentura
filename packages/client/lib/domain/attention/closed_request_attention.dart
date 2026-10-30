import 'dart:convert';

import 'package:tentura_root/domain/entity/beacon_status.dart';

import '../entity/beacon.dart';
import 'attention_event_classification.dart';
import 'entity/attention_receipt.dart';
import 'request_card_zones.dart';

/// Closed, cancelled, or deleted: the Request no longer takes help or forwards.
bool attentionRequestIsClosed(BeaconStatus status) =>
    status == BeaconStatus.closed ||
    status == BeaconStatus.cancelled ||
    status == BeaconStatus.deleted;

/// Whether this Activity surface should treat the Request as closed.
///
/// The beacon status wins when it is already closed, and when it moved on
/// after the receipt that said closed (a reopen). A receipt the client
/// already holds (`toStatus`, or a finalized closure) covers a row whose
/// beacon was built without a status, and a pinned row whose beacon has not
/// caught up yet.
bool attentionSurfaceIsClosed({
  required Beacon beacon,
  AttentionReceipt? representative,
  Iterable<AttentionReceipt> eventsPreview = const [],
}) {
  if (attentionRequestIsClosed(beacon.status)) return true;
  final reported = _newestReportedStatus([
    ?representative,
    ...eventsPreview,
  ]);
  if (reported == null || !attentionRequestIsClosed(reported.status)) {
    return false;
  }
  final changedAt = beacon.statusChangedAt;
  if (changedAt != null && reported.at.isBefore(changedAt)) return false;
  return true;
}

/// Status named by the newest status-bearing receipt, if any.
BeaconStatus? beaconStatusFromAttentionReceipts(
  Iterable<AttentionReceipt> receipts,
) => _newestReportedStatus(receipts)?.status;

/// After close, «something for you» is a live address: a person wrote to the
/// viewer, or the closure names the viewer's own result. A declined
/// invitation and the close itself are not.
bool attentionAddressedAfterClose(AttentionReceipt receipt) {
  if (attentionReceiptHasOwnOutcome(receipt)) return true;
  if (!attentionReceiptIsPersonal(receipt)) return false;
  return switch (attentionEventTypeOf(receipt.presentationPayloadJson)) {
    'authorInviteReceived' ||
    'authorInviteAccepted' ||
    'authorInviteDeclined' ||
    'relayReceived' ||
    'requestStatusChanged' ||
    'beaconHierarchyStatusChanged' ||
    'closureOpened' ||
    'closureFinalized' ||
    'closureCancelled' ||
    'closureDraftReminder' ||
    'deadlineChanged' ||
    'deadlineReminder' => false,
    _ => true,
  };
}

/// Any preview already names the viewer's own closure result.
bool attentionPreviewHasOwnOutcome(Iterable<AttentionReceipt> receipts) =>
    receipts.any(attentionReceiptHasOwnOutcome);

/// The closure payload names this viewer's result (`outcome`).
bool attentionReceiptHasOwnOutcome(AttentionReceipt receipt) {
  final outcome = _payloadString(receipt.presentationPayloadJson, 'outcome');
  return outcome != null && outcome.isNotEmpty;
}

({BeaconStatus status, DateTime at})? _newestReportedStatus(
  Iterable<AttentionReceipt> receipts,
) {
  ({BeaconStatus status, DateTime at})? newest;
  for (final receipt in receipts) {
    final status = _statusOf(receipt);
    if (status == null) continue;
    if (newest == null || !receipt.createdAt.isBefore(newest.at)) {
      newest = (status: status, at: receipt.createdAt);
    }
  }
  return newest;
}

BeaconStatus? _statusOf(AttentionReceipt receipt) {
  final type = attentionEventTypeOf(receipt.presentationPayloadJson);
  if (type == 'closureFinalized') return BeaconStatus.closed;
  if (type != 'requestStatusChanged' &&
      type != 'beaconHierarchyStatusChanged') {
    return null;
  }
  final name = _payloadString(receipt.presentationPayloadJson, 'toStatus');
  if (name == null) return null;
  return BeaconStatus.values.asNameMap()[name];
}

String? _payloadString(String presentationPayloadJson, String key) {
  final raw = presentationPayloadJson.trim();
  if (raw.isEmpty || raw == '{}') return null;
  try {
    final decoded = jsonDecode(raw);
    if (decoded is! Map) return null;
    final value = decoded[key];
    if (value is! String) return null;
    final trimmed = value.trim();
    return trimmed.isEmpty ? null : trimmed;
  } on Object {
    return null;
  }
}
