// tentura-bzw8: tests must not read trust_context_config, which m0202 drops,
// and schema_baseline_pg_test must pass on a migrated database.

import 'dart:convert';
import 'dart:io';

import 'package:test/test.dart';

import '../support/m0202_dropped_trust_sql_usage.dart';

const _baselineTestPath = 'test/data/database/schema_baseline_pg_test.dart';
const _seedTestName = 'the baseline seeds the rows the replaced chain seeded';
const _droppedTable = 'trust_context_config';

/// Files that may name the table in SQL: this guard (sample SQL / messages).
const _allowedFiles = {
  'test/architecture/tentura_bzw8_baseline_seed_dropped_config_test.dart',
};

/// Reads or writes of the table. `to_regclass('public.x')` absence checks are
/// deliberately not matched: asserting the table is gone is the right
/// post-m0202 assertion.
final _tableUsage = RegExp(
  '\\b(FROM|INTO|JOIN|UPDATE|TRUNCATE)\\s+(public\\.)?$_droppedTable\\b',
  caseSensitive: false,
);

List<int> _usageLines(String source) {
  final code = stripDartAndSqlComments(source);
  return [
    for (final match in _tableUsage.allMatches(code))
      '\n'.allMatches(code.substring(0, match.start)).length + 1,
  ];
}

/// Source of the test named [name], up to its `skip:` argument.
String _testBody(String source, String name) {
  final start = source.indexOf("'$name'");
  expect(start, isNonNegative, reason: 'test "$name" must still exist');
  final end = source.indexOf('skip: skipReason', start);
  expect(end, greaterThan(start), reason: 'test "$name" must keep its skip');
  return source.substring(start, end);
}

void main() {
  test('m0202 still drops trust_context_config (premise of this guard)', () {
    final migration = File(
      'lib/data/database/migration/m0202.dart',
    ).readAsStringSync();
    expect(
      migration,
      matches(
        RegExp(
          'DROP TABLE IF EXISTS\\s+public\\.$_droppedTable\\b',
          caseSensitive: false,
        ),
      ),
    );
  });

  test('no test reads or writes the dropped trust_context_config table', () {
    final offenders = <String>[];
    for (final entity in Directory('test').listSync(recursive: true)) {
      if (entity is! File || !entity.path.endsWith('.dart')) continue;
      final path = entity.path.replaceAll(r'\', '/');
      if (_allowedFiles.contains(path)) continue;
      for (final line in _usageLines(entity.readAsStringSync())) {
        offenders.add('$path:$line');
      }
    }
    expect(
      offenders,
      isEmpty,
      reason:
          '$_droppedTable was dropped by m0202; these tests fail with 42P01 '
          'on a migrated database. Assert the post-m0202 schema instead.',
    );
  });

  test('the baseline seed test asserts the table is gone', () {
    final body = _testBody(
      File(_baselineTestPath).readAsStringSync(),
      _seedTestName,
    );
    expect(
      body,
      matches(RegExp("to_regclass\\s*\\(\\s*'(public\\.)?$_droppedTable'")),
      reason: 'assert the post-m0202 schema (table absent) in the seed test',
    );
  });

  test('the baseline seed test keeps its real seed-row assertions', () {
    final body = stripDartAndSqlComments(
      _testBody(File(_baselineTestPath).readAsStringSync(), _seedTestName),
    );
    for (final table in ['mr_publish_epoch', 'trust_policy']) {
      expect(
        body,
        matches(
          RegExp(
            'count\\(\\*\\)(::int)?\\s+FROM\\s+public\\.$table\\b'
            '[\\s\\S]*?\\)\\)\\.single\\.single,\\s*1,',
          ),
        ),
        reason: 'the $table row-count expectation (== 1) must be preserved',
      );
    }
  });

  test(
    'schema_baseline_pg_test runs and passes on a migrated database',
    () async {
      final result = await Process.run(Platform.resolvedExecutable, [
        'test',
        _baselineTestPath,
        '--tags',
        'mr',
        '-j',
        '1',
        '--reporter',
        'json',
      ]);
      final names = <int, String>{};
      final outcomes = <String, String>{};
      for (final line in const LineSplitter().convert(
        result.stdout as String,
      )) {
        if (!line.startsWith('{')) continue;
        final event = jsonDecode(line) as Map<String, dynamic>;
        if (event['type'] == 'testStart') {
          final test = event['test'] as Map<String, dynamic>;
          names[test['id'] as int] = test['name'] as String;
        } else if (event['type'] == 'testDone' && event['hidden'] != true) {
          final id = event['testID'] as int;
          outcomes[names[id] ?? '#$id'] = event['skipped'] == true
              ? 'skipped'
              : event['result'] as String;
        }
      }
      final seedOutcome = outcomes.entries
          .where((e) => e.key.endsWith(_seedTestName))
          .map((e) => e.value)
          .toList();
      expect(
        seedOutcome,
        ['success'],
        reason:
            'seed-rows test must run (Postgres admin reachable) and succeed '
            'on a migrated DB; outcomes: $outcomes\n${result.stderr}',
      );
      expect(result.exitCode, 0, reason: 'outcomes: $outcomes');
    },
    timeout: const Timeout(Duration(minutes: 5)),
  );
}
