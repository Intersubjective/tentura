const kRoomReplyExcerptMaxChars = 160;

/// One-line excerpt of a quoted message body (client copy of server helper).
String? roomReplyExcerpt(String? body) {
  if (body == null) {
    return null;
  }
  final collapsed = body.trim().replaceAll(RegExp(r'\s+'), ' ');
  if (collapsed.isEmpty) {
    return null;
  }
  final runes = collapsed.runes;
  if (runes.length <= kRoomReplyExcerptMaxChars) {
    return collapsed;
  }
  return '${String.fromCharCodes(runes.take(kRoomReplyExcerptMaxChars))}…';
}
