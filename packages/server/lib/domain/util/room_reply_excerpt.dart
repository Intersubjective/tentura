const kRoomReplyExcerptMaxChars = 160;

/// One-line excerpt of a quoted message body.
///
/// Collapses all whitespace runs to single spaces and truncates on a **rune**
/// boundary (so surrogate pairs never split). Full grapheme-cluster safety
/// (ZWJ sequences, skin-tone modifiers) is deliberately *not* promised — the
/// server has no `characters` dependency and a clipped ZWJ sequence degrades
/// to two visible glyphs, which is acceptable in a 160-char preview.
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
