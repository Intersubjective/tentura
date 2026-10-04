import 'package:flutter/foundation.dart';

part 'emoji_catalog_data.dart';

/// Picker sections, in the order the picker shows them.
enum EmojiCategory {
  smileys,
  people,
  nature,
  food,
  travel,
  activities,
  objects,
  symbols,
  flags,
}

/// One emoji with its `:shortcode:` names ([aliases]) and search keywords.
@immutable
final class EmojiEntry {
  const EmojiEntry(
    this.emoji,
    this.category,
    this.aliases,
    this.tags,
    this.description,
  );

  final String emoji;

  final EmojiCategory category;

  /// Shortcode names without colons; the first one is the canonical name.
  final List<String> aliases;

  final List<String> tags;

  /// Unicode CLDR name, e.g. `grinning face with smiling eyes`.
  final String description;

  String get shortcode => aliases.first;
}

/// Static emoji catalog (gemoji names) with shortcode lookup and search.
abstract final class EmojiCatalog {
  /// Every emoji in picker order.
  static List<EmojiEntry> get all => _kEmojiCatalog;

  static final Map<EmojiCategory, List<EmojiEntry>> byCategory = {
    for (final category in EmojiCategory.values)
      category: [
        for (final e in _kEmojiCatalog)
          if (e.category == category) e,
      ],
  };

  static final Map<String, EmojiEntry> _byAlias = {
    for (final e in _kEmojiCatalog)
      for (final alias in e.aliases) alias: e,
  };

  static final Map<String, EmojiEntry> _byEmoji = {
    for (final e in _kEmojiCatalog) e.emoji: e,
  };

  /// Exact shortcode lookup (`smile` or `:smile:`), case-insensitive.
  static EmojiEntry? byShortcode(String shortcode) {
    var name = shortcode.trim().toLowerCase();
    if (name.length > 2 && name.startsWith(':') && name.endsWith(':')) {
      name = name.substring(1, name.length - 1);
    }
    return _byAlias[name];
  }

  static EmojiEntry? byEmoji(String emoji) => _byEmoji[emoji];

  /// Emoji whose names or keywords match [query], best match first.
  ///
  /// Ranking: exact shortcode, shortcode prefix, prefix of a word inside a
  /// shortcode (`smile` → `sweat_smile`), keyword prefix, shortcode substring,
  /// then a word of the Unicode name. Ties keep catalog order, which puts
  /// common faces before rarer symbols.
  static List<EmojiEntry> search(String query, {int? limit}) {
    final q = query.trim().toLowerCase();
    if (q.isEmpty) return const [];
    final buckets = List.generate(6, (_) => <EmojiEntry>[]);
    for (final e in _kEmojiCatalog) {
      final rank = _rank(e, q);
      if (rank != null) buckets[rank].add(e);
    }
    final out = buckets.expand((b) => b);
    return (limit == null ? out : out.take(limit)).toList(growable: false);
  }

  static int? _rank(EmojiEntry e, String q) {
    var best = 99;
    for (final alias in e.aliases) {
      if (alias == q) return 0;
      if (alias.startsWith(q)) {
        best = best < 1 ? best : 1;
      } else if (alias.split('_').any((w) => w.startsWith(q))) {
        best = best < 2 ? best : 2;
      } else if (alias.contains(q)) {
        best = best < 4 ? best : 4;
      }
    }
    if (best > 3 && e.tags.any((t) => t.startsWith(q))) best = 3;
    if (best > 5 && e.description.split(' ').any((w) => w.startsWith(q))) {
      best = 5;
    }
    return best == 99 ? null : best;
  }
}
