import 'package:flutter/widgets.dart';

/// Text controller that detects the active `@handle` token at cursor and can
/// replace it with a selected mention.
final class MentionTextController extends TextEditingController {
  MentionTextController({super.text});

  String? _activeMentionQuery;
  TextRange? _activeMentionRange;

  /// `null` = no active mention at cursor, `''` = user typed `@` but no query.
  String? get activeMentionQuery {
    _recompute();
    return _activeMentionQuery;
  }

  TextRange? get activeMentionRange {
    _recompute();
    return _activeMentionRange;
  }

  @override
  set value(TextEditingValue newValue) {
    super.value = newValue;
    _recompute();
  }

  void _recompute() {
    _activeMentionQuery = null;
    _activeMentionRange = null;

    final text = this.text;
    if (text.isEmpty) return;

    final selectionOffset = selection.baseOffset;
    final cursor = selectionOffset < 0 ? text.length : selectionOffset;
    if (cursor > text.length) return;

    // Walk left by UTF-16 code units to the token start. Handles are ASCII, so
    // surrogate pairs (emoji) never match `@` / handle chars; they only act as
    // non-whitespace boundaries that reject a mention without a preceding space.
    var start = cursor;
    while (start > 0) {
      final ch = text[start - 1];
      if (_isMentionBoundary(ch)) {
        break;
      }
      start--;
    }

    if (start >= text.length) return;
    if (text[start] != '@') return;

    // Require mention boundary (start-of-text or whitespace before '@').
    if (start > 0 && !_isMentionBoundary(text[start - 1])) {
      return;
    }

    final raw = text.substring(start + 1, cursor);
    if (raw.isNotEmpty && !RegExp(r'^[a-zA-Z0-9_]+$').hasMatch(raw)) {
      return;
    }

    _activeMentionQuery = raw.toLowerCase();
    _activeMentionRange = TextRange(start: start, end: cursor);
  }

  /// Whitespace that ends a mention token. Non-BMP / surrogate units are not
  /// boundaries — they keep the walk going so `@` glued to an emoji is rejected.
  static bool _isMentionBoundary(String ch) =>
      ch == ' ' || ch == '\n' || ch == '\t';

  bool insertMention(String handleLowercase) {
    final range = _activeMentionRange;
    if (range == null) return false;
    final token = '@$handleLowercase ';

    final t = text;
    final before = t.substring(0, range.start);
    final after = t.substring(range.end);
    final next = before + token + after;
    final nextCursor = before.length + token.length;

    value = value.copyWith(
      text: next,
      selection: TextSelection.collapsed(offset: nextCursor),
      composing: TextRange.empty,
    );
    return true;
  }
}
