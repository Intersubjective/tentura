// The constellation journal must carry the server perf baseline (FULL,
// ANCHORS, upsert and delete, cold and warm, measured on MeritRank 0.12 with
// enough repetitions for a p95 with an uncertainty estimate) and the
// calibrated, frozen budgets that replace the proposed ARCH §7.6 targets.
//
// Expected journal shape: one or more `## UNIT U41 ...` sections.
//  * Baseline tables name the operation (as a word, so `person upsert` or
//    `delete (no visibility check)` count) and give p50 and p95 in
//    milliseconds (`12.5 ms`) for cold and warm runs. Cold and warm may be
//    named on the row itself or in the column headers of a one-row-per-
//    operation table. Each operation row carries a p95 uncertainty interval
//    (`± 4 ms`, `(CI 80–95 ms)`, `[80, 95]`).
//  * The methodology states the repetition count and the MeritRank 0.12
//    snapshot build.
//  * Budget tables sit under a "frozen budgets" heading (subheadings belong
//    to it), name the operation with p50 and p95 in milliseconds, differ from
//    the proposed ARCH targets, and quote the measured baseline values they
//    were calibrated from.

import 'dart:io';

import 'package:test/test.dart';

/// Proposed ARCH §7.6 initial targets (p50 ms, p95 ms) the journal calibrates.
const _proposedTargets = <String, (num, num)>{
  '1-op apply': (25, 100),
  '64-op apply': (100, 300),
  'ANCHORS': (40, 150),
  'FULL': (100, 300),
};

/// Fewest repetitions that can support a p95 estimate with an interval.
const _minRepetitions = 30;

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

/// All `## UNIT U41` sections of the journal, joined.
String _u41Sections() {
  final text = File(
    '${_repoRoot().path}/docs/plans/'
    'issue-235-constellation-interactive-journal.md',
  ).readAsStringSync();
  final buffer = StringBuffer();
  var from = 0;
  while (true) {
    final start = text.indexOf('## UNIT U41', from);
    if (start < 0) break;
    final next = text.indexOf('\n## ', start + 1);
    final end = next < 0 ? text.length : next;
    buffer.writeln(text.substring(start, end));
    from = end;
  }
  return buffer.toString();
}

/// A latency cell in milliseconds: a number followed by `ms`, optionally
/// prefixed (`~`, `≤`) and annotated afterwards (`± 4`, `(CI 80-95)`).
final _msCell = RegExp(r'^\s*[~≈<>≤]?\s*\d+(\.\d+)?\s*ms(?![a-z])');

/// Every `<number> ms` quantity in free text.
final _msNumber = RegExp(r'(\d+(?:\.\d+)?)\s*ms(?![a-z])');

/// An uncertainty interval: `± 4`, `CI`, `80–95 ms` or `[80, 95]`.
final _interval = RegExp(
  r'±\s*\d|\bci\b|confidence interval|bootstrap|'
  r'\d+(\.\d+)?\s*[–—-]\s*\d+(\.\d+)?\s*ms|'
  r'\[\s*\d+(\.\d+)?\s*[,;–—-]\s*\d+(\.\d+)?\s*\]',
  caseSensitive: false,
);

/// A markdown table: header rows (before the `---` separator) and body rows,
/// each a list of trimmed cells with the same indexing.
class _Table {
  _Table(this.header, this.body);

  final List<List<String>> header;
  final List<List<String>> body;

  /// Column heading at [index]: all header rows' cells at that index joined.
  String heading(int index) => [
    for (final row in header)
      if (index < row.length) row[index],
  ].join(' ');
}

List<String> _cells(String line) =>
    line.trim().split('|').map((c) => c.trim()).toList();

bool _isSeparator(List<String> cells) {
  final filled = cells.where((c) => c.isNotEmpty).toList();
  return filled.isNotEmpty &&
      filled.every((c) => RegExp(r'^:?-{3,}:?$').hasMatch(c));
}

/// Tables of [text]: maximal runs of lines starting with `|`.
List<_Table> _tables(String text) {
  final tables = <_Table>[];
  var run = <List<String>>[];
  void flush() {
    if (run.isEmpty) return;
    final separator = run.indexWhere(_isSeparator);
    tables.add(
      separator < 0
          ? _Table([], run.toList())
          : _Table(
              run.sublist(0, separator),
              run.sublist(separator + 1),
            ),
    );
    run = [];
  }

  for (final line in text.split('\n')) {
    if (line.trimLeft().startsWith('|')) {
      run.add(_cells(line));
    } else {
      flush();
    }
  }
  flush();
  return tables;
}

/// Number of millisecond cells in [row].
int _msCells(List<String> row) => row.where(_msCell.hasMatch).length;

/// Whether some cell of [row] contains [word] as a whole word, ignoring case.
bool _namesWord(Iterable<String> row, String word) {
  final pattern = RegExp(
    '\\b${RegExp.escape(word)}\\b',
    caseSensitive: false,
  );
  return row.any(pattern.hasMatch);
}

bool _names(List<String> row, Pattern what) =>
    row.any((c) => c.toLowerCase().contains(what));

/// Body rows of [tables] naming [operation] as a word.
Iterable<(_Table, List<String>)> _operationRows(
  List<_Table> tables,
  String operation,
) => [
  for (final table in tables)
    for (final row in table.body)
      if (_namesWord(row, operation)) (table, row),
];

/// Measurement cells for [operation] at [temperature]: the row itself when
/// the row names a temperature, otherwise the row's columns whose headings
/// name the temperature (and, jointly, both p50 and p95).
List<List<String>> _measurements(
  List<_Table> tables,
  String operation,
  String temperature,
) {
  final result = <List<String>>[];
  for (final (table, row) in _operationRows(tables, operation)) {
    final rowTemperatures = ['cold', 'warm'].where((t) => _namesWord(row, t));
    if (rowTemperatures.isNotEmpty) {
      if (rowTemperatures.contains(temperature)) result.add(row);
      continue;
    }
    final columns = [
      for (var i = 0; i < row.length; i++)
        if (_namesWord([table.heading(i)], temperature)) i,
    ];
    final headings = columns.map(table.heading).join(' ').toLowerCase();
    if (headings.contains('p50') && headings.contains('p95')) {
      result.add([for (final i in columns) row[i]]);
    }
  }
  return result;
}

/// Heading of the frozen budgets and everything below it up to the next
/// heading of the same or a higher level.
({int start, int end})? _frozenBudgetsRange(String section) {
  final start = RegExp(
    r'^#{2,6}[^\n]*frozen[^\n]*budget|^#{2,6}[^\n]*budget[^\n]*frozen',
    caseSensitive: false,
    multiLine: true,
  ).firstMatch(section);
  if (start == null) return null;
  final level = RegExp('#+').firstMatch(start.group(0)!)!.group(0)!.length;
  final next = RegExp(
    '^#{1,$level} ',
    multiLine: true,
  ).firstMatch(section.substring(start.end));
  return (
    start: start.start,
    end: next == null ? section.length : start.end + next.start,
  );
}

num _number(String cell) =>
    num.parse(RegExp(r'\d+(\.\d+)?').firstMatch(cell)!.group(0)!);

void main() {
  late String section;
  late String baseline;
  late String budgets;

  setUpAll(() {
    section = _u41Sections();
    final range = _frozenBudgetsRange(section);
    budgets = range == null ? '' : section.substring(range.start, range.end);
    baseline = range == null
        ? section
        : section.substring(0, range.start) + section.substring(range.end);
  });

  test('journal has a server perf baseline section', () {
    expect(section, isNotEmpty, reason: 'journal has no U41 section');
  });

  group('baseline numbers', () {
    for (final operation in ['FULL', 'ANCHORS', 'upsert', 'delete']) {
      for (final temperature in ['cold', 'warm']) {
        test('$operation $temperature has p50 and p95 in ms', () {
          final measurements = _measurements(
            _tables(baseline),
            operation,
            temperature,
          );
          expect(
            measurements,
            isNotEmpty,
            reason:
                'no table row names $operation with "$temperature" on the row '
                'or in p50/p95 column headings',
          );
          expect(
            measurements.any((cells) => _msCells(cells) >= 2),
            isTrue,
            reason: 'no $operation/$temperature measurement has p50 and p95 '
                'in ms',
          );
        });
      }

      test('$operation p95 carries an uncertainty interval', () {
        final rows = _operationRows(_tables(baseline), operation);
        expect(rows, isNotEmpty, reason: 'no baseline row names $operation');
        expect(
          rows.any((r) => _interval.hasMatch(r.$2.join(' | '))),
          isTrue,
          reason: 'no $operation row has a ±, CI or [lo, hi] interval',
        );
      });
    }

    test('records that the baseline ran on the MeritRank 0.12 snapshots', () {
      final lower = baseline.toLowerCase();
      expect(lower, matches(RegExp(r'meritrank[^\n]{0,60}0\.12')));
      expect(lower, contains('snapshot'));
    });

    test('states a repetition count large enough for a p95', () {
      final counts = [
        for (final m in RegExp(
          r'(\d+)\s*(?:repetitions|reps|samples|runs|iterations)\b|'
          r'\b(?:n|reps|repetitions|samples)\s*[=:]\s*(\d+)',
          caseSensitive: false,
        ).allMatches(baseline))
          int.parse(m.group(1) ?? m.group(2)!),
      ];
      expect(counts, isNotEmpty, reason: 'no repetition count is stated');
      expect(
        counts.reduce((a, b) => a > b ? a : b),
        greaterThanOrEqualTo(_minRepetitions),
        reason: 'fewer than $_minRepetitions repetitions cannot support a p95',
      );
    });

    test('names the method behind the p95 uncertainty', () {
      expect(
        baseline.toLowerCase(),
        matches(
          RegExp(
            'bootstrap|confidence interval|standard error|order.statistic',
          ),
        ),
      );
    });

    test('declares the reference machine', () {
      expect(
        section.toLowerCase(),
        matches(RegExp('reference (machine|hardware|host)')),
      );
    });
  });

  group('calibrated frozen budgets', () {
    late List<_Table> budgetTables;

    setUpAll(() {
      budgetTables = _tables(budgets);
    });

    Iterable<List<String>> budgetRows(String operation) => [
      for (final table in budgetTables)
        for (final row in table.body)
          if (_names(row, operation.toLowerCase())) row,
    ];

    test('have a heading naming frozen budgets', () {
      expect(
        budgets,
        isNotEmpty,
        reason: 'no heading names the frozen (calibrated) budgets',
      );
    });

    test('cite the ARCH §7.6 targets they calibrate', () {
      expect(budgets, contains('§7.6'));
    });

    for (final operation in _proposedTargets.keys) {
      test('$operation has a p50 and p95 budget in ms', () {
        final rows = budgetRows(operation);
        expect(
          rows,
          isNotEmpty,
          reason: 'no frozen budget row names $operation',
        );
        expect(
          rows.any((r) => _msCells(r) >= 2),
          isTrue,
          reason: '$operation has no p50 and p95 budget in ms',
        );
      });
    }

    test('include the cursor-hold p95 budget', () {
      final rows = [
        for (final table in budgetTables)
          for (final row in table.body)
            if (_names(row, RegExp('cursor.?hold'))) row,
      ];
      expect(rows, isNotEmpty, reason: 'no cursor-hold budget row');
      expect(
        rows.any((r) => _msCells(r) >= 1),
        isTrue,
        reason: 'cursor-hold budget has no p95 in ms',
      );
    });

    test('state that the budgets are frozen before optimisation', () {
      expect(budgets.toLowerCase(), contains('frozen'));
      expect(budgets.toLowerCase(), contains('optimi'));
    });

    test('differ from the proposed ARCH §7.6 targets', () {
      final calibrated = <String>{};
      for (final entry in _proposedTargets.entries) {
        for (final row in budgetRows(entry.key)) {
          final ms = row.where(_msCell.hasMatch).toList();
          if (ms.length < 2) continue;
          if ((_number(ms[0]), _number(ms[1])) != entry.value) {
            calibrated.add(entry.key);
          }
        }
      }
      expect(
        calibrated.length,
        greaterThanOrEqualTo(2),
        reason:
            'budgets repeat the proposed §7.6 table; fewer than two of '
            '${_proposedTargets.keys.join(', ')} were changed by calibration',
      );
    });

    test('quote the measured baseline values they were calibrated from', () {
      final proposed = {
        for (final (p50, p95) in _proposedTargets.values) ...[p50, p95],
        50, // cursor-hold p95
      };
      final measured = <num>{
        for (final operation in ['FULL', 'ANCHORS', 'upsert', 'delete'])
          for (final (_, row) in _operationRows(_tables(baseline), operation))
            for (final m in _msNumber.allMatches(row.join(' | ')))
              num.parse(m.group(1)!),
      }..removeAll(proposed);
      final quoted = {
        for (final m in _msNumber.allMatches(budgets)) num.parse(m.group(1)!),
      };
      expect(measured, isNotEmpty, reason: 'no measured baseline values');
      expect(
        quoted.intersection(measured),
        isNotEmpty,
        reason:
            'no frozen-budget text quotes a measured baseline value (in ms), '
            'so the budgets are not tied to the baseline',
      );
      expect(budgets.toLowerCase(), contains('baseline'));
      expect(budgets.toLowerCase(), contains('calibrat'));
    });
  });
}
