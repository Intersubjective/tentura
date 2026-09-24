import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

/// `main` shipped `7.19.6` when tentura-634 was scoped; release must bump minor past
/// that baseline (e.g. `7.20.0`).
const kTentura634MainMinorBaseline = 19;

const _readReceiptsHeading = '## Read receipts';

File _repoFile(String relativePath) {
  for (final prefix in const ['../../', '']) {
    final file = File('$prefix$relativePath');
    if (file.existsSync()) {
      return file.absolute;
    }
  }
  throw StateError('Repo file not found: $relativePath');
}

String? _markdownSectionBody(String markdown, String heading) {
  final lines = markdown.split('\n');
  final startIndex = lines.indexWhere((line) => line.trim() == heading);
  if (startIndex < 0) {
    return null;
  }
  final body = <String>[];
  for (var i = startIndex + 1; i < lines.length; i++) {
    final line = lines[i];
    if (line.startsWith('## ')) {
      break;
    }
    body.add(line);
  }
  return body.join('\n');
}

String _clientPackageVersion() {
  final pubspec = _repoFile('packages/client/pubspec.yaml').readAsStringSync();
  final versionLine = pubspec
      .split('\n')
      .singleWhere((line) => line.startsWith('version:'));
  return versionLine.split(':').last.trim().split('+').first;
}

void main() {
  group('tentura-634 read receipts release contract', () {
    test('beacon_room.md documents Read receipts with room_seen_peer wire kind', () {
      final doc = _repoFile('docs/features/beacon_room.md').readAsStringSync();
      expect(doc, contains(_readReceiptsHeading));

      final section = _markdownSectionBody(doc, _readReceiptsHeading);
      expect(
        section,
        isNotNull,
        reason: '$_readReceiptsHeading section body is missing',
      );
      expect(section!, contains('room_seen_peer'));
    });

    test(
      'beacon_room.md Read receipts section states the at-least-one-other-member rule',
      () {
        final doc =
            _repoFile('docs/features/beacon_room.md').readAsStringSync();
        final section = _markdownSectionBody(doc, _readReceiptsHeading);
        expect(
          section,
          isNotNull,
          reason: '$_readReceiptsHeading section is required',
        );

        final otherMemberRule = RegExp(
          r'(≥\s*1|at least one).{0,80}other.{0,40}member',
          caseSensitive: false,
        );
        expect(
          otherMemberRule.hasMatch(section!),
          isTrue,
          reason:
              'Read receipts section must document when receipts apply (≥1 other member)',
        );
      },
    );

    test(
      'beacon_room.md Read receipts section avoids user-facing beacon/room nouns',
      () {
        final section = _markdownSectionBody(
          _repoFile('docs/features/beacon_room.md').readAsStringSync(),
          _readReceiptsHeading,
        );
        expect(
          section,
          isNotNull,
          reason: 'cannot review terminology until $_readReceiptsHeading exists',
        );

        final beaconNoun = RegExp(r'\b[Bb]eacon\b|\bbeacons\b|\bBeacons\b');
        final roomNoun = RegExp(r'\b[Rr]oom\b|\broom\b');
        expect(
          beaconNoun.hasMatch(section!),
          isFalse,
          reason: 'Read receipts copy must not use product noun beacon',
        );
        expect(
          roomNoun.hasMatch(section!),
          isFalse,
          reason: 'Read receipts copy must not use workspace noun room',
        );
      },
    );

    test('client pubspec minor version is above main baseline for tentura-634', () {
      final version = _clientPackageVersion();
      final parts = version.split('.');
      expect(parts.length, greaterThanOrEqualTo(3), reason: 'semver $version');

      final minor = int.parse(parts[1]);
      expect(
        minor,
        greaterThan(kTentura634MainMinorBaseline),
        reason:
            'packages/client/pubspec.yaml version $version must bump minor above '
            'main 7.${kTentura634MainMinorBaseline}.x',
      );
    });
  });
}
