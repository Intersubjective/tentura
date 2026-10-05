import 'package:flutter/widgets.dart';

import 'package:tentura/features/emoji/domain/emoji_shortcode_token.dart';

import '../../domain/entity/committed_mention.dart';

export 'package:tentura/features/emoji/domain/emoji_shortcode_token.dart'
    show EmojiShortcodeToken;

export '../../domain/entity/committed_mention.dart';

/// Text controller that detects the active `@handle` or `:shortcode` token at
/// cursor and can replace it with a selected mention or emoji.
final class MentionTextController extends TextEditingController {
  MentionTextController({super.text, this.emojiForShortcode});

  /// Resolves an exact shortcode (no colons) to its emoji. When set, typing
  /// the closing colon of a known `:shortcode:` replaces it with the emoji.
  final String? Function(String shortcode)? emojiForShortcode;

  String? _activeMentionQuery;
  TextRange? _activeMentionRange;
  EmojiShortcodeToken? _activeEmojiToken;
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

  /// `:query` being typed at cursor (query of 2+ characters), or `null`.
  EmojiShortcodeToken? get activeEmojiToken {
    _recompute();
    return _activeEmojiToken;
  }

  @override
  set value(TextEditingValue rawValue) {
    final oldValue = value;
    final newValue = _withTypedShortcodeReplaced(oldValue, rawValue);
    if (oldValue.text != newValue.text) {
      _shiftCommittedMentionsForEdit(oldValue, newValue);
    }
    super.value = newValue;
    _recompute();
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

  /// Slack-style: a typed closing colon turns a known `:shortcode:` into its
  /// emoji. Only a single typed `:` at a collapsed caret outside IME
  /// composition qualifies, so pastes and programmatic edits stay literal.
  TextEditingValue _withTypedShortcodeReplaced(
    TextEditingValue oldValue,
    TextEditingValue newValue,
  ) {
    final lookup = emojiForShortcode;
    if (lookup == null) return newValue;
    final newText = newValue.text;
    final sel = newValue.selection;
    if (!sel.isValid || !sel.isCollapsed) return newValue;
    if (newValue.composing.isValid && !newValue.composing.isCollapsed) {
      return newValue;
    }
    final caret = sel.baseOffset;
    if (newText.length != oldValue.text.length + 1 ||
        caret < 1 ||
        caret > newText.length ||
        newText[caret - 1] != ':' ||
        newText.substring(0, caret - 1) + newText.substring(caret) !=
            oldValue.text) {
      return newValue;
    }
    final done = completedEmojiShortcode(newText, caret);
    if (done == null) return newValue;
    final emoji = lookup(done.name.toLowerCase());
    if (emoji == null) return newValue;
    return TextEditingValue(
      text: newText.replaceRange(done.start, done.end, emoji),
      selection: TextSelection.collapsed(offset: done.start + emoji.length),
    );
  }

  void _recompute() {
    _activeMentionQuery = null;
    _activeMentionRange = null;
    _activeEmojiToken = null;

    final text = this.text;
    if (text.isEmpty) return;

    final selectionOffset = selection.baseOffset;
    final cursor = selectionOffset < 0 ? text.length : selectionOffset;
    if (cursor > text.length) return;

    _activeEmojiToken = activeEmojiShortcodeToken(text, cursor);

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

  /// Replaces the active `:query` token with [emoji]; `false` when none.
  bool insertEmoji(String emoji) {
    final token = activeEmojiToken;
    if (token == null) return false;
    value = value.copyWith(
      text: text.replaceRange(token.start, token.end, emoji),
      selection: TextSelection.collapsed(offset: token.start + emoji.length),
      composing: TextRange.empty,
    );
    return true;
  }
}
