import 'package:flutter/widgets.dart';

/// Text controller that detects the active `@handle` token at cursor and can
/// replace it with a selected mention.
final class MentionTextController extends TextEditingController {
  MentionTextController({super.text});

  String? _activeMentionQuery;
  TextRange? _activeMentionRange;

  /// `null` = no active mention at cursor, `''` = user typed `@` but no query.
  String? get activeMentionQuery => _activeMentionQuery;

  TextRange? get activeMentionRange => _activeMentionRange;

  @override
  set value(TextEditingValue newValue) {
    super.value = newValue;
    _recompute();
  }

  void _recompute() {
    _activeMentionQuery = null;
    _activeMentionRange = null;

    final cursor = selection.baseOffset;
    if (cursor < 0) return;

    final text = this.text;
    if (text.isEmpty) return;
    if (cursor > text.length) return;

    // Walk left to the beginning of the current token.
    var start = cursor;
    while (start > 0) {
      final ch = text[start - 1];
      if (ch == ' ' || ch == '\n' || ch == '\t') {
        break;
      }
      start--;
    }

    if (start >= text.length) return;
    if (text[start] != '@') return;

    // Require mention boundary (start-of-text or whitespace before '@').
    if (start > 0) {
      final prev = text[start - 1];
      if (prev != ' ' && prev != '\n' && prev != '\t') return;
    }

    final raw = text.substring(start + 1, cursor);
    if (raw.isNotEmpty && !RegExp(r'^[a-zA-Z0-9_]+$').hasMatch(raw)) {
      return;
    }

    _activeMentionQuery = raw.toLowerCase();
    _activeMentionRange = TextRange(start: start, end: cursor);
  }

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
