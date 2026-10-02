// tentura-h8q: permanent People-seen release version policy (no git-show-main
// minor gate).

import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

const _mainSafeReleaseVersionTestName =
    'release version policy passes on a clean main checkout and allows '
    'same-minor patch releases';

final _defectiveMinorOnlyGatePattern = RegExp(
  r'greaterThan\s*\(\s*int\.parse\s*\(\s*'
  '(?:mainVersion|branchVersion|worktreeVersion|mainRefVersion)'
  r"\.split\(\s*'\.'\s*\)\[\s*1\s*\]\s*\)\s*\)",
);

File _clientTestFile(String relativePath) {
  for (final prefix in const ['../../', '']) {
    final file = File('$prefix$relativePath');
    if (file.existsSync()) {
      return file.absolute;
    }
  }
  throw StateError('Client test file not found: $relativePath');
}

String? _flutterTestBody(String source, String testName) {
  final start = source.indexOf("test('$testName'");
  if (start < 0) {
    return null;
  }
  final braceStart = source.indexOf('{', start);
  if (braceStart < 0) {
    return null;
  }
  var depth = 0;
  for (var i = braceStart; i < source.length; i++) {
    final char = source[i];
    if (char == '{') {
      depth++;
    } else if (char == '}') {
      depth--;
      if (depth == 0) {
        return source.substring(braceStart + 1, i);
      }
    }
  }
  return null;
}

bool _legacyMinorOnlyGateWouldFail(
  String worktreeVersion,
  String mainRefVersion,
) {
  final worktreeMinor = int.parse(worktreeVersion.split('.')[1]);
  final mainMinor = int.parse(mainRefVersion.split('.')[1]);
  return worktreeMinor <= mainMinor;
}

void main() {
  final releaseTestSource = _clientTestFile(
    'packages/client/test/architecture/beacon_people_seen_release_test.dart',
  ).readAsStringSync();

  group('tentura-h8q permanent People-seen release version policy', () {
    test(
      'beacon_people_seen_release_test.dart does not restore the git-show-main minor gate',
      () {
        expect(
          releaseTestSource,
          isNot(
            contains('client minor exceeds main and tracked web cache buster'),
          ),
          reason: 'One-time branch-release minor gate must stay removed',
        );
        expect(
          releaseTestSource,
          isNot(matches(_defectiveMinorOnlyGatePattern)),
          reason:
              'Must not compare only pubspec minor fields with greaterThan',
        );
        expect(
          releaseTestSource,
          isNot(contains('must exceed main')),
          reason: 'Minor-exceeds-main copy must not return to the permanent suite',
        );
      },
    );

    test(
      'beacon_people_seen_release_test.dart defines a main-safe release version test',
      () {
        expect(
          releaseTestSource,
          contains("test('$_mainSafeReleaseVersionTestName'"),
          reason:
              'Permanent suite must assert clean main and same-minor patch '
              'releases are allowed',
        );
      },
    );

    test(
      'main-safe release version test reads main pubspec and rejects the legacy minor gate',
      () {
        final body = _flutterTestBody(
          releaseTestSource,
          _mainSafeReleaseVersionTestName,
        );
        expect(
          body,
          isNotNull,
          reason: 'Missing $_mainSafeReleaseVersionTestName test body',
        );
        expect(
          body,
          contains('main:packages/client/pubspec.yaml'),
          reason: 'Must compare working tree against git show main pubspec',
        );
        expect(
          body,
          isNot(matches(_defectiveMinorOnlyGatePattern)),
          reason: 'Main-safe test must not reintroduce minor-only greaterThan',
        );
        expect(
          body,
          contains('7.22.3'),
          reason: 'Must cover equal-on-main scenario from acceptance criteria',
        );
        expect(
          body,
          contains('7.22.4'),
          reason: 'Must cover same-minor patch scenario from acceptance criteria',
        );
      },
    );

    test('acceptance scenarios were broken by the legacy minor-only gate', () {
      for (final scenario in [
        ('7.22.3', '7.22.3'),
        ('7.22.4', '7.22.3'),
      ]) {
        expect(
          _legacyMinorOnlyGateWouldFail(scenario.$1, scenario.$2),
          isTrue,
          reason:
              'Legacy gate incorrectly rejects ${scenario.$1} vs ${scenario.$2}',
        );
      }
    });
  });
}
