// tentura-28f landing gate acceptance (trial merge tentura-21x)

import 'dart:io';

import 'package:test/test.dart';

/// Alloy tentura-28f landing gate — same path as bead acceptance harness.
const k28fAcceptanceTestPaths = [
  'test/architecture/tentura_28f_landing_check_test.dart',
];

const _28fLandingGateMarker =
    'tentura-28f landing gate acceptance (trial merge tentura-21x)';

const _trialMergeMarker = 'trial merge tentura-21x';

const _21xLandingTestRelative =
    'test/architecture/tentura_21x_unused_test_setup_test.dart';

Object get _skipNestedCleanupInCiDartTest {
  final env = Platform.environment;
  if (env['GITHUB_ACTIONS'] == 'true' ||
      env['CI'] == 'true' ||
      env['TEST_TARGET'] == 'server' ||
      env['TENTURA_U6E_NESTED_SUITE'] == 'true') {
    return 'do not nest run_with_test_cleanup.sh inside CI dart test';
  }
  return false;
}

void main() {
  group('tentura-28f landing check (trial merge tentura-21x)', () {
    test('28f acceptance test paths declare 28f landing gate markers', () {
      for (final path in k28fAcceptanceTestPaths) {
        final file = File(path);
        expect(file.existsSync(), isTrue, reason: 'missing acceptance path $path');
        final source = file.readAsStringSync();
        expect(
          source,
          contains(_28fLandingGateMarker),
          reason:
              '$path must tag the 28f landing gate for Alloy trial-merge tracking',
        );
        expect(
          source,
          contains(_trialMergeMarker),
          reason: '$path must reference trial merge tentura-21x',
        );
      }
    });

    test('m0141 person_capability_event ledger test defines wired _seedFixture', () {
      const relative =
          'test/data/database/m0141_person_capability_event_ledger_test.dart';
      final source = _serverTestSource(relative);
      if (!source.contains('await _seedFixture(writer)')) {
        return;
      }
      expect(
        source,
        contains('Future<void> _seedFixture'),
        reason:
            '$relative calls _seedFixture but the helper is missing — '
            'finish tentura-21x trial merge',
      );
    });

    test(
      'attention_repository_pg_test defines _TestChannels when channel handoff is wired',
      () {
        const relative =
            'test/data/repository/attention_repository_pg_test.dart';
        final source = _serverTestSource(relative);
        if (!RegExp(r'\b_TestChannels\(').hasMatch(source)) {
          return;
        }
        expect(
          source,
          contains('class _TestChannels'),
          reason:
              '$relative uses _TestChannels but the fake is missing — '
              'finish tentura-21x trial merge',
        );
      },
    );

    test(
      'bead acceptance: wrapped dart test tentura_21x_unused_test_setup_test.dart exits 0',
      () {
        final outcome = run28fAcceptance21xLandingTest();
        expect(
          outcome.exitCode,
          0,
          reason:
              'tentura-28f requires '
              '`cd packages/server && '
              '../../scripts/run_with_test_cleanup.sh --timeout 45m -- '
              'dart test test/architecture/tentura_21x_unused_test_setup_test.dart` '
              'to exit 0\n'
              'stdout:\n${outcome.stdout}\n'
              'stderr:\n${outcome.stderr}',
        );
      },
      timeout: const Timeout(Duration(minutes: 46)),
      skip: _skipNestedCleanupInCiDartTest,
    );

    test('tentura-21x landing gate test file is present for trial merge', () {
      final landing = File(_21xLandingTestRelative);
      expect(
        landing.existsSync(),
        isTrue,
        reason: 'missing $_21xLandingTestRelative from tentura-21x',
      );
      expect(
        landing.readAsStringSync(),
        contains('tentura-21x unused test setup'),
        reason: '21x landing test must guard unused disposable-PG setup',
      );
    });
  });
}

/// Runs the exact tentura-28f bead acceptance command.
({int exitCode, String stdout, String stderr}) run28fAcceptance21xLandingTest() {
  final wrapper = _testCleanupWrapper();
  final nestedTmp = Directory.systemTemp.createTempSync(
    'tentura-28f-nested-',
  );
  try {
    final result = Process.runSync(
      wrapper.path,
      [
        '--timeout',
        '45m',
        '--',
        'dart',
        'test',
        _21xLandingTestRelative,
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

String _serverTestSource(String relativePath) {
  final file = File('${_serverPackageRoot().path}/$relativePath');
  if (!file.existsSync()) {
    throw StateError('server test file not found: ${file.path}');
  }
  return file.readAsStringSync();
}
