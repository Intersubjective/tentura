@Tags(['repo-files'])
library;

import 'dart:io';

import 'package:postgres/postgres.dart';
import 'package:test/test.dart';

import '../support/disposable_pg_target.dart';

/// Pg-tagged suites that must run on a disposable, freshly migrated database.
const _disposableSuites = <String, int>{
  'test/data/repository/room_message_reply_readback_pg_test.dart': 11,
  'test/data/repository/room_message_snapshot_lookup_test.dart': 7,
};

/// Calls that open a database connection or pool.
final _connectionCall = RegExp(
  r'(TenturaDb|PgDatabase|Connection\.open|Connection\.openFromUrl|'
  r'Pool\.withEndpoints|Pool\.withUrl|Pool\.withSettings)\(\s*'
  r'([A-Za-z_][\w.]*(?:\(\))?)',
);

/// A directly constructed `Env(...)` is how a test builds an ambient
/// (POSTGRES_* from the process environment) database configuration.
///
/// `adminEnv = Env(...)` is exempt: a target's admin connection has no
/// database of its own by design.
final _envConstructor = RegExp(r'(?<![\w.])(?<!adminEnv\s=\s)Env\(');

/// Argument text of the call whose opening parenthesis is at [open].
String _callArguments(String code, int open) {
  var depth = 0;
  for (var i = open; i < code.length; i++) {
    final c = code[i];
    if (c == '(') depth++;
    if (c == ')' && --depth == 0) return code.substring(open + 1, i);
  }
  return code.substring(open + 1);
}

/// An `Env(...)` is ambient when it configures a connection without naming
/// its database, or takes the database name from the process environment. Any
/// other named database (a target's `pgDatabase`, a literal) is fine, as is an
/// `Env` that configures no connection at all.
bool _isAmbientEnv(String arguments) {
  final database = RegExp(
    r'pgDatabase:\s*([^,]+),',
  ).firstMatch('$arguments,')?.group(1);
  if (database != null) {
    return database.contains('Platform.environment') ||
        database.contains('fromEnvironment');
  }
  return RegExp(r'\bpg(Host|Port|Username|Password):').hasMatch(arguments);
}

/// Roots a connection argument may start from: a disposable target, or one of
/// the target's own env/endpoint members.
final _targetDerived = RegExp(
  r'^(\w*[tT]arget\w*\.|adminEnv\.|templateEnv\.|databaseEnv\.|'
  r'session\.|fixture\.)',
);

/// A suite that provisions a disposable target builds its connection
/// arguments (`env`, `endpoint`, ...) from it; the connection-call check can
/// only judge suites that do not.
final _usesDisposableTarget = RegExp(
  r'DisposablePgTarget|setUpDisposablePgWriter',
);

/// A suite that connects to a server it starts itself builds its own
/// `Endpoint(host: ...)` and never reads the ambient `Platform.environment`.
final _buildsOwnEndpoint = RegExp(r'Endpoint\(\s*host:');

bool _connectsToPrivateServer(String code) =>
    _buildsOwnEndpoint.hasMatch(code) && !code.contains('Platform.environment');

String _withoutComments(String source) =>
    source.split('\n').where((l) => !l.trimLeft().startsWith('//')).join('\n');

/// True when the library header tags the suite `pg` in any supported form:
/// single/double quotes, `const` list, multi-line `@Tags(...)`.
bool _isPgTagged(String source) {
  final tags = RegExp(
    r'@Tags\(\s*(?:const\s*)?\[([^\]]*)\]\s*,?\s*\)',
    dotAll: true,
  ).firstMatch(source);
  return tags != null && RegExp('[\'"]pg[\'"]').hasMatch(tags.group(1)!);
}

/// Connection openings in [source] that are not derived from a disposable
/// target, plus any direct `Env(...)` construction in the same file.
///
/// Covers the project's pg-test patterns: `TenturaDb(...)`, drift
/// `PgDatabase(...)`, `package:postgres` `Connection.open*` / `Pool.*`, and
/// hand-built `Env(...)`. A helper that hides a connection behind another API
/// must be added to [_connectionCall].
List<String> _ambientDbOpens(String source) {
  final code = _withoutComments(source);
  return [
    for (final m in _connectionCall.allMatches(code))
      if (!_usesDisposableTarget.hasMatch(code) &&
          !_connectsToPrivateServer(code) &&
          !_targetDerived.hasMatch(m.group(2)!) &&
          !(m.group(2)!.startsWith('envWith') &&
              code.contains('target.databaseEnv')) &&
          !RegExp(r'^(target|\w*Target)$').hasMatch(m.group(2)!))
        m.group(0)!.replaceAll(RegExp(r'\s+'), ' '),
    if (_envConstructor
        .allMatches(code)
        .any((m) => _isAmbientEnv(_callArguments(code, m.end - 1))))
      'Env(',
  ];
}

Iterable<File> _testFiles() => Directory('test')
    .listSync(recursive: true)
    .whereType<File>()
    .where((f) => f.path.endsWith('.dart'));

Future<ProcessResult> _runSuite(String path, Map<String, String?> overrides) {
  final env = Map<String, String>.of(Platform.environment);
  overrides.forEach((k, v) => v == null ? env.remove(k) : env[k] = v);
  return Process.run(
    Platform.resolvedExecutable,
    ['test', path, '--reporter', 'expanded'],
    environment: env,
    includeParentEnvironment: false,
  );
}

/// Final reporter line must show every case ran and passed: `+N: All tests
/// passed!` with N at least [expected] and no skipped (`~`) segment.
void _expectAllCasesRan(ProcessResult result, int expected) {
  final output = '${result.stdout}${result.stderr}';
  final done = RegExp(r'\+(\d+): All tests passed!').allMatches(output);
  expect(done, isNotEmpty, reason: output);
  expect(int.parse(done.last.group(1)!), greaterThanOrEqualTo(expected));
  expect(output, isNot(contains('~')), reason: 'cases were skipped');
  expect(result.exitCode, 0);
}

Future<void> _withAdminDatabase(
  String name,
  Future<void> Function(Connection admin, DisposablePgTarget target) body, {
  required bool create,
}) async {
  final target = DisposablePgTarget.fromNamedEnvironment(
    envVarName: 'TENTURA_STALE_SHARED_DB_PROBE',
    defaultNamePrefix: name,
  );
  final admin = await Connection.open(
    target.adminEnv.pgEndpoint,
    settings: target.adminEnv.pgEndpointSettings,
  );
  if (create) {
    await admin.execute('CREATE DATABASE "${target.databaseName}"');
  }
  try {
    await body(admin, target);
  } finally {
    await admin.execute(
      'DROP DATABASE IF EXISTS "${target.databaseName}" WITH (FORCE)',
    );
    await admin.close();
  }
}

void main() {
  _disposableSuites.forEach((path, expectedCases) {
    final name = path.split('/').last;

    test('$name opens every connection through its disposable target', () {
      final source = File(path).readAsStringSync();
      expect(_isPgTagged(source), isTrue);
      expect(_ambientDbOpens(source), isEmpty);
      expect(source, contains('setUpDisposablePgWriter'));
      expect(source, contains('TenturaDb(target.databaseEnv)'));
    });

    group('$name when the ambient database is unusable', () {
      test(
        'runs every case with POSTGRES_DBNAME unset',
        () async {
          final result = await _runSuite(path, {'POSTGRES_DBNAME': null});
          _expectAllCasesRan(result, expectedCases);
        },
        tags: ['pg'],
        timeout: const Timeout(Duration(minutes: 5)),
      );

      test(
        'runs every case when POSTGRES_DBNAME is an unmigrated database',
        () async {
          await _withAdminDatabase('tentura_test_stale_shared', (
            _,
            target,
          ) async {
            final result = await _runSuite(path, {
              'POSTGRES_DBNAME': target.databaseName,
            });
            _expectAllCasesRan(result, expectedCases);
          }, create: true);
        },
        tags: ['pg'],
        timeout: const Timeout(Duration(minutes: 5)),
      );

      test(
        'runs every case when POSTGRES_DBNAME names a missing database',
        () async {
          await _withAdminDatabase('tentura_test_missing_shared', (
            _,
            target,
          ) async {
            final result = await _runSuite(path, {
              'POSTGRES_DBNAME': target.databaseName,
            });
            _expectAllCasesRan(result, expectedCases);
          }, create: false);
        },
        tags: ['pg'],
        timeout: const Timeout(Duration(minutes: 5)),
      );
    });
  });

  test(
    'no pg-tagged test opens a database that is not a disposable target',
    () {
      final offenders = <String>[
        for (final f in _testFiles())
          if (_isPgTagged(f.readAsStringSync()) &&
              _ambientDbOpens(f.readAsStringSync()).isNotEmpty)
            f.path,
      ]..sort();
      expect(offenders, isEmpty);
    },
  );
}
