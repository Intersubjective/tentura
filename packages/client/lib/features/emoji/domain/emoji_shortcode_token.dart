/// An `:query` token being typed; `start` is the opening colon, `end` the
/// cursor. `query` is raw (not lowercased).
typedef EmojiShortcodeToken = ({String query, int start, int end});

/// Minimum characters after `:` before suggestions open, so a lone colon
/// (`Итог: …`, `:)`) never pops anything.
const kEmojiShortcodeMinQueryLength = 2;

/// The `:query` token that ends at [cursor], or `null`.
///
/// The colon must start the text or follow a character that cannot precede a
/// shortcode: not a letter, digit, `_`, `:` or `/`. That rejects `10:30`,
/// `https://` and `word:x`, but accepts `😄:joy` and `(:joy`.
EmojiShortcodeToken? activeEmojiShortcodeToken(String text, int cursor) {
  if (cursor < 0 || cursor > text.length) return null;
  var start = cursor;
  while (start > 0 && _isShortcodeChar(text[start - 1])) {
    start--;
  }
  final colon = start - 1;
  if (colon < 0 || text[colon] != ':') return null;
  if (colon > 0 && _blocksOpeningColon(text[colon - 1])) return null;
  final query = text.substring(start, cursor);
  if (query.length < kEmojiShortcodeMinQueryLength) return null;
  return (query: query, start: colon, end: cursor);
}

/// A complete `:shortcode:` whose closing colon sits right before [cursor],
/// or `null`. Returns the range of the whole token and its inner name.
({String name, int start, int end})? completedEmojiShortcode(
  String text,
  int cursor,
) {
  if (cursor < 1 || cursor > text.length || text[cursor - 1] != ':') {
    return null;
  }
  final token = activeEmojiShortcodeToken(text, cursor - 1);
  if (token == null) return null;
  return (name: token.query, start: token.start, end: cursor);
}

bool _isShortcodeChar(String ch) => _shortcodeChar.hasMatch(ch);

bool _blocksOpeningColon(String ch) => _blocking.hasMatch(ch);

final _shortcodeChar = RegExp(r'^[a-zA-Z0-9_+\-а-яА-ЯёЁ]$');
final _blocking = RegExp(r'^[a-zA-Z0-9_:/а-яА-ЯёЁ]$');
