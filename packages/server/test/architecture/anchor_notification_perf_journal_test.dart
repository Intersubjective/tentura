// The constellation journal must record the measured cost of the deferred
// anchor notification triggers (commit latency with and without them,
// transaction-body vs COMMIT latency under concurrent commits, and the
// slow-listener backlog) in a `## UNIT U15 ...` section.
//
// Journal format: one fact per line (bullet, prose line or table row),
// durations as `NN ms` / `N.N ms`, counts as plain numbers.
//  * report: the section names `build/perf/anchor_notification_triggers.json`;
//  * commit latency: a line naming `without` triggers and one naming `with`
//    triggers, each with `p50` or `p95` and a duration;
//  * concurrent commits: a line naming `transaction body` and `p95` with a
//    duration, and a different line naming `COMMIT` and `p95` with a duration;
//  * backlog: a line naming `slow listener` and `backlog` with a count and the
//    drain time in ms.

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

/// All `## UNIT U15` sections of the journal, joined.
String _u15Sections() {
  final text = File(
    '${_repoRoot().path}/docs/plans/'
    'issue-235-constellation-interactive-journal.md',
  ).readAsStringSync();
  final buffer = StringBuffer();
  var from = 0;
  while (true) {
    final start = text.indexOf('## UNIT U15', from);
    if (start < 0) break;
    final next = text.indexOf('\n## ', start + 1);
    final end = next < 0 ? text.length : next;
    buffer.writeln(text.substring(start, end));
    from = end;
  }
  return buffer.toString();
}

final _durationMs = RegExp(r'\d+(?:\.\d+)?\s*ms(?![a-z])');

/// Lines of [section], lower case, markdown emphasis and backticks removed.
List<String> _lines(String section) => [
  for (final line in section.split('\n'))
    line.toLowerCase().replaceAll(RegExp('[*_`]'), ''),
];

Iterable<String> _linesWith(
  List<String> lines,
  List<Pattern> all, {
  bool needsDuration = true,
}) => lines.where(
  (l) =>
      all.every((p) => l.contains(p)) &&
      (!needsDuration || _durationMs.hasMatch(l)),
);

void main() {
  group('journal records the anchor notification trigger cost', () {
    late String section;
    late List<String> lines;

    setUpAll(() {
      section = _u15Sections();
      lines = _lines(section);
    });

    test('has a U15 section naming the perf report it was taken from', () {
      expect(section, isNotEmpty, reason: 'no `## UNIT U15` section');
      expect(
        section,
        contains('build/perf/anchor_notification_triggers.json'),
      );
    });

    test('gives commit latency without and with the triggers', () {
      final without = _linesWith(lines, ['without']).where(
        (l) => l.contains('p50') || l.contains('p95'),
      );
      final withTriggers = _linesWith(lines, [
        RegExp(r'\bwith\b(?! ?out)'),
      ]).where((l) => l.contains('p50') || l.contains('p95'));

      expect(without, isNotEmpty, reason: 'latency without the triggers');
      expect(withTriggers, isNotEmpty, reason: 'latency with the triggers');
    });

    test('gives transaction-body and COMMIT p95 under concurrent commits '
        'on separate lines', () {
      final body = _linesWith(lines, ['transaction body', 'p95']).toList();
      final commit = _linesWith(lines, [
        'commit',
        'p95',
      ]).where((l) => !l.contains('transaction body')).toList();

      expect(body, isNotEmpty, reason: 'transaction-body p95');
      expect(commit, isNotEmpty, reason: 'COMMIT p95 on its own line');
    });

    test('gives the slow-listener backlog and its drain time', () {
      final backlog = _linesWith(lines, [
        'slow listener',
        'backlog',
      ]).where((l) => RegExp(r'\d').hasMatch(l));

      expect(backlog, isNotEmpty, reason: 'slow-listener backlog count');
    });
  });
}
