import 'package:freezed_annotation/freezed_annotation.dart';

import 'package:tentura/domain/entity/room_message.dart';

part 'room_message_receipt.freezed.dart';

enum RoomMessageReceiptState { pending, sent, read }

@freezed
abstract class RoomMessageReceipt with _$RoomMessageReceipt {
  const factory RoomMessageReceipt({
    required RoomMessageReceiptState state,
    @Default(<String>[]) List<String> readerIds,
  }) = _RoomMessageReceipt;
}

final class RoomReceiptIndex {
  const RoomReceiptIndex({
    required this.myUserId,
    required this.watermarks,
    required this.pendingLocalIds,
  });

  final String myUserId;
  final Map<String, DateTime> watermarks;
  final Set<String> pendingLocalIds;

  RoomMessageReceipt? receiptFor(RoomMessage message) {
    if (message.authorId != myUserId) {
      return null;
    }
    if (message.systemMessageKind != null) {
      return null;
    }
    if (message.id.startsWith('local:') || pendingLocalIds.contains(message.id)) {
      return const RoomMessageReceipt(state: RoomMessageReceiptState.pending);
    }

    final readers = <String, DateTime>{};
    for (final entry in watermarks.entries) {
      final userId = entry.key;
      if (userId == myUserId) {
        continue;
      }
      if (!entry.value.isBefore(message.createdAt)) {
        readers[userId] = entry.value;
      }
    }

    final readerIds = readers.entries.toList()
      ..sort((a, b) => b.value.compareTo(a.value));
    final sortedReaderIds = readerIds.map((e) => e.key).toList(growable: false);

    if (sortedReaderIds.isEmpty) {
      return const RoomMessageReceipt(state: RoomMessageReceiptState.sent);
    }
    return RoomMessageReceipt(
      state: RoomMessageReceiptState.read,
      readerIds: sortedReaderIds,
    );
  }

  /// Last-seen time for [userId] if it covers [messageCreatedAt], else null.
  DateTime? readerLastSeenAt(String userId, DateTime messageCreatedAt) {
    final lastSeenAt = watermarks[userId];
    if (lastSeenAt == null || lastSeenAt.isBefore(messageCreatedAt)) {
      return null;
    }
    return lastSeenAt;
  }
}
