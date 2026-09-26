import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

File _repoFile(String path) {
  for (final prefix in const ['../../', '']) {
    final file = File('$prefix$path');
    if (file.existsSync()) return file.absolute;
  }
  throw StateError('Repo file not found: $path');
}

Directory _repoRoot() =>
    _repoFile('packages/client/pubspec.yaml').parent.parent.parent;

String _versionIn(String pubspec) {
  final match = RegExp(
    r'^version:\s*(\d+\.\d+\.\d+)(?:\+\S+)?\s*$',
    multiLine: true,
  ).firstMatch(pubspec);
  expect(match, isNotNull, reason: 'Client pubspec must contain semver');
  return match!.group(1)!;
}

Iterable<String> _peopleSeenSections() sync* {
  final files =
      Directory('${_repoRoot().path}/docs/features')
          .listSync()
          .whereType<File>()
          .where((file) => file.path.endsWith('.md'))
          .toList()
        ..sort((a, b) => a.path.compareTo(b.path));
  final heading = RegExp(r'^(#{1,6})\s+(.+)$');

  for (final file in files) {
    final lines = file.readAsLinesSync();
    for (var i = 0; i < lines.length; i++) {
      final start = heading.firstMatch(lines[i]);
      if (start == null ||
          !RegExp(
            r'\bseen\b',
            caseSensitive: false,
          ).hasMatch(start.group(2)!)) {
        continue;
      }
      final body = <String>[];
      for (var j = i + 1; j < lines.length; j++) {
        final next = heading.firstMatch(lines[j]);
        if (next != null && next.group(1)!.length <= start.group(1)!.length) {
          break;
        }
        body.add(lines[j]);
      }
      final section = '${lines[i]}\n${body.join('\n')}';
      if (section.contains('beacon_people_seen') &&
          RegExp(r'\bpeople_seen\b').hasMatch(section)) {
        yield section;
      }
    }
  }
}

void main() {
  test('seen feature spec names the People watermark and wire kind', () {
    expect(
      _peopleSeenSections().toList(),
      isNotEmpty,
      reason:
          'A docs/features/*.md seen section must name '
          'beacon_people_seen and people_seen',
    );
  });

  test('every People author-seen section explains its release contract', () {
    final sections = _peopleSeenSections().toList();
    expect(sections, isNotEmpty);
    for (final section in sections) {
      final text = section.toLowerCase().replaceAll(RegExp(r'\s+'), ' ');
      for (final term in [
        'author',
        'steward',
        'people',
        'offer sheet',
        'moderator',
        'watermark',
        'offer',
        'general',
        'room_seen_peer',
        'read receipt',
        'admission',
        'decision',
        'd6',
        'other helpers',
        'another offerer',
        'bridge_attention_people_seen',
        'activity',
        'm0198',
      ]) {
        expect(text, contains(term), reason: 'Seen spec must explain $term');
      }
      for (final check in <(String, RegExp)>[
        (
          'People or offer sheet viewing',
          RegExp(r'\b(?:open|opens|opening|view|views|viewing)\b'),
        ),
        (
          'watermark writers',
          RegExp(r'\b(?:write|writes|update|updates|mark|marks)\b'),
        ),
        (
          'latest moderator watermark',
          RegExp(r'\b(?:latest|most recent|greatest|maximum)\b'),
        ),
        ('offer creation time', RegExp(r'\b(?:created|submitted|creation)\b')),
        (
          'earlier offers',
          RegExp(r'\b(?:earlier|prior|existing|previous|retroactive)\b'),
        ),
        ('people_seen wire update', RegExp(r'\b(?:wire|event|realtime)\b')),
        (
          'D6 privacy restriction',
          RegExp(r'\b(?:cannot|can\x27t|not exposed|not visible)\b'),
        ),
        (
          'not a General read receipt',
          RegExp(r'\b(?:not|never)\b.{0,40}\b(?:read )?receipts?\b'),
        ),
        (
          'not an admission decision',
          RegExp(r'\b(?:not|never)\b.{0,40}\bdecisions?\b'),
        ),
        (
          'server-first rollout',
          RegExp(
            r'\bserver\b.{0,100}\b(?:first|before)\b.{0,100}\bclient\b|'
            r'\bclient\b.{0,100}\bafter\b.{0,100}\bserver\b',
          ),
        ),
      ]) {
        expect(
          text,
          matches(check.$2),
          reason: 'Seen spec must explain ${check.$1}',
        );
      }
      expect(
        RegExp(r'\b[Bb]eacons?\b|\b[Rr]ooms?\b').hasMatch(section),
        isFalse,
        reason: 'User-facing terms in this section are Request and General',
      );
    }
  });

  test('terminology CI check passes', () {
    final result = Process.runSync(
      'bash',
      ['scripts/check-user-facing-terminology.sh'],
      workingDirectory: _repoRoot().path,
      environment: {'TERMINOLOGY_STRICT': '1'},
    );
    expect(result.exitCode, 0, reason: '${result.stdout}\n${result.stderr}');
  });

  test('tracked web cache buster matches pubspec version', () {
    // Alloy now runs in no-worktree mode: every bead commits directly onto
    // main, so there is no separate branch to compare a version bump
    // against (main and the working tree are the same ref) — the previous
    // "client minor exceeds main" assertion was a worktree-era invariant
    // that degenerated to comparing main against itself. Dropped; landing
    // review is the gate for whether a release-facing change bumped the
    // version at all. This test still guards a real defect class: the
    // tracked web bootstrap cache buster silently drifting from pubspec.
    final branchVersion = _versionIn(
      _repoFile('packages/client/pubspec.yaml').readAsStringSync(),
    );
    final index = _repoFile(
      'packages/client/web/index.html',
    ).readAsStringSync();
    expect(
      index,
      contains('flutter_bootstrap.js?v=$branchVersion'),
      reason: 'Tracked web bootstrap cache buster must match pubspec',
    );
  });
}
