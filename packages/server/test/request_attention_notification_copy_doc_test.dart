@Tags(['repo-files'])
library;

import 'dart:io';

import 'package:test/test.dart';

/// The «Notification copy» section of `request-attention.md` must exist and
/// list every `presentation_key` of the notification identity spec (§5.2).
void main() {
  final doc = File('../../docs/features/request-attention.md')
      .readAsStringSync();
  final spec = File('../../docs/plans/notification-identity-spec.md')
      .readAsStringSync();

  final headingMatch = RegExp(
    r'^## [^\n]*Notification copy[^\n]*$',
    multiLine: true,
  ).firstMatch(doc);

  test('the Notification copy section exists', () {
    expect(headingMatch, isNotNull);
  });

  test('the section lists every presentation_key of the spec table', () {
    final start = headingMatch!.end;
    final next = RegExp('^## ', multiLine: true).firstMatch(
      doc.substring(start),
    );
    final section = doc.substring(
      start,
      next == null ? doc.length : start + next.start,
    );

    final table = spec.substring(
      spec.indexOf('### 5.2 Event sentences'),
      spec.indexOf('### 5.3 In-app'),
    );
    final keys = RegExp(r'^\| `([a-z_]+)`', multiLine: true)
        .allMatches(table)
        .map((m) => m.group(1)!)
        .toSet();

    expect(keys, isNotEmpty);
    for (final key in keys) {
      expect(section, contains('`$key`'), reason: 'missing $key');
    }
  });

  test('DEV_GUIDELINES names the renderer as the only place for copy', () {
    final guide = File('../../DEV_GUIDELINES.md').readAsStringSync();
    expect(guide, contains('NotificationCopyRenderer'));
  });
}
