import 'dart:convert';

import 'package:freezed_annotation/freezed_annotation.dart';

part 'room_message_mention_span.freezed.dart';

@freezed
abstract class RoomMessageMentionSpan with _$RoomMessageMentionSpan {
  const factory RoomMessageMentionSpan({
    required String userId,
    required int offset,
    required int length,
  }) = _RoomMessageMentionSpan;
}

/// Parses server mention spans, dropping malformed entries without throwing.
List<RoomMessageMentionSpan> parseRoomMessageMentionSpansJson(String raw) {
  if (raw.trim().isEmpty) return const [];
  try {
    final decoded = jsonDecode(raw);
    if (decoded is! List) return const [];
    return [
      for (final item in decoded)
        if (item is Map)
          if (item['userId'] case final String userId)
            if (item['offset'] case final int offset)
              if (item['length'] case final int length)
                RoomMessageMentionSpan(
                  userId: userId,
                  offset: offset,
                  length: length,
                ),
    ];
  } on FormatException {
    return const [];
  }
}
