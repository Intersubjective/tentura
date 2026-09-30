// tentura-0exd: tests must not call SQL objects m0202 dropped.

import 'dart:io';

import 'package:test/test.dart';

/// m0202 drops `trust_apply_source_evidence`, `trust_rebuild_effective_edge`,
/// the `user_trust_source_edge` table and the `trust_evidence_event` table.
/// pg-tagged tests that still use them fail on a migrated database and are
/// invisible to `--exclude-tags pg`, so this guard scans the test sources.
///
/// Only real SQL usage counts: comments and prose (test names, skip reasons)
/// that merely mention an object are fine.
const _droppedFunctions = [
  'trust_apply_source_evidence',
  'trust_rebuild_effective_edge',
];
const _droppedTables = [
  'user_trust_source_edge',
  'trust_evidence_event',
];
const _droppedObjects = [..._droppedFunctions, ..._droppedTables];

/// Files that legitimately use the dropped objects. Kept deliberately narrow:
/// any other test, including any future architecture test, is scanned.
/// - this guard itself (its detector self-tests contain sample SQL);
/// - `m0202_trust_ledger_pg_test` migrates a scratch DB only to m0201 (where
///   the objects still exist) before running m0202;
/// - `tentura_btai_trust_paths_migrated_pg_test` asserts the objects are gone;
/// - `tentura_btai_dropped_trust_sql_test` asserts the objects are absent
///   from production sources and quotes their SQL as forbidden strings.
const _allowedFiles = {
  'test/architecture/tentura_0exd_dropped_trust_sql_in_tests_test.dart',
  'test/data/database/m0202_trust_ledger_pg_test.dart',
  'test/data/repository/tentura_btai_trust_paths_migrated_pg_test.dart',
  'test/architecture/tentura_btai_dropped_trust_sql_test.dart',
};

bool _isSpace(String c) => c == ' ' || c == '\t' || c == '\n' || c == '\r';

/// Blanks comments while keeping every offset and newline, so matches still
/// map to line numbers. Handles Dart `//` and `/* */` comments (only outside
/// string literals) and SQL `--` comments inside string literals (a `--`
/// that starts a token, e.g. `'--tags'`, is not a comment). Inline and
/// trailing comments are covered, not just full-line ones.
String _stripComments(String s) {
  final out = StringBuffer();
  var i = 0;
  String? quote;
  var raw = false;

  // Blanks from [i] up to (not including) the next newline or, inside a
  // string, the closing quote.
  int blankLine(int from) {
    var j = from;
    while (j < s.length && s[j] != '\n') {
      if (quote != null && s.startsWith(quote, j)) break;
      out.write(' ');
      j++;
    }
    return j;
  }

  while (i < s.length) {
    final c = s[i];
    if (quote == null) {
      if (s.startsWith('//', i)) {
        i = blankLine(i);
      } else if (s.startsWith('/*', i)) {
        final end = s.indexOf('*/', i + 2);
        final stop = end == -1 ? s.length : end + 2;
        for (; i < stop; i++) {
          out.write(s[i] == '\n' ? '\n' : ' ');
        }
      } else if (c == "'" || c == '"') {
        raw =
            i > 0 &&
            s[i - 1] == 'r' &&
            (i < 2 || !RegExp(r'\w').hasMatch(s[i - 2]));
        quote = s.startsWith(c * 3, i) ? c * 3 : c;
        out.write(quote);
        i += quote.length;
      } else {
        out.write(c);
        i++;
      }
      continue;
    }
    if (!raw && c == r'\' && i + 1 < s.length) {
      out.write(s.substring(i, i + 2));
      i += 2;
    } else if (s.startsWith(quote, i)) {
      out.write(quote);
      i += quote.length;
      quote = null;
    } else if (quote.length == 1 && c == '\n') {
      out.write(c); // unterminated single-line string: resync
      i++;
      quote = null;
    } else if (s.startsWith('--', i) &&
        (i == 0 ||
            _isSpace(s[i - 1]) ||
            s.startsWith(quote, i - quote.length)) &&
        (i + 2 >= s.length ||
            _isSpace(s[i + 2]) ||
            s.startsWith(quote, i + 2))) {
      i = blankLine(i);
    } else {
      out.write(c);
      i++;
    }
  }
  return out.toString();
}

/// 1-based line numbers where [source] uses [object] as SQL: a function call,
/// a table in a FROM/INTO/JOIN/UPDATE/TABLE/TRUNCATE clause, or a catalog
/// lookup (`to_regclass('public.x')`, `proname = 'x'`, `proname IN ('a','x')`,
/// `table_name = 'x'`). A bare quoted name elsewhere (test description, list
/// of forbidden names) is not SQL usage.
List<int> _sqlUsageLines(String source, String object) {
  final code = _stripComments(source);
  final patterns = [
    RegExp('\\b$object\\s*\\('),
    RegExp(
      '\\b(FROM|INTO|JOIN|UPDATE|TABLE|TRUNCATE)\\s+(public\\.)?$object\\b',
      caseSensitive: false,
    ),
    RegExp(
      "\\bto_reg(class|proc|procedure|type)\\s*\\(\\s*'(public\\.)?$object\\b",
      caseSensitive: false,
    ),
    RegExp(
      '\\b(proname|relname|tablename|table_name|routine_name)\\s*'
      "(=|IN\\s*\\()\\s*(?:'[^']*'\\s*,\\s*)*'(public\\.)?$object'",
      caseSensitive: false,
    ),
  ];
  final lines = <int>{};
  for (final pattern in patterns) {
    for (final match in pattern.allMatches(code)) {
      lines.add('\n'.allMatches(code.substring(0, match.start)).length + 1);
    }
  }
  return lines.toList()..sort();
}

void main() {
  group('tentura-0exd: detector distinguishes SQL usage from mentions', () {
    test('flags calls, table clauses and quoted catalog names', () {
      expect(
        _sqlUsageLines(
          "SELECT trust_apply_source_evidence('personal', \$1)",
          'trust_apply_source_evidence',
        ),
        [1],
      );
      expect(
        _sqlUsageLines(
          'DELETE FROM public.user_trust_source_edge WHERE 1=1',
          'user_trust_source_edge',
        ),
        [1],
      );
      expect(
        _sqlUsageLines(
          "SELECT to_regclass('public.trust_evidence_event')",
          'trust_evidence_event',
        ),
        [1],
      );
    });

    test('flags catalog lookups only in SQL predicates', () {
      expect(
        _sqlUsageLines(
          "WHERE proname IN ('a', 'trust_rebuild_effective_edge')",
          'trust_rebuild_effective_edge',
        ),
        [1],
      );
      expect(
        _sqlUsageLines(
          "WHERE table_name = 'user_trust_source_edge'",
          'user_trust_source_edge',
        ),
        [1],
      );
    });

    test('ignores comments, test names and skip reasons', () {
      const source = '''
// trust_rebuild_effective_edge was dropped by m0202
/// see user_trust_source_edge
/* trust_apply_source_evidence(x) */
test('T-G7: adds zero trust_evidence_event rows', () {});
skipReason = 'user_trust_source_edge missing';
''';
      for (final object in _droppedObjects) {
        expect(_sqlUsageLines(source, object), isEmpty, reason: object);
      }
    });

    test('ignores bare quoted names outside SQL predicates', () {
      const source = '''
const forbidden = ['trust_apply_source_evidence', "user_trust_source_edge"];
test('trust_evidence_event', () {});
final name = 'trust_rebuild_effective_edge';
''';
      for (final object in _droppedObjects) {
        expect(_sqlUsageLines(source, object), isEmpty, reason: object);
      }
    });

    test('ignores inline Dart and trailing SQL comments', () {
      const source = '''
final a = 1; // SELECT trust_apply_source_evidence(1)
final b = 'x'; /* FROM user_trust_source_edge */
final c = \'\'\'
SELECT 1 -- trust_rebuild_effective_edge(a, b)
FROM t -- DELETE FROM public.trust_evidence_event
\'\'\';
final d = 'SELECT 1 -- trust_apply_source_evidence(1)';
''';
      for (final object in _droppedObjects) {
        expect(_sqlUsageLines(source, object), isEmpty, reason: object);
      }
    });

    test('still flags SQL that follows a comment-like token', () {
      const source = '''
final url = 'http://x'; final q = 'SELECT trust_rebuild_effective_edge(1)';
final args = ['--tags', 'DELETE FROM user_trust_source_edge'];
''';
      expect(
        _sqlUsageLines(source, 'trust_rebuild_effective_edge'),
        [1],
      );
      expect(_sqlUsageLines(source, 'user_trust_source_edge'), [2]);
    });
  });

  group('tentura-0exd: tests do not use objects dropped by m0202', () {
    test('m0202 still drops all four objects (premise of this guard)', () {
      final migration = File(
        'lib/data/database/migration/m0202.dart',
      ).readAsStringSync();
      for (final function in _droppedFunctions) {
        expect(
          migration,
          matches(
            RegExp(
              'DROP FUNCTION IF EXISTS\\s+public\\.$function\\s*\\(',
              caseSensitive: false,
            ),
          ),
          reason: 'm0202 must drop function $function',
        );
      }
      for (final table in _droppedTables) {
        expect(
          migration,
          matches(
            RegExp(
              'DROP TABLE IF EXISTS\\s+public\\.$table\\b',
              caseSensitive: false,
            ),
          ),
          reason: 'm0202 must drop table $table',
        );
      }
    });

    for (final object in _droppedObjects) {
      test('test/ does not use $object in SQL', () {
        final offenders = <String>[];
        for (final entity in Directory('test').listSync(recursive: true)) {
          if (entity is! File || !entity.path.endsWith('.dart')) continue;
          final path = entity.path.replaceAll(r'\', '/');
          if (_allowedFiles.contains(path)) continue;
          for (final line in _sqlUsageLines(
            entity.readAsStringSync(),
            object,
          )) {
            offenders.add('$path:$line');
          }
        }
        expect(
          offenders,
          isEmpty,
          reason:
              '$object was dropped by m0202; these tests fail on a migrated '
              'DB. Port them to trust_evidence / user_trust_edge, or delete '
              'them if they only cover the dropped objects.',
        );
      });
    }
  });
}
