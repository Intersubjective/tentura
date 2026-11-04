import 'dart:convert';

import 'entity/attention_receipt.dart';

/// Server value when Questions holds the oldest unread message.
const kRequestCardUnreadRoomQuestions = 'questions';

/// Server value when the discussion holds the oldest unread.
const kRequestCardUnreadRoomDiscussion = 'discussion';

/// Whether [receipt] is a Questions room message (#656, #904).
bool attentionReceiptIsQuestionsRoomMessage(AttentionReceipt receipt) {
  if (receipt.presentationKey != 'room_message_posted') return false;
  if (receipt.coordinationItemId?.trim().isNotEmpty ?? false) return true;
  final raw = receipt.presentationPayloadJson.trim();
  if (raw.isEmpty || raw == '{}') return false;
  try {
    final decoded = jsonDecode(raw);
    if (decoded is! Map) return false;
    final id = decoded['coordinationItemId'];
    return id is String && id.trim().isNotEmpty;
  } on Object {
    return false;
  }
}

/// Optional attention receipts the Request card still renders as update rows.
///
/// Questions messages are unread via the card's room unread count only (#904).
Iterable<AttentionReceipt> requestCardVisibleAttentionEvents(
  Iterable<AttentionReceipt> events,
) => events.where((event) => !attentionReceiptIsQuestionsRoomMessage(event));

bool requestCardUnreadOpensQuestions(String? unreadRoom) =>
    unreadRoom == kRequestCardUnreadRoomQuestions;
