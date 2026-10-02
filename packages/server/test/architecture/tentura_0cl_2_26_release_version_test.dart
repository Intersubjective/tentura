import 'dart:io';

import 'package:test/test.dart';

/// Git-tracked runbook (Arch §11 release sequence + A24 post-deploy checks).
const _deployRunbookPath =
    '../../docs/plans/episode-closure-deploy-runbook.md';

/// Review artifact: exact body pasted into the merge PR description (must match
/// the runbook).
const _prDescriptionArtifactPath =
    '../../docs/plans/episode-closure-a24-pr-description.md';

const _architecturePath =
    '../../docs/plans/episode-closure-architecture.md';

String _normalizeForMatch(String text) =>
    text.toLowerCase().replaceAll(RegExp(r'\s+'), ' ').trim();

String _versionFromPubspecText(String pubspec) {
  final line = pubspec
      .split('\n')
      .firstWhere((l) => l.startsWith('version:'));
  return line.split(':')[1].trim();
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
  group('tentura-0cl.2.26 — A24 release version and floor', () {
    test('the checked-in web bootstrap cache-buster matches pubspec', () {
      expect(
        _bootstrapCacheBusterVersion(),
        _shippedClientVersion(),
        reason:
            'packages/client/web/index.html flutter_bootstrap.js?v= must '
            'match packages/client/pubspec.yaml.',
      );
    });

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
