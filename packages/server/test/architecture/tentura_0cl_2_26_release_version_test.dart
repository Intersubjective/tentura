import 'dart:io';

import 'package:test/test.dart';
import 'package:tentura_server/env.dart';

/// Git-tracked runbook (Arch §11 release sequence + A24 post-deploy checks).
const _deployRunbookPath =
    '../../docs/plans/episode-closure-deploy-runbook.md';

/// Review artifact: exact body pasted into the merge PR description (must match
/// the runbook).
const _prDescriptionArtifactPath =
    '../../docs/plans/episode-closure-a24-pr-description.md';

const _architecturePath =
    '../../docs/plans/episode-closure-architecture.md';

List<int> _parseSemver(String version) => [
  for (final part in version.split('.')) int.parse(part),
];

int _compareSemver(String a, String b) {
  final left = _parseSemver(a);
  final right = _parseSemver(b);
  for (var i = 0; i < left.length; i++) {
    final c = left[i].compareTo(right[i]);
    if (c != 0) return c;
  }
  return 0;
}

String _normalizeForMatch(String text) =>
    text.toLowerCase().replaceAll(RegExp(r'\s+'), ' ').trim();

Directory _repoRoot() => Directory('../..').absolute;

String _versionFromPubspecText(String pubspec) {
  final line = pubspec
      .split('\n')
      .firstWhere((l) => l.startsWith('version:'));
  return line.split(':')[1].trim();
}

String _clientVersionOnMain() {
  for (final ref in ['main', 'origin/main']) {
    final result = Process.runSync('git', [
      'show',
      '$ref:packages/client/pubspec.yaml',
    ], workingDirectory: _repoRoot().path);
    if (result.exitCode == 0) {
      return _versionFromPubspecText('${result.stdout}');
    }
  }
  fail('Could not read packages/client/pubspec.yaml from main or origin/main');
}

/// A24 minor release: increment `Y`, reset patch to `0` (`x.Y.z` → `x.(Y+1).0`).
String _minorBumpRelease(String baseline) {
  final parts = _parseSemver(baseline);
  expect(parts.length, 3);
  return '${parts[0]}.${parts[1] + 1}.0';
}

File _clientFile(String relative) => File('../client/$relative');

String _shippedClientVersion() {
  return _versionFromPubspecText(_clientFile('pubspec.yaml').readAsStringSync());
}

String _bootstrapCacheBusterVersion() {
  final html = _clientFile('web/index.html').readAsStringSync();
  final match = RegExp(
    r'flutter_bootstrap\.js\?v=([0-9]+\.[0-9]+\.[0-9]+)',
  ).firstMatch(html);
  if (match == null) {
    fail('web/index.html has no flutter_bootstrap.js?v= cache-buster');
  }
  return match.group(1)!;
}

List<String> _releaseSequenceStepsFromArchitecture() {
  final lines = File(_architecturePath).readAsLinesSync();
  final start = lines.indexWhere(
    (line) => line.contains('Release sequence (one maintenance window'),
  );
  expect(
    start,
    greaterThanOrEqualTo(0),
    reason: '$_architecturePath must document the §11 release sequence.',
  );

  final steps = <String>[];
  for (var i = start + 1; i < lines.length; i++) {
    final line = lines[i];
    final match = RegExp(r'^\d+\.\s+(.*)$').firstMatch(line);
    if (match != null) {
      steps.add(match.group(1)!.trim());
      continue;
    }
    if (steps.isNotEmpty) {
      break;
    }
  }
  expect(
    steps.length,
    5,
    reason:
        'Arch §11 release sequence must list five numbered steps; found '
        '${steps.length}.',
  );
  return steps;
}

const _postDeployChecksFromA24 = [
  "trust_cutover_state.status = 'done'",
  'queue depth near 0',
];

void main() {
  late String mainClientVersion;
  late String expectedShippedVersion;

  setUpAll(() {
    mainClientVersion = _clientVersionOnMain();
    expectedShippedVersion = _minorBumpRelease(mainClientVersion);
  });

  group('tentura-0cl.2.26 — A24 release version and floor', () {
    test('minor-bumps the client from the version on main', () {
      expect(
        _shippedClientVersion(),
        expectedShippedVersion,
        reason:
            'A24 must minor-bump packages/client/pubspec.yaml from '
            '$mainClientVersion (main) to $expectedShippedVersion.',
      );
    });

    test('the checked-in web bootstrap cache-buster matches pubspec', () {
      expect(
        _bootstrapCacheBusterVersion(),
        _shippedClientVersion(),
        reason:
            'packages/client/web/index.html flutter_bootstrap.js?v= must '
            'match packages/client/pubspec.yaml.',
      );
    });

    test('kDefaultMinClientVersion equals the shipped client version', () {
      expect(
        kDefaultMinClientVersion,
        _shippedClientVersion(),
        reason:
            'kDefaultMinClientVersion ($kDefaultMinClientVersion) must equal '
            'packages/client/pubspec.yaml (${_shippedClientVersion()}).',
      );
    });

    /// Same behavioural contract as [release_client_version_floor_test] after
    /// A24 updates its pinned pre-release main to the version on main.
    group('release_client_version_floor_test contract (post-A24 pin)', () {
      test('shipped client is strictly higher than pre-release main', () {
        expect(
          _compareSemver(_shippedClientVersion(), mainClientVersion),
          greaterThan(0),
          reason:
              'packages/client/pubspec.yaml must be bumped above '
              '$mainClientVersion (main).',
        );
      });

      test('index.html cache-buster matches the bumped pubspec', () {
        expect(
          _compareSemver(_shippedClientVersion(), mainClientVersion),
          greaterThan(0),
          reason: 'pubspec.yaml must be bumped before this check is meaningful.',
        );
        expect(
          _bootstrapCacheBusterVersion(),
          _shippedClientVersion(),
          reason:
              'web/index.html flutter_bootstrap.js?v= must carry the same '
              'version as pubspec.yaml.',
        );
      });

      test('kDefaultMinClientVersion is raised to equal the new client version',
          () {
        expect(
          _compareSemver(kDefaultMinClientVersion, mainClientVersion),
          greaterThan(0),
          reason:
              'kDefaultMinClientVersion must be raised past $mainClientVersion.',
        );
        expect(
          kDefaultMinClientVersion,
          _shippedClientVersion(),
          reason:
              'kDefaultMinClientVersion must equal the bumped pubspec version, '
              'not merely satisfy it.',
        );
      });
    });

    test('release_client_version_floor_test.dart passes once versions land', () {
      expect(
        _shippedClientVersion(),
        expectedShippedVersion,
        reason:
            'A24 must ship $expectedShippedVersion (minor bump from main) '
            'before the floor-test gate can pass.',
      );
      final result = Process.runSync('dart', [
        'test',
        'test/release_client_version_floor_test.dart',
      ]);
      final output = '${result.stdout}\n${result.stderr}';
      expect(
        result.exitCode,
        0,
        reason:
            'release_client_version_floor_test must pass after the bump and '
            'pin update:\n$output',
      );
    }, timeout: const Timeout(Duration(minutes: 5)));

    group('deploy runbook and PR description artifact', () {
      late List<String> archSteps;

      setUpAll(() {
        archSteps = _releaseSequenceStepsFromArchitecture();
      });

      test('checked-in runbook carries the full Arch §11 release sequence', () {
        final runbook = File(_deployRunbookPath);
        expect(
          runbook.existsSync(),
          isTrue,
          reason: 'Add $_deployRunbookPath for the episode-closure release.',
        );
        final normalized = _normalizeForMatch(runbook.readAsStringSync());
        for (final step in archSteps) {
          expect(
            normalized,
            contains(_normalizeForMatch(step)),
            reason:
                'Deploy runbook must include Arch §11 release step: $step',
          );
        }
      });

      test('checked-in runbook documents A24 post-deploy verification', () {
        final runbook = File(_deployRunbookPath);
        expect(runbook.existsSync(), isTrue);
        final normalized = _normalizeForMatch(runbook.readAsStringSync());
        for (final check in _postDeployChecksFromA24) {
          expect(
            normalized,
            contains(_normalizeForMatch(check)),
            reason: 'Deploy runbook must document post-deploy check: $check',
          );
        }
      });

      test('PR description artifact matches the checked-in runbook', () {
        final runbookFile = File(_deployRunbookPath);
        final prFile = File(_prDescriptionArtifactPath);
        expect(
          runbookFile.existsSync(),
          isTrue,
          reason: 'Deploy runbook must exist before the PR artifact.',
        );
        expect(
          prFile.existsSync(),
          isTrue,
          reason:
              'Add $_prDescriptionArtifactPath with the exact text pasted '
              'into the merge PR description.',
        );
        expect(
          _normalizeForMatch(prFile.readAsStringSync()),
          _normalizeForMatch(runbookFile.readAsStringSync()),
          reason:
              'The PR description artifact must match the deploy runbook '
              '(copy runbook into the PR body).',
        );
      });
    });
  });
}
