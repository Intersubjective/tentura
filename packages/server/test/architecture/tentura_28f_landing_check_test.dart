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
