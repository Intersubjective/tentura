import 'dart:convert';

import 'attention_event_classification.dart';
import 'entity/attention_receipt.dart';

/// Whether the server marked [receipt] *personal* (#189 rev 2): a person
/// addressed this to the viewer by name — a message to you, an ask aimed at
/// you, your offer answered — rather than the Request moving for everyone.
///
/// Decided on the server by why the viewer got the event
/// (`AttentionPolicy.isPersonal`), never here by event type: the same
/// `blockerOpened` is personal on your own item and general as a room member.
bool attentionReceiptIsPersonal(AttentionReceipt receipt) {
  final raw = receipt.presentationPayloadJson.trim();
  if (raw.isEmpty || raw == '{}') return false;
  try {
    final decoded = jsonDecode(raw);
    return decoded is Map && decoded['personal'] == true;
  } on Object {
    return false;
  }
}

/// One row of a card's «вам» zone: everything one sender sent the viewer,
/// newest first. The row shows the newest item; its × clears all of them.
class PersonalSenderRow {
  const PersonalSenderRow({required this.senderId, required this.receipts});

  /// Empty when the server named no actor; such a row stands alone.
  final String senderId;

  /// Newest first, never empty.
  final List<AttentionReceipt> receipts;

  AttentionReceipt get newest => receipts.first;
}

/// The two zones of a For You card (#189 rev 2), from its event preview.
///
/// * [personalRows] — the «вам» zone: one row per sender, newest sender
///   first. Rows are never merged across senders, and a personal item is
///   never merged with a general one.
/// * [changeLine] — the single newest *general* event. No count, no ×: the
///   rest of the general events live in the Timeline.
///
/// Obligations never reach either zone — For You carries only what can be
/// skipped. The server already keeps them out; this is the client's guard on
/// the same rule.
class RequestCardZones {
  const RequestCardZones({
    this.personalRows = const [],
    this.changeLine,
  });

  factory RequestCardZones.fromPreview(Iterable<AttentionReceipt> preview) {
    final events = [
      for (final event in preview)
        if (!event.requiresAction) event,
    ]..sort((a, b) => b.createdAt.compareTo(a.createdAt));

    final bySender = <String, List<AttentionReceipt>>{};
    final order = <String>[];
    AttentionReceipt? change;
    for (final event in events) {
      if (attentionReceiptIsPersonal(event)) {
        final actor = event.actorUserId?.trim() ?? '';
        // No actor: nothing to group by, so the item keeps a row of its own.
        final key = actor.isEmpty ? 'receipt:${event.id}' : actor;
        if (!bySender.containsKey(key)) order.add(key);
        bySender.putIfAbsent(key, () => []).add(event);
      } else if (change == null && !_neverAChangeLine(event)) {
        change = event;
      }
    }
    return RequestCardZones(
      personalRows: [
        for (final key in order)
          PersonalSenderRow(
            senderId: key.startsWith('receipt:') ? '' : key,
            receipts: List.unmodifiable(bySender[key]!),
          ),
      ],
      changeLine: change,
    );
  }

  final List<PersonalSenderRow> personalRows;
  final AttentionReceipt? changeLine;

  bool get hasPersonal => personalRows.isNotEmpty;

  /// How many preview events the rows and the change line stand for. The
  /// card's footer counts what is left as «Ещё N в хронологии».
  int get shownEventCount =>
      personalRows.fold(0, (sum, row) => sum + row.receipts.length) +
      (changeLine == null ? 0 : 1);
}

/// A deadline change only recolours the header deadline (§6.1); it is never
/// the card's change line.
bool _neverAChangeLine(AttentionReceipt event) =>
    attentionEventTypeOf(event.presentationPayloadJson) == 'deadlineChanged';
