@Tags(['repo-files'])
library;

import 'dart:convert';
import 'dart:io';

import 'package:test/test.dart';

/// MeritRank-backed constellation-field repository PostgreSQL suite that the
/// required check must run with `dart test --tags mr -j 1`.
const _mrSuite =
    'test/data/repository/constellation_field_repository_pg_test.dart';

/// Connection-age suite stays on the plain pg slice only (no MeritRank).
const _pgPlainSuite =
    'test/data/repository/constellation_field_connection_age_pg_test.dart';

/// In-repo Alloy required-verification registry entry for this check.
const _verificationRegistryPath = 'scripts/alloy-required-verification-checks.json';
const _verificationRegistryKey = 'tentura-lvsg';

const _probePlainName = '__constellation_field_mr_pg_required_check_probe__';

final _repoRoot = Directory('../..').absolute;
final _serverPackage = Directory.current.absolute;
const _serverPackagePathSuffix = 'packages/server';

Set<String> _declaredTags(File file) {
  final header = file.readAsStringSync().split('library;').first;
  final tags = RegExp(r'@Tags\(\[([^\]]*)\]\)').firstMatch(header);
  if (tags == null) return {};
  return tags
      .group(1)!
      .split(',')
      .map((t) => t.trim().replaceAll("'", ''))
      .where((t) => t.isNotEmpty)
      .toSet();
}

Map<String, Object?> _readRequiredVerificationEntry() {
  final file = File('${_repoRoot.path}/$_verificationRegistryPath');
  expect(
    file.existsSync(),
    isTrue,
    reason:
        'Add $_verificationRegistryPath with a $_verificationRegistryKey '
        'entry recording `dart test --tags mr -j 1` for both suites.',
  );
  final registry = jsonDecode(file.readAsStringSync()) as Map<String, Object?>;
  final entry = registry[_verificationRegistryKey];
  expect(
    entry,
    isNotNull,
    reason: 'Registry must define the required verification check under '
        '$_verificationRegistryKey.',
  );
  return entry! as Map<String, Object?>;
}

List<String> _entryArgv(Map<String, Object?> entry) {
  final argv = entry['argv'];
  expect(argv, isA<List<Object?>>(), reason: 'registry argv must be a JSON array');
  return List<String>.from(argv! as List<Object?>);
}

bool _usesPlainPgExcludeMrSelector(List<String> argv) {
  final tagsIndex = argv.indexOf('--tags');
  if (tagsIndex < 0 || tagsIndex + 1 >= argv.length) {
    return false;
  }
  if (argv[tagsIndex + 1] != 'pg') {
    return false;
  }
  final excludeIndex = argv.indexOf('--exclude-tags');
  return excludeIndex >= 0 &&
      excludeIndex + 1 < argv.length &&
      argv[excludeIndex + 1] == 'mr';
}

Future<Set<String>> _suitePathsSelectedByArgv({
  required String workingDirectory,
  required List<String> argv,
}) async {
  final result = await Process.run(
    Platform.resolvedExecutable,
    [
      ...argv,
      '--reporter',
      'json',
      '--plain-name',
      _probePlainName,
    ],
    workingDirectory: workingDirectory,
  );
  final output = '${result.stdout}${result.stderr}';
  expect(
    output,
    isNot(contains('No tests match the requested tag selectors')),
    reason: output,
  );

  final paths = <String>{};
  for (final line in result.stdout.toString().split('\n')) {
    if (line.isEmpty) continue;
    final dynamic decoded;
    try {
      decoded = jsonDecode(line);
    } on FormatException {
      continue;
    }
    if (decoded is! Map<String, Object?>) continue;
    if (decoded['type'] != 'suite') continue;
    final suite = decoded['suite'];
    if (suite is! Map<String, Object?>) continue;
    final path = suite['path'];
    if (path is String) {
      paths.add(path);
    }
  }
  return paths;
}

void main() {
  test('dart_test.yaml declares the mr tag with serial execution guidance', () {
    final config = File('dart_test.yaml').readAsStringSync();
    expect(config, matches(RegExp(r'^\s*mr:', multiLine: true)));
    final mrBlock = RegExp(
      r'^\s*mr:\s*\n\s*description:\s*>-?\s*\n((?:\s+.+\n)+)',
      multiLine: true,
    ).firstMatch(config)?.group(1);
    final mrBlockText = mrBlock;
    expect(mrBlockText, isNotNull);
    expect(mrBlockText, matches(RegExp(r'j\s*1', caseSensitive: false)));
  });

  test(
    '${_pgPlainSuite.split('/').last} stays pg-tagged without library mr',
    () {
      expect(
        _declaredTags(File('${_serverPackage.path}/$_pgPlainSuite')),
        contains('pg'),
      );
      expect(
        _declaredTags(File('${_serverPackage.path}/$_pgPlainSuite')),
        isNot(contains('mr')),
      );
    },
  );

  test(
    '${_mrSuite.split('/').last} library stays pg-tagged for the plain slice',
    () {
      expect(
        _declaredTags(File('${_serverPackage.path}/$_mrSuite')),
        contains('pg'),
      );
      expect(
        _declaredTags(File('${_serverPackage.path}/$_mrSuite')),
        isNot(contains('mr')),
      );
    },
  );

  group('constellation-field MeritRank PostgreSQL required verification', () {
    late Map<String, Object?> entry;
    late List<String> argv;
    late String cwd;

    setUp(() {
      entry = _readRequiredVerificationEntry();
      argv = _entryArgv(entry);
      final rawCwd = entry['cwd'];
      expect(rawCwd, isA<String>());
      cwd = rawCwd! as String;
    });

    test(
      'registry records dart test --tags mr -j 1 on both repository suites '
      'under packages/server',
      () {
        expect(
          _usesPlainPgExcludeMrSelector(argv),
          isFalse,
          reason: 'The reported defect used --tags pg --exclude-tags mr, '
              'which selects zero mr-tagged suites (exit 79).',
        );
        expect(argv.first, 'test');
        expect(argv[argv.indexOf('--tags') + 1], 'mr');
        expect(argv[argv.indexOf('-j') + 1], '1');
        expect(argv, contains(_mrSuite));
        expect(argv, isNot(contains(_pgPlainSuite)));
        expect(cwd, _serverPackagePathSuffix);
      },
    );

    test('executor script exists and is runnable', () {
      final executor = entry['executor'];
      expect(executor, isA<String>());
      final script = File('${_repoRoot.path}/${executor!}');
      expect(script.existsSync(), isTrue);
      expect(
        Process.runSync('test', ['-x', script.path]).exitCode,
        0,
        reason: 'executor must be executable',
      );
    });

    test('registry argv selects both suite files via json reporter', () {
      final workdir = Directory('${_repoRoot.path}/$cwd');
      expect(workdir.existsSync(), isTrue);

      return _suitePathsSelectedByArgv(
        workingDirectory: workdir.path,
        argv: argv,
      ).then((paths) {
        expect(
          paths.any((p) => p.endsWith(_mrSuite)),
          isTrue,
          reason: 'expected suite path ending with $_mrSuite in $paths',
        );
      });
    });
  });

  group('constellation-field MeritRank PostgreSQL check executor', () {
    test('reads argv from the verification registry and runs dart in packages/server', () async {
      final entry = _readRequiredVerificationEntry();
      final expectedArgv = _entryArgv(entry);
      final rawExecutor = entry['executor'];
      expect(rawExecutor, isA<String>());
      final executor = rawExecutor! as String;
      final script = File('${_repoRoot.path}/$executor');
      expect(script.existsSync(), isTrue);

      expect(
        script.readAsStringSync(),
        contains(_verificationRegistryPath),
        reason: 'executor must load argv from $_verificationRegistryPath',
      );
      expect(
        script.readAsStringSync(),
        contains(_verificationRegistryKey),
      );

      final fixtureRoot =
          Directory.systemTemp.createTempSync('constellation_mr_pg_check_');
      addTearDown(() {
        if (fixtureRoot.existsSync()) {
          fixtureRoot.deleteSync(recursive: true);
        }
      });

      final bin = Directory('${fixtureRoot.path}/bin')..createSync();
      final log = File('${fixtureRoot.path}/invocations.log');
      File('${bin.path}/dart').writeAsStringSync('''
#!/usr/bin/env bash
{
  echo "PWD=\$PWD"
  echo "ARGV=\$*"
} >> "${log.path}"
exit 0
''');
      Process.runSync('chmod', ['+x', '${bin.path}/dart']);

      final result = await Process.run(
        'bash',
        [script.path],
        workingDirectory: _repoRoot.path,
        environment: {
          ...Platform.environment,
          'PATH': '${bin.path}:${Platform.environment['PATH']}',
        },
      );

      expect(
        result.exitCode,
        0,
        reason: '${result.stdout}${result.stderr}',
      );
      expect(log.existsSync(), isTrue);
      final lines = log
          .readAsStringSync()
          .split('\n')
          .where((l) => l.isNotEmpty)
          .toList();
      expect(lines, hasLength(2));

      final pwdLine = lines.firstWhere((l) => l.startsWith('PWD='));
      final argvLine = lines.firstWhere((l) => l.startsWith('ARGV='));
      expect(
        pwdLine,
        endsWith('/$_serverPackagePathSuffix'),
        reason: 'dart must run from packages/server, got $pwdLine',
      );
      expect(argvLine, 'ARGV=${expectedArgv.join(' ')}');
    });
  });
}
