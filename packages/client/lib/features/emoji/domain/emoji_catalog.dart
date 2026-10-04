import 'emoji_catalog_data.dart';
import 'entity/emoji_entry.dart';

export 'entity/emoji_entry.dart';

/// A catalog hit plus the shortcode to show for it (the one that matched).
typedef EmojiMatch = ({EmojiEntry entry, String shortcode});

/// Bundled emoji catalog (`emojibase-data`) with shortcode search.
///
/// Parsed lazily on first use from [kEmojiCatalogData].
abstract final class EmojiCatalog {
  static List<EmojiEntry>? _entries;
  static Map<String, EmojiEntry>? _byShortcode;

  static List<EmojiEntry> get entries => _entries ??= _parse(kEmojiCatalogData);

  static Map<String, EmojiEntry> get _shortcodeIndex => _byShortcode ??= {
    for (final e in entries.reversed)
      for (final s in e.shortcodes) s: e,
  };

  /// Emoji for an exact English [shortcode] (no colons), or `null`.
  static String? emojiForShortcode(String shortcode) =>
      _shortcodeIndex[shortcode.toLowerCase()]?.emoji;

  /// Emoji whose shortcode (English) or keyword (Russian) starts with [query].
  ///
  /// Order: exact shortcode, shortcode prefix, prefix of a shortcode word
  /// (`joy` → `joy_cat`); within a rank shorter shortcodes first (`smi` →
  /// `smile` before `smiley`), then catalog order. Cyrillic queries match
  /// Russian keyword prefixes, in catalog order.
  static List<EmojiMatch> search(String query, {required int limit}) {
    final q = normalizeQuery(query);
    if (q.isEmpty || limit <= 0) return const [];
    final cyrillic = _cyrillic.hasMatch(q);
    final ranked = <({int rank, int index, EmojiMatch match})>[];
    final all = entries;
    for (var i = 0; i < all.length; i++) {
      final e = all[i];
      if (cyrillic) {
        if (e.ruWords.any((w) => w.startsWith(q))) {
          ranked.add((
            rank: 0,
            index: i,
            match: (entry: e, shortcode: e.primaryShortcode),
          ));
        }
        continue;
      }
      ({int rank, String shortcode})? best;
      for (final s in e.shortcodes) {
        final rank = s == q
            ? 0
            : s.startsWith(q)
            ? 1
            : s.split(_wordSeparator).skip(1).any((w) => w.startsWith(q))
            ? 2
            : null;
        if (rank != null && (best == null || rank < best.rank)) {
          best = (rank: rank, shortcode: s);
        }
      }
      if (best != null) {
        ranked.add((
          rank: best.rank,
          index: i,
          match: (entry: e, shortcode: best.shortcode),
        ));
      }
    }
    ranked.sort((a, b) {
      if (a.rank != b.rank) return a.rank.compareTo(b.rank);
      final byLength = cyrillic
          ? 0
          : a.match.shortcode.length.compareTo(b.match.shortcode.length);
      return byLength != 0 ? byLength : a.index.compareTo(b.index);
    });
    return [for (final r in ranked.take(limit)) r.match];
  }

  /// Lowercase, `ё` folded to `е` (the catalog stores Russian words so).
  static String normalizeQuery(String query) =>
      query.trim().toLowerCase().replaceAll('ё', 'е');

  static final _cyrillic = RegExp('[а-я]');
  static final _wordSeparator = RegExp('[_-]');

  static List<EmojiEntry> _parse(String data) {
    final out = <EmojiEntry>[];
    for (final line in data.split('\n')) {
      final fields = line.split('\t');
      if (fields.length != 3 || fields[1].isEmpty) continue;
      out.add(
        EmojiEntry(
          emoji: fields[0],
          shortcodes: fields[1].split(' '),
          ruWords: fields[2].isEmpty ? const [] : fields[2].split(' '),
        ),
      );
    }
    return List.unmodifiable(out);
  }
}
