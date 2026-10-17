// MeritRank 0.12 walks cache + snapshots: the operator documentation and the
// acceptance record must exist and be consistent with the deployed settings.
//
//  * docs/production-deploy.md documents the MR memory budget (walks cache
//    about 1 MB per frame at 10k walks, `MERITRANK_SNAPSHOTS_MB` default 256,
//    process-wide) and the rule "walks cache >= active readers", and quotes
//    the cache size that compose ships. The doc checks look at normalised text
//    (lower case, markdown emphasis removed, line breaks collapsed), so any
//    wording of the same facts passes.
//    The memory-budget and cache-rule facts must each sit in ONE sentence (or
//    bullet / table row) that also names the subject, so a stray "1 MB" or the
//    word "readers" elsewhere does not count.
//  * The constellation journal has a `## UNIT U47 ...` section recording the
//    run settings (heavy viewer V~1000, cache 300, on-demand walks 10000,
//    snapshot staleness 2), cold and warm `mr_mutual_scores` latency, warm FULL
//    p95 (plain and with one write per 100 reads), and the MR process memory.
//  * Warm `mr_mutual_scores` p95 <= 100 ms; warm FULL p95 stays within the
//    frozen budget from the U41 section ("FULL (warm MR)" row).
//
// Journal format (a bullet, a prose line or a table row all work, one fact per
// line, durations as `NN ms` or `N.N s`):
//  * settings: the section names the viewer (`V ~ 1000` / `V≈1,000` / `V=1000`)
//    and each setting with its value (`MERITRANK_WALKS_CACHE_SIZE=300`,
//    `MERITRANK_ON_DEMAND_NUM_WALKS=10000`, `MERITRANK_SNAPSHOT_STALENESS=2`);
//  * cold latency: a line naming `cold` and `mr_mutual_scores` with a duration;
//  * warm latency: a line naming `warm`, `mr_mutual_scores` and `p95`; the
//    figure is the first duration after `p95`. Lines without `p95` (narrative,
//    the old regression) are not judged;
//  * warm FULL: a line naming `FULL`, `warm` and `p95`, same figure rule;
//  * write mix: a line naming `FULL`, the mix (`1 write per 100 reads`,
//    `1 write / 100 reads` or `1:100`) and `p95`, same figure rule;
//  * MR memory: a line naming MR (or MeritRank) and memory (or rss) with a
//    MiB/GiB figure that is a measurement (no env-var names, no `default`).

// Regex literals are kept raw for readability.
// ignore_for_file: unnecessary_raw_strings, missing_whitespace_between_adjacent_strings

@Tags(['repo-files'])
library;

import 'dart:io';

import 'package:test/test.dart';

Directory _repoRoot() {
  var dir = Directory.current.absolute;
  while (!File('${dir.path}/compose.prod.yaml').existsSync()) {
    final parent = dir.parent;
    if (parent.path == dir.path) {
      throw StateError('repo root not found');
    }
    dir = parent;
  }
  return dir;
}

String _read(String relPath) =>
    File('${_repoRoot().path}/$relPath').readAsStringSync();

const _journalPath =
    'docs/plans/issue-235-constellation-interactive-journal.md';

/// All text of the journal sections whose heading starts with [prefix].
String _sections(String prefix) {
  final text = _read(_journalPath);
  final buffer = StringBuffer();
  var from = 0;
  while (true) {
    final start = text.indexOf('## UNIT $prefix', from);
    if (start < 0) {
      break;
    }
    final next = text.indexOf('\n## ', start + 1);
    final end = next < 0 ? text.length : next;
    buffer.writeln(text.substring(start, end));
    from = end;
  }
  return buffer.toString();
}

/// Lower case, no markdown emphasis/backticks, whitespace collapsed.
String _normalise(String text) => text
    .toLowerCase()
    .replaceAll(RegExp(r'[`*]'), '')
    .replaceAll(RegExp(r'\s+'), ' ');

String _squash(String text) =>
    text.toLowerCase().replaceAll(RegExp('[^a-z0-9]'), '');

/// Doc text as lower-case sentences: bullets, table rows and paragraphs are
/// separate, then split at sentence ends; emphasis and backticks removed.
List<String> _sentences(String doc) => [
  for (final chunk
      in doc
          .toLowerCase()
          .replaceAll(RegExp(r'[`*]'), '')
          .split(RegExp(r'\n\s*\n|\n(?=\s*([-+]|\d+\.|\|))')))
    for (final sentence in chunk.split(RegExp(r'(?<=[.!?])\s+')))
      sentence.replaceAll(RegExp(r'\s+'), ' ').trim(),
];

final _duration = RegExp(r'(?<![\w.])(\d+(?:\.\d+)?)\s*(ms|s)\b');

/// Durations on [line], in milliseconds, in reading order.
List<double> _durationsMs(String line) => [
  for (final m in _duration.allMatches(line))
    double.parse(m.group(1)!) * (m.group(2) == 's' ? 1000 : 1),
];

/// The first duration after `p95` on [line]; null when the line has no `p95`
/// or no duration after it.
double? _p95Ms(String line) {
  final at = line.toLowerCase().indexOf('p95');
  if (at < 0) {
    return null;
  }
  final after = _durationsMs(line.substring(at + 3));
  return after.isEmpty ? null : after.first;
}

/// Lines of [section] whose squashed text contains every word of [words]
/// and (when given) satisfies [where].
Iterable<String> _lines(
  String section,
  List<String> words, {
  bool Function(String line)? where,
}) => section.split('\n').where((line) {
  final squashed = _squash(line);
  return words.every((w) => squashed.contains(_squash(w))) &&
      (where?.call(line) ?? true);
});

final _writeMix = RegExp(
  r'(\b(1|one)\s+(write|mutation)s?\s*(per|/|every|:)\s*100\b)|'
  r'(\b1\s*:\s*100\b)',
  caseSensitive: false,
);

bool _isWriteMix(String line) => _writeMix.hasMatch(line);

void main() {
  group('production deploy doc, MeritRank memory budget', () {
    late String doc;
    late String text;

    setUp(() {
      doc = _read('docs/production-deploy.md');
      text = _normalise(doc);
    });

    test('names the walks cache setting and the value compose ships', () {
      final shipped = RegExp(
        r'MERITRANK_WALKS_CACHE_SIZE=(\d+)',
      ).firstMatch(_read('compose.prod.yaml'))!.group(1)!;
      expect(doc, contains('MERITRANK_WALKS_CACHE_SIZE'));
      expect(
        RegExp('MERITRANK_WALKS_CACHE_SIZE\\D{0,40}$shipped\\b').hasMatch(doc),
        isTrue,
        reason: 'doc does not quote the shipped cache size $shipped',
      );
    });

    test('states the walks cache costs about 1 MB per frame at 10k walks', () {
      final sentences = _sentences(doc).where(
        (t) =>
            RegExp(r'walks[ _-]?cache').hasMatch(t) &&
            RegExp(r'10\s?k\b|10[, ]?000').hasMatch(t) &&
            RegExp(
              r'\b1\s*(mb|mib)\b[^.]{0,40}(\bper\b|\beach\b|\bevery\b|/)'
              r'\s*(cached\s+)?(walks[ -]cache\s+)?(frame|reader)|'
              r'\b(each|every|per)\s+(cached\s+)?(walks[ -]cache\s+)?(frame|reader)\b'
              r'[^.]{0,40}\b1\s*(mb|mib)\b',
            ).hasMatch(t),
      );
      expect(
        sentences,
        isNotEmpty,
        reason:
            'no sentence ties the walks cache, 10k walks and "1 MB per frame"',
      );
      expect(doc, contains('MERITRANK_ON_DEMAND_NUM_WALKS'));
    });

    test('documents the process-wide snapshot budget and its default', () {
      const setting = 'meritrank_snapshots_mb';
      final starts = [
        for (final m in RegExp(setting).allMatches(text)) m.start,
      ];
      expect(starts, isNotEmpty, reason: 'MERITRANK_SNAPSHOTS_MB missing');
      final documented = starts.any((i) {
        final around = text.substring(
          (i - 200).clamp(0, text.length),
          (i + 400).clamp(0, text.length),
        );
        return around.contains('256') && around.contains('process');
      });
      expect(
        documented,
        isTrue,
        reason: 'snapshot budget needs its 256 default and "process-wide"',
      );
    });

    test(
      'states the rule that the walks cache must hold at least the active '
      'readers',
      () {
        const cache = r'(walks[ _-]?cache|meritrank_walks_cache_size)';
        const bound =
            r'(>=|≥|at least|no (smaller|lower|less|fewer) than|'
            r'not (be )?(lower|below|smaller|less|under|fewer) than|'
            r'(never|must not) (be )?(lower|below|smaller) than|must (cover|hold|fit|exceed))';
        const readers = r'active readers?';
        final rule = RegExp(
          '$cache[^.]{0,80}$bound[^.]{0,60}$readers|'
          '$readers[^.]{0,60}must\\s+(fit|be (covered|held))[^.]{0,40}$cache',
        );
        expect(
          _sentences(doc).where(rule.hasMatch),
          isNotEmpty,
          reason: 'no sentence states "walks cache >= active readers"',
        );
      },
    );
  });

  group('acceptance record in the constellation journal', () {
    late String section;

    setUp(() {
      section = _sections('U47');
      expect(section, isNotEmpty, reason: 'journal has no U47 section');
    });

    test('records the run settings and the heavy viewer', () {
      final text = section.toLowerCase();
      expect(
        RegExp(r'\bv\s*(≈|~|=|about)?\s*1[, ]?000\b').hasMatch(text),
        isTrue,
        reason: 'run does not name the V~1000 heavy viewer',
      );
      for (final setting in const [
        r'meritrank_walks_cache_size\D{0,4}300\b',
        r'meritrank_on_demand_num_walks\D{0,4}10[, ]?000\b',
        r'meritrank_snapshot_staleness\D{0,4}2\b',
      ]) {
        expect(
          RegExp(setting).hasMatch(text),
          isTrue,
          reason: 'run does not record $setting',
        );
      }
    });

    test('records cold and warm mr_mutual_scores latency', () {
      final cold = _lines(
        section,
        ['cold', 'mr_mutual_scores'],
      ).where((l) => _durationsMs(l).isNotEmpty);
      expect(cold, isNotEmpty, reason: 'no cold mr_mutual_scores latency');
      final warm = _lines(
        section,
        ['warm', 'mr_mutual_scores', 'p95'],
      ).where((l) => _p95Ms(l) != null);
      expect(warm, isNotEmpty, reason: 'no warm mr_mutual_scores p95');
    });

    test('warm mr_mutual_scores p95 is at most 100 ms', () {
      final warm = _lines(
        section,
        ['warm', 'mr_mutual_scores', 'p95'],
      ).map(_p95Ms).whereType<double>().toList();
      expect(warm, isNotEmpty, reason: 'no warm mr_mutual_scores p95');
      for (final p95 in warm) {
        expect(p95, lessThanOrEqualTo(100));
      }
    });

    double frozenFullWarmP95() {
      final rows = _lines(
        _sections('U41'),
        ['full (warm mr)'],
        where: (l) => _durationsMs(l).length >= 2,
      );
      expect(rows, isNotEmpty, reason: 'U41 has no frozen FULL warm budget');
      // Row shape: | FULL (warm MR) | <p50> ms | <p95> ms | ...
      return _durationsMs(rows.first)[1];
    }

    test('warm FULL p95 is within the frozen budget', () {
      final frozen = frozenFullWarmP95();
      final runs = _lines(
        section,
        ['full', 'warm', 'p95'],
        where: (l) => !_isWriteMix(l),
      ).map(_p95Ms).whereType<double>().toList();
      expect(runs, isNotEmpty, reason: 'no warm FULL p95 figure');
      for (final p95 in runs) {
        expect(p95, lessThanOrEqualTo(frozen));
      }
    });

    test('warm FULL p95 with one write per 100 reads is within the budget', () {
      final frozen = frozenFullWarmP95();
      final mixed = _lines(
        section,
        ['full', 'p95'],
        where: _isWriteMix,
      ).map(_p95Ms).whereType<double>().toList();
      expect(
        mixed,
        isNotEmpty,
        reason: 'no FULL latency line tied to a run with 1 write per 100 reads',
      );
      for (final p95 in mixed) {
        expect(p95, lessThanOrEqualTo(frozen));
      }
    });

    test('records the MR process memory of the run in MiB', () {
      final memory = RegExp(
        r'(\d+(?:\.\d+)?)\s*(mib|gib)\b',
        caseSensitive: false,
      );
      final figures = <double>[];
      for (final line in section.split('\n')) {
        final lower = line.toLowerCase();
        final namesMr = RegExp(r'\bmr\b|meritrank').hasMatch(lower);
        final namesMemory = RegExp(r'memory|\brss\b|\bmem\b').hasMatch(lower);
        final isConfig =
            line.contains('MERITRANK_') ||
            lower.contains('default') ||
            lower.contains('budget');
        if (!namesMr || !namesMemory || isConfig) {
          continue;
        }
        for (final m in memory.allMatches(line)) {
          final value = double.parse(m.group(1)!);
          figures.add(
            m.group(2)!.toLowerCase() == 'gib' ? value * 1024 : value,
          );
        }
      }
      expect(
        figures.any((mib) => mib >= 64),
        isTrue,
        reason: 'no measured MR memory figure (MR + memory/rss + MiB)',
      );
    });
  });
}
