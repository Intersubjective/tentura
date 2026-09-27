// tentura-olc landing gate acceptance (trial merge tentura-21x)

import 'dart:convert';
import 'dart:io';

import 'package:test/test.dart';

/// Alloy tentura-olc landing gate — same paths as the bead acceptance harness.
const kOlcAcceptanceTestPaths = [
  'test/architecture/tentura_olc_landing_check_test.dart',
];

const _olcLandingGateMarker =
    'tentura-olc landing gate acceptance (trial merge tentura-21x)';

const _trialMergeMarker = 'trial merge tentura-21x';

const _agentsOlcLandingFixture =
    '../../test/fixtures/agents_alloy_memory_olc_landing_tail.txt';

void main() {
  group('tentura-olc landing check (trial merge tentura-21x)', () {
    test('olc acceptance test paths declare olc landing gate markers', () {
      for (final path in kOlcAcceptanceTestPaths) {
        final file = File(path);
        expect(file.existsSync(), isTrue, reason: 'missing acceptance path $path');
        final source = file.readAsStringSync();
        expect(
          source,
          contains(_olcLandingGateMarker),
          reason:
              '$path must tag the olc landing gate for Alloy trial-merge tracking',
        );
        expect(
          source,
          contains(_trialMergeMarker),
          reason: '$path must reference trial merge tentura-21x',
        );
      }
    });

    test(
      'bead acceptance: wrapped `dart analyze .` exits 0 from packages/server',
      () {
        final outcome = runOlcAcceptancePackageAnalyze();
        expect(
          outcome.exitCode,
          0,
          reason:
              'tentura-olc requires '
              '`cd packages/server && '
              '../../scripts/run_with_test_cleanup.sh --timeout 10m -- '
              'dart analyze .` to exit 0\n'
              'stdout:\n${outcome.stdout}\n'
              'stderr:\n${outcome.stderr}',
        );
        expect(
          olcPackageAnalyzeErrorDiagnostics(),
          isEmpty,
          reason:
              'package analyze must report no error-severity diagnostics:\n'
              '${olcPackageAnalyzeErrorDiagnostics().join('\n')}',
        );
      },
      timeout: const Timeout(Duration(minutes: 12)),
      skip: Platform.environment['GITHUB_ACTIONS'] == 'true'
          ? 'do not nest run_with_test_cleanup.sh inside GitHub Actions dart test'
          : false,
    );

    test(
      'AGENTS.md alloy memory tail records tentura-olc landing gate acceptance',
      () {
        final agentsPath = _repoFile('AGENTS.md');
        final fixturePath = _repoFile(_agentsOlcLandingFixture);
        expect(
          fixturePath.existsSync(),
          isTrue,
          reason: 'missing $_agentsOlcLandingFixture',
        );
        final agents = agentsPath.readAsStringSync();
        const beginMarker = '<!-- alloy:memory:begin -->';
        final start = agents.indexOf(beginMarker);
        expect(start, greaterThanOrEqualTo(0), reason: 'missing $beginMarker');
        final actualTail = agents.substring(start).trimRight();
        final expectedTail = fixturePath.readAsStringSync().trimRight();
        expect(
          actualTail,
          equals(expectedTail),
          reason:
              'append tentura-olc landing gate acceptance beside jc0 on '
              'alloy/tentura-21x trial merge',
        );
      },
    );
  });
}

File _repoFile(String relativePath) {
  for (final prefix in const ['../../', '']) {
    final candidate = File('$prefix$relativePath');
    if (candidate.existsSync()) {
      return candidate.absolute;
    }
  }
  throw StateError('Repo file not found: $relativePath');
}

/// Runs the exact tentura-olc bead acceptance analyze command.
({int exitCode, String stdout, String stderr}) runOlcAcceptancePackageAnalyze() {
  final wrapper = _testCleanupWrapper();
  final nestedTmp = Directory.systemTemp.createTempSync(
    'tentura-olc-nested-',
  );
  try {
    final result = Process.runSync(
      wrapper.path,
      [
        '--timeout',
        '10m',
        '--',
        'dart',
        'analyze',
        '.',
      ],
      workingDirectory: _serverPackageRoot().path,
      environment: {
        ...Platform.environment,
        'DART_SUPPRESS_ANALYTICS': 'true',
        'TMPDIR': nestedTmp.path,
      },
    );
    return (
      exitCode: result.exitCode,
      stdout: result.stdout as String,
      stderr: result.stderr as String,
    );
  } finally {
    nestedTmp.deleteSync(recursive: true);
  }
}

List<String> olcPackageAnalyzeErrorDiagnostics() {
  final result = Process.runSync(
    'dart',
    ['analyze', '--format=json', '.'],
    workingDirectory: _serverPackageRoot().path,
    environment: {
      ...Platform.environment,
      'DART_SUPPRESS_ANALYTICS': 'true',
    },
  );
  final stdout = (result.stdout as String).trim();
  expect(
    stdout,
    isNotEmpty,
    reason:
        'dart analyze . must emit JSON (exit ${result.exitCode}); '
        'stderr: ${result.stderr}',
  );

  final payload = jsonDecode(stdout) as Map<String, dynamic>;
  final diagnostics =
      (payload['diagnostics'] as List).cast<Map<String, dynamic>>();
  return diagnostics
      .where((d) => d['severity'] == 'ERROR')
      .map((d) {
        final location = d['location'] as Map?;
        final line = location == null
            ? '?'
            : (location['range'] as Map?)?['start']?['line'];
        final file = location?['file'] ?? '?';
        final message =
            d['problemMessage']?.toString() ??
            d['message']?.toString() ??
            d['code']?.toString();
        return '$file:$line: $message';
      })
      .toList();
}

File _testCleanupWrapper() {
  final serverRoot = _serverPackageRoot();
  final candidates = [
    File('${serverRoot.path}/../../scripts/run_with_test_cleanup.sh'),
    File('${serverRoot.parent.parent.path}/scripts/run_with_test_cleanup.sh'),
  ];
  for (final file in candidates) {
    if (file.existsSync()) {
      return file.absolute;
    }
  }
  throw StateError('scripts/run_with_test_cleanup.sh not found');
}

Directory _serverPackageRoot() {
  for (final path in const ['.', '../../packages/server']) {
    final dir = Directory(path);
    final candidate = File('${dir.path}/lib/env.dart');
    if (candidate.existsSync()) {
      return dir.absolute;
    }
  }
  throw StateError('server package root not found');
}
