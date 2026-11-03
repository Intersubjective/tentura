const kRoomReplyExcerptMaxChars = 160;

final _combiningMark = RegExp(r'^\p{M}$', unicode: true);

/// Collapses whitespace and quotes at most 160 runes, followed by an ellipsis
/// when truncated. Blank bodies have no excerpt.
///
/// Surrogate pairs stay intact. If the cut separates a base from its combining
/// marks, omit that sequence instead of showing an unaccented base. Other
/// multi-rune emoji sequences retain the existing rune-based boundary.
String? roomReplyExcerptFromBody(String? body) {
  if (body == null) {
    return null;
  }
  final collapsed = body.trim().replaceAll(RegExp(r'\s+'), ' ');
  if (collapsed.isEmpty) {
    return null;
  }
  final runes = collapsed.runes.toList(growable: false);
  if (runes.length <= kRoomReplyExcerptMaxChars) {
    return collapsed;
  }
  var end = kRoomReplyExcerptMaxChars;
  if (_combiningMark.hasMatch(String.fromCharCode(runes[end]))) {
    while (end > 0 &&
        _combiningMark.hasMatch(String.fromCharCode(runes[end - 1]))) {
      end--;
    }
    if (end > 0) {
      end--;
    }
  }
  return '${String.fromCharCodes(runes.take(end))}…';
}
