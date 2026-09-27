// tentura-23h concurrent wrapped-suite isolation acceptance

import 'dart:io';

import 'package:test/test.dart';

/// Alloy tentura-23h — paths exercised by bead acceptance harness.
const k23hAcceptanceTestPaths = [
  'test/architecture/tentura_23h_concurrent_wrapped_test.dart',
];

const _23hAcceptanceMarker = 'tentura-23h concurrent wrapped-suite isolation acceptance';

void main() {
  group('tentura-23h concurrent wrapped cleanup', () {
    test('23h acceptance test paths declare tentura-23h markers', () {
      for (final path in k23hAcceptanceTestPaths) {
        final file = File(path);
        expect(file.existsSync(), isTrue, reason: 'missing acceptance path $path');
        final source = file.readAsStringSync();
        expect(
          source,
          contains(_23hAcceptanceMarker),
          reason: '$path must tag tentura-23h for Alloy acceptance tracking',
        );
      }
    });

    test(
      'bead acceptance: concurrent wrapped selftest exits 0',
      () {
        final outcome = run23hConcurrentWrappedSelftest();
        expect(
          outcome.exitCode,
          0,
          reason:
              'tentura-23h requires '
              '`bash scripts/tentura_23h_concurrent_wrapped_selftest.sh` '
              'to exit 0 while another wrapped suite is still running\n'
              'stdout:\n${outcome.stdout}\n'
              'stderr:\n${outcome.stderr}',
        );
      },
      timeout: const Timeout(Duration(minutes: 3)),
    );

    test(
      'bead acceptance: nested wrapped 28f-style run survives concurrent wrapped peer',
      () async {
        final outcome = await run23hNestedWrappedConcurrentPeer();
        expect(
          outcome.exitCode,
          0,
          reason:
              'tentura-23h requires an outer wrapped nested dart test to exit 0 '
              'while a concurrent wrapped `true` peer finishes and sweeps\n'
              'stdout:\n${outcome.stdout}\n'
              'stderr:\n${outcome.stderr}',
        );
      },
      timeout: const Timeout(Duration(minutes: 5)),
    );

    test(
      '23h concurrent peer isolation probe',
      () async {
        // Holds the wrapped dart test run open while another agent's wrapper sweeps.
        final hold = await Process.start(
          'python3',
          ['-c', 'import time; time.sleep(25)'],
        );
        expect(await hold.exitCode, 0);
      },
      timeout: const Timeout(Duration(minutes: 2)),
    );
  });
}

({int exitCode, String stdout, String stderr}) run23hConcurrentWrappedSelftest() {
  final script = _repoRoot().path + '/scripts/tentura_23h_concurrent_wrapped_selftest.sh';
  final result = Process.runSync(
    'bash',
    [script],
    workingDirectory: _repoRoot().path,
    environment: {
      ...Platform.environment,
      'DART_SUPPRESS_ANALYTICS': 'true',
    },
  );
  return (
    exitCode: result.exitCode,
    stdout: result.stdout as String,
    stderr: result.stderr as String,
  );
}

/// Mirrors tentura-28f nested acceptance while a second wrapped suite runs.
Future<({int exitCode, String stdout, String stderr})>
run23hNestedWrappedConcurrentPeer() async {
  final wrapper = _testCleanupWrapper();
  final nestedTmp = Directory.systemTemp.createTempSync('tentura-23h-nested-');
  try {
    final peer = await Process.start(
      wrapper.path,
      ['--timeout', '45s', '--', 'true'],
      workingDirectory: _serverPackageRoot().path,
      environment: Platform.environment,
    );
    // Let the peer reach its exit sweep while the victim is still wrapped.
    await Future<void>.delayed(const Duration(milliseconds: 300));

    final victim = Process.runSync(
      wrapper.path,
      [
        '--timeout',
        '45m',
        '--',
        'dart',
        'test',
        '--name',
        '23h concurrent peer isolation probe',
        'test/architecture/tentura_23h_concurrent_wrapped_test.dart',
      ],
      workingDirectory: _serverPackageRoot().path,
      environment: {
        ...Platform.environment,
        'DART_SUPPRESS_ANALYTICS': 'true',
        'TMPDIR': nestedTmp.path,
      },
    );

    final peerExit = await peer.exitCode;
    return (
      exitCode: victim.exitCode,
      stdout:
          '${victim.stdout}\n--- peer exit code ---\n$peerExit\n',
      stderr: victim.stderr as String,
    );
  } finally {
    nestedTmp.deleteSync(recursive: true);
  }
}

Directory _repoRoot() {
  for (final start in [
    Directory.current,
    Directory('../../'),
    Directory('../../../'),
  ]) {
    final script = File('${start.path}/scripts/run_with_test_cleanup.sh');
    if (script.existsSync()) {
      return start.absolute;
    }
  }
  throw StateError('repo root not found');
}

File _testCleanupWrapper() {
  final repo = _repoRoot();
  final file = File('${repo.path}/scripts/run_with_test_cleanup.sh');
  if (!file.existsSync()) {
    throw StateError('scripts/run_with_test_cleanup.sh not found');
  }
  return file.absolute;
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
