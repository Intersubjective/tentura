/// Folds a search query: lower case, ё→е, no `@`, trimmed.
String foldSearchQuery(String query) =>
    query.toLowerCase().replaceAll('ё', 'е').replaceAll('@', '').trim();

/// Splits a folded query into words, also on Unicode whitespace.
List<String> searchWords(String folded) => folded
    .split('')
    .map((character) => character.trim().isEmpty ? ' ' : character)
    .join()
    .split(' ')
    .where((word) => word.isNotEmpty)
    .toList();

/// Longest folded query and most words a fact search uses.
const kMaxFactSearchQueryChars = 100;
const kMaxFactSearchWords = 6;
