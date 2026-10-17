// The functional PG suite must also run with a single pooled connection, so a
// scope that re-enters its own lease hangs or fails deterministically instead
// of passing on a spare connection. Tests that deliberately need several
// connections opt out with the `multi-connection` tag.

@Tags(['repo-files'])
library;

import 'dart:io';

import 'package:test/test.dart';

const _overrideVar = 'TENTURA_TEST_PG_POOL_SIZE';
const _multiTag = 'multi-connection';

final _repoRoot = Directory('../..').absolute;

/// The pg case branch of the CI job, as logical commands: line continuations
/// joined, comments and blank lines dropped.
List<String> _pgJobCommands() {
  final text = File(
    '${_repoRoot.path}/.github/workflows/pipeline.yml',
  ).readAsStringSync();
  final start = text.indexOf(RegExp(r'^\s*pg\)\s*$', multiLine: true));
  expect(start, isNonNegative, reason: 'pg case branch not found');
  final end = text.indexOf(
    RegExp(r'^\s*client-a\)\s*$', multiLine: true),
    start,
  );
  final joined = text.substring(start, end).replaceAll(RegExp(r'\\\s*\n'), ' ');
  return [
    for (final line in joined.split('\n'))
      if (line.trim().isNotEmpty && !line.trim().startsWith('#')) line.trim(),
  ];
}

List<String> _dartTestCommands() => [
  for (final c in _pgJobCommands())
    if (c.contains('dart test')) c,
];

/// Value of `--[option] value` / `--[option]=value` in [command], unquoted.
String? _optionValue(String command, String option) {
  final match = RegExp(
    '--$option(?:=|\\s+)("[^"]*"|\'[^\']*\'|\\S+)',
  ).firstMatch(command);
  return match?.group(1)?.replaceAll(RegExp('^["\']|["\']\$'), '');
}

Iterable<File> _dartFilesUnderTest() => Directory('test')
    .listSync(recursive: true)
    .whereType<File>()
    .where(
      (f) =>
          f.path.endsWith('.dart') &&
          !f.path.contains('.dart_tool') &&
          !f.path.endsWith('.mocks.dart'),
    );

/// Probes and tests of the override itself read the ambient pool size on
/// purpose.
bool _isPoolOverrideSupport(String path) =>
    path.contains('disposable_pg_target') ||
    path.contains('single_connection_cross_handle_probe');

/// True when the source sizes a pool by anything other than a literal 1:
/// `maxConnectionCount:`, `pgMaxConnectionCount` or `POSTGRES_MAXCONN`.
bool _sizesPoolAboveOne(String source) {
  final sizing = RegExp(r'maxConnectionCount:\s*([^,)\s]+)');
  return sizing.allMatches(source).any((m) => m.group(1) != '1') ||
      source.contains('pgMaxConnectionCount') ||
      source.contains('POSTGRES_MAXCONN');
}

final _tagDeclarations = [
  RegExp(r'@Tags\(\[([^\]]*)\]\)'),
  RegExp(r"tags:\s*(?:const\s*)?(\[[^\]]*\]|'[^']*')"),
];

/// File-, group- and test-level `pg` tag declarations lacking
/// `multi-connection`.
List<String> _untaggedPgDeclarations(String path, String source) => [
  for (final pattern in _tagDeclarations)
    for (final m in pattern.allMatches(source))
      if (m.group(1)!.contains("'pg'") && !m.group(1)!.contains("'$_multiTag'"))
        '$path: ${m.group(0)}',
];

void main() {
  group('pool-size-1 CI mode', () {
    test('dart_test.yaml declares the multi-connection tag', () {
      final yaml = File('dart_test.yaml').readAsStringSync();
      expect(yaml, matches(RegExp('^  $_multiTag:', multiLine: true)));
    });

    test('one dart test command runs the pg suite with the pool override and '
        'without the multi-connection tests', () {
      final pooled = [
        for (final c in _dartTestCommands())
          if (c.contains('$_overrideVar=1')) c,
      ];
      expect(pooled, hasLength(1), reason: 'exactly one pool-size-1 run');
      final command = pooled.single;
      expect(_optionValue(command, 'tags'), contains('pg'));
      final excluded = _optionValue(command, 'exclude-tags') ?? '';
      expect(excluded, contains(_multiTag));
      expect(excluded, contains('mr'), reason: 'still serial-only elsewhere');
      expect(_optionValue(command, 'tags'), isNot(contains(_multiTag)));
    });

    test('a separate dart test command, without the override, runs the '
        'multi-connection tests with the normal pool', () {
      final normal = [
        for (final c in _dartTestCommands())
          if (!c.contains(_overrideVar) &&
              (_optionValue(c, 'tags') ?? '').contains(_multiTag))
            c,
      ];
      expect(normal, hasLength(1), reason: 'exactly one normal-pool run');
      expect(
        _optionValue(normal.single, 'exclude-tags') ?? '',
        isNot(contains(_multiTag)),
      );
      expect(
        _pgJobCommands().where((c) => c.contains(_overrideVar)),
        hasLength(1),
        reason:
            'the override must be scoped to the pool-size-1 command, '
            'not exported to the normal-pool run',
      );
    });

    test('every pg tag declaration in a test file that sizes its own pool '
        'above one connection also carries the multi-connection tag', () {
      final offenders = <String>[];
      for (final file in _dartFilesUnderTest()) {
        if (!file.path.endsWith('_test.dart')) continue;
        final source = file.readAsStringSync();
        if (!_sizesPoolAboveOne(source)) continue;
        offenders.addAll(_untaggedPgDeclarations(file.path, source));
      }
      expect(offenders, isEmpty);
    });

    test('every pg test consuming a fixture that sizes the pool above one '
        'connection carries the multi-connection tag', () {
      final fixtures = [
        for (final file in _dartFilesUnderTest())
          if (!file.path.endsWith('_test.dart') &&
              !_isPoolOverrideSupport(file.path) &&
              _sizesPoolAboveOne(file.readAsStringSync()))
            file.path.split('/').last,
      ];
      expect(
        fixtures,
        isNotEmpty,
        reason: 'expected at least the perf fixture matrix to size a pool',
      );
      final offenders = <String>[];
      for (final file in _dartFilesUnderTest()) {
        if (!file.path.endsWith('_test.dart')) continue;
        final source = file.readAsStringSync();
        if (!fixtures.any(source.contains)) continue;
        offenders.addAll(_untaggedPgDeclarations(file.path, source));
      }
      expect(offenders, isEmpty);
    });
  });
}
