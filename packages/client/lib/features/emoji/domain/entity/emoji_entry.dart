/// One emoji from the bundled catalog with the words that find it.
final class EmojiEntry {
  const EmojiEntry({
    required this.emoji,
    required this.shortcodes,
    required this.ruWords,
  });

  /// The emoji itself, as inserted into the message.
  final String emoji;

  /// Lowercase English shortcodes without colons (`smile`, `thumbsup`); the
  /// first one is shown in suggestions.
  final List<String> shortcodes;

  /// Lowercase Russian keywords (`ё` folded to `е`) for `:улыб`-style search.
  final List<String> ruWords;

  String get primaryShortcode => shortcodes.first;
}
