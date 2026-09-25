/// Word-level diff kind (issue #181 plan §14.2: pure fact-revision diff).
enum DiffKind { same, added, removed }

/// A run of text tagged with how it relates between `older` and `newer`.
final class DiffSegment {
  const DiffSegment(this.text, this.kind);

  final String text;
  final DiffKind kind;
}

final RegExp _tokenPattern = RegExp(r'\s+|\S+');

List<String> _tokenize(String text) =>
    _tokenPattern.allMatches(text).map((m) => m[0]!).toList();

/// Word-level diff between [older] and [newer], preserving whitespace.
///
/// Tokens are runs of whitespace or non-whitespace so separators are diffed
/// alongside words; adjacent segments of the same [DiffKind] are merged.
/// Concatenating the `same`+`removed` segments reproduces [older] exactly,
/// and `same`+`added` reproduces [newer] exactly.
List<DiffSegment> wordDiff(String older, String newer) {
  final a = _tokenize(older);
  final b = _tokenize(newer);
  final m = a.length;
  final n = b.length;

  final lcs = List.generate(m + 1, (_) => List<int>.filled(n + 1, 0));
  for (var i = m - 1; i >= 0; i--) {
    for (var j = n - 1; j >= 0; j--) {
      lcs[i][j] = a[i] == b[j]
          ? lcs[i + 1][j + 1] + 1
          : (lcs[i + 1][j] >= lcs[i][j + 1] ? lcs[i + 1][j] : lcs[i][j + 1]);
    }
  }

  final segments = <DiffSegment>[];
  void append(String text, DiffKind kind) {
    if (segments.isNotEmpty && segments.last.kind == kind) {
      final prev = segments.removeLast();
      segments.add(DiffSegment(prev.text + text, kind));
    } else {
      segments.add(DiffSegment(text, kind));
    }
  }

  var i = 0;
  var j = 0;
  while (i < m && j < n) {
    if (a[i] == b[j]) {
      append(a[i], DiffKind.same);
      i++;
      j++;
    } else if (lcs[i + 1][j] >= lcs[i][j + 1]) {
      append(a[i], DiffKind.removed);
      i++;
    } else {
      append(b[j], DiffKind.added);
      j++;
    }
  }
  while (i < m) {
    append(a[i], DiffKind.removed);
    i++;
  }
  while (j < n) {
    append(b[j], DiffKind.added);
    j++;
  }

  return segments;
}
