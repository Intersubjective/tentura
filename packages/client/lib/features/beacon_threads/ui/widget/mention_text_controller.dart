import 'package:flutter/widgets.dart';

import '../../domain/entity/committed_mention.dart';

export '../../domain/entity/committed_mention.dart';

/// Text controller that detects the active `@handle` or `:shortcode` token at
/// cursor and can replace it with a selected mention or emoji.
final class MentionTextController extends TextEditingController {
  MentionTextController({super.text, this.emojiForShortcode});

  /// Resolves a complete shortcode name (no colons) to its emoji. When set,
  /// typing the closing colon of a known `:name:` replaces it with the emoji.
  String? Function(String name)? emojiForShortcode;

  String? _activeMentionQuery;
  TextRange? _activeMentionRange;
  String? _activeEmojiQuery;
  TextRange? _activeEmojiRange;
  final _committed = <CommittedMention>[];

  /// Id-anchored mention ranges that still exactly survive the current text.
  List<CommittedMention> get committedMentions => List.unmodifiable(_committed);

  /// `null` = no active mention at cursor, `''` = user typed `@` but no query.
  String? get activeMentionQuery {
    _recompute();
    return _activeMentionQuery;
  }

  TextRange? get activeMentionRange {
    _recompute();
    return _activeMentionRange;
  }

  /// Name typed after a `:` at cursor (lowercase, may be empty), or `null`
  /// when the cursor is not inside a `:shortcode` token.
  String? get activeEmojiQuery {
    _recompute();
    return _activeEmojiQuery;
  }

  TextRange? get activeEmojiRange {
    _recompute();
    return _activeEmojiRange;
  }

  @override
  set value(TextEditingValue newValue) {
    final oldValue = value;
    if (oldValue.text != newValue.text) {
      _shiftCommittedMentionsForEdit(oldValue, newValue);
    }
    super.value = newValue;
    _recompute();
    _replaceCompletedShortcode(oldValue, newValue);
  }

  @override
  void clear() {
    _committed.clear();
    super.clear();
  }

  void _shiftCommittedMentionsForEdit(
    TextEditingValue oldValue,
    TextEditingValue newValue,
  ) {
    final oldText = oldValue.text;
    final newText = newValue.text;
    final selectionEdit = _selectionAwareEdit(oldValue, newValue);
    if (selectionEdit case final edit?) {
      _applyEdit(edit);
      return;
    }
    var prefix = 0;
    final shortest = oldText.length < newText.length
        ? oldText.length
        : newText.length;
    while (prefix < shortest && oldText[prefix] == newText[prefix]) {
      prefix++;
    }
    var suffix = 0;
    while (suffix < shortest - prefix &&
        oldText[oldText.length - 1 - suffix] ==
            newText[newText.length - 1 - suffix]) {
      suffix++;
    }
    _applyEdit((
      oldStart: prefix,
      oldEnd: oldText.length - suffix,
      newEnd: newText.length - suffix,
    ));
  }

  ({int oldStart, int oldEnd, int newEnd})? _selectionAwareEdit(
    TextEditingValue oldValue,
    TextEditingValue newValue,
  ) {
    final oldText = oldValue.text;
    final newText = newValue.text;
    final oldSelection = oldValue.selection;
    final newSelection = newValue.selection;
    if (!oldSelection.isValid || !newSelection.isValid) return null;

    final candidates = <({int oldStart, int oldEnd, int newEnd})>[];
    if (!oldSelection.isCollapsed) {
      candidates.add((
        oldStart: oldSelection.start,
        oldEnd: oldSelection.end,
        newEnd:
            oldSelection.start +
            newText.length -
            (oldText.length - oldSelection.end + oldSelection.start),
      ));
    } else {
      final caret = oldSelection.extentOffset;
      final delta = newText.length - oldText.length;
      if (delta >= 0) {
        candidates.add((oldStart: caret, oldEnd: caret, newEnd: caret + delta));
      } else {
        final deleted = -delta;
        candidates
          ..add((
            oldStart: caret - deleted,
            oldEnd: caret,
            newEnd: caret - deleted,
          ))
          ..add((
            oldStart: caret,
            oldEnd: caret + deleted,
            newEnd: caret,
          ));
      }
    }
    for (final candidate in candidates) {
      if (_isExactEdit(oldText, newText, candidate)) return candidate;
    }
    return null;
  }

  bool _isExactEdit(
    String oldText,
    String newText,
    ({int oldStart, int oldEnd, int newEnd}) edit,
  ) {
    if (edit.oldStart < 0 ||
        edit.oldEnd < edit.oldStart ||
        edit.oldEnd > oldText.length ||
        edit.newEnd < edit.oldStart ||
        edit.newEnd > newText.length) {
      return false;
    }
    return oldText.substring(0, edit.oldStart) ==
            newText.substring(0, edit.oldStart) &&
        oldText.substring(edit.oldEnd) == newText.substring(edit.newEnd);
  }

  void _applyEdit(({int oldStart, int oldEnd, int newEnd}) edit) {
    final delta = edit.newEnd - edit.oldEnd;
    final next = <CommittedMention>[];
    for (final mention in _committed) {
      if (mention.end <= edit.oldStart) {
        next.add(mention);
      } else if (mention.start >= edit.oldEnd) {
        next.add((
          userId: mention.userId,
          start: mention.start + delta,
          end: mention.end + delta,
        ));
      }
    }
    _committed
      ..clear()
      ..addAll(next);
  }

  void _recompute() {
    _activeMentionQuery = null;
    _activeMentionRange = null;
    _activeEmojiQuery = null;
    _activeEmojiRange = null;

    final text = this.text;
    if (text.isEmpty) return;

    final selectionOffset = selection.baseOffset;
    final cursor = selectionOffset < 0 ? text.length : selectionOffset;
    if (cursor > text.length) return;
    _recomputeEmoji(text, cursor);

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
    if (cursor <= start) return;

    final raw = text.substring(start + 1, cursor);
    if (raw.isNotEmpty && !RegExp(r'^[a-zA-Z0-9_]+$').hasMatch(raw)) {
      return;
    }

    _activeMentionQuery = raw.toLowerCase();
    _activeMentionRange = TextRange(start: start, end: cursor);
  }

  void _recomputeEmoji(String text, int cursor) {
    _activeEmojiQuery = null;
    _activeEmojiRange = null;
    final start = _shortcodeStart(text, cursor);
    if (start == null) return;
    _activeEmojiQuery = text.substring(start + 1, cursor).toLowerCase();
    _activeEmojiRange = TextRange(start: start, end: cursor);
  }

  /// Index of the `:` opening a shortcode token that ends at [end], or `null`.
  /// The colon must start the text or follow whitespace, so `10:30` and URLs
  /// never trigger.
  static int? _shortcodeStart(String text, int end) {
    var start = end;
    while (start > 0 && _isShortcodeChar(text.codeUnitAt(start - 1))) {
      start--;
    }
    if (start == 0 || text[start - 1] != ':') return null;
    start--;
    if (start > 0 && !_isMentionBoundary(text[start - 1])) return null;
    return start;
  }

  static bool _isShortcodeChar(int c) =>
      (c >= 0x61 && c <= 0x7A) || // a-z
      (c >= 0x41 && c <= 0x5A) || // A-Z
      (c >= 0x30 && c <= 0x39) || // 0-9
      c == 0x5F || // _
      c == 0x2B || // +
      c == 0x2D; // -

  /// Typing the closing `:` of a known `:name:` swaps the token for its emoji.
  void _replaceCompletedShortcode(
    TextEditingValue oldValue,
    TextEditingValue newValue,
  ) {
    final lookup = emojiForShortcode;
    if (lookup == null) return;
    final text = newValue.text;
    final selection = newValue.selection;
    if (!selection.isValid || !selection.isCollapsed) return;
    if (newValue.composing.isValid && !newValue.composing.isCollapsed) return;
    final cursor = selection.extentOffset;
    if (text.length != oldValue.text.length + 1 ||
        cursor < 1 ||
        cursor > text.length ||
        text[cursor - 1] != ':' ||
        text.substring(0, cursor - 1) + text.substring(cursor) !=
            oldValue.text) {
      return;
    }
    final start = _shortcodeStart(text, cursor - 1);
    if (start == null || start + 1 >= cursor - 1) return;
    final emoji = lookup(text.substring(start + 1, cursor - 1).toLowerCase());
    if (emoji == null) return;
    value = TextEditingValue(
      text: text.replaceRange(start, cursor, emoji),
      selection: TextSelection.collapsed(offset: start + emoji.length),
    );
  }

  /// Replaces the active `:shortcode` token with [emoji].
  bool insertEmojiForActiveShortcode(String emoji) {
    final range = activeEmojiRange;
    if (range == null) return false;
    value = TextEditingValue(
      text: text.replaceRange(range.start, range.end, emoji),
      selection: TextSelection.collapsed(offset: range.start + emoji.length),
    );
    return true;
  }

  /// Inserts [insertion] at the cursor, replacing any selected text; appends
  /// when the field has never had a selection.
  void insertAtSelection(String insertion) {
    final t = text;
    final sel = selection;
    final start = sel.isValid ? sel.start.clamp(0, t.length) : t.length;
    final end = sel.isValid ? sel.end.clamp(start, t.length) : t.length;
    value = TextEditingValue(
      text: t.replaceRange(start, end, insertion),
      selection: TextSelection.collapsed(offset: start + insertion.length),
    );
  }

  /// Whitespace that ends a mention token. Non-BMP / surrogate units are not
  /// boundaries — they keep the walk going so `@` glued to an emoji is rejected.
  static bool _isMentionBoundary(String ch) =>
      ch == ' ' || ch == '\n' || ch == '\t';

  bool insertLiteralMentionText(String token, {String? userId}) {
    final range = _activeMentionRange;
    if (range == null) return false;
    final full = '$token ';

    final t = text;
    final before = t.substring(0, range.start);
    final after = t.substring(range.end);
    final next = before + full + after;
    final nextCursor = before.length + full.length;

    value = value.copyWith(
      text: next,
      selection: TextSelection.collapsed(offset: nextCursor),
      composing: TextRange.empty,
    );
    if (userId != null) {
      _committed.add((
        userId: userId,
        start: before.length,
        end: before.length + token.length,
      ));
    }
    return true;
  }

  bool insertMention(String handleLowercase) =>
      insertLiteralMentionText('@$handleLowercase');
}
