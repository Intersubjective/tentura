@Tags(['repo-files'])
library;

import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

/// #495 / #605: a bar shown straight through `ScaffoldMessenger.showSnackBar`
/// queues behind whatever bar is already up, so a fresh notice waited out the
/// old one's whole duration. The app `showSnackBar` helper in
/// `lib/ui/utils/ui_utils.dart` clears first (replace semantics); every other
/// call site goes through it.
///
/// [_legacy] freezes how many direct calls each older file still has; they
/// are tracked separately. A count may only go down, and an entry whose count
/// reaches 0 is removed.
const _helper = 'lib/ui/utils/ui_utils.dart';

/// Other helpers with the same replace semantics: they clear the messenger
/// before showing their bar. `undo_snack_bar.dart` builds the Undo bar
/// (people tags), which needs `persist: false` and its own animation style.
const _replacingHelpers = {_helper, 'lib/ui/widget/undo_snack_bar.dart'};

const _legacy = {
  'lib/features/beacon_create/ui/screen/beacon_create_screen.dart': 1,
  'lib/features/constellation/ui/widget/constellation_body.dart': 1,
  'lib/features/constellation/ui/widget/constellation_camera_controls.dart': 1,
  'lib/features/forward_candidate_context/ui/widget/'
          'forward_candidate_context_sheet.dart':
      1,
  'lib/ui/widget/pending_attachments.dart': 1,
};

final _direct = RegExp(r'\.\s*showSnackBar\s*\(');

Directory _libRoot() => Directory('lib').existsSync()
    ? Directory('lib')
    : Directory('packages/client/lib');

/// Line numbers (1-based) of the direct calls in [file], comments skipped.
List<int> _directCallLines(File file) {
  final lines = file.readAsLinesSync();
  return [
    for (var i = 0; i < lines.length; i++)
      if (!lines[i].trimLeft().startsWith('//'))
        for (final _ in _direct.allMatches(lines[i])) i + 1,
  ];
}

/// Checks [counts] (path → direct calls found) against [frozen]; returns one
/// line per breach.
List<String> legacyCountBreaches(
  Map<String, int> counts,
  Map<String, int> frozen,
) => [
  for (final MapEntry(key: path, value: limit) in frozen.entries)
    if ((counts[path] ?? 0) > limit)
      '$path: ${counts[path]} direct calls, frozen at $limit'
    else if ((counts[path] ?? 0) == 0)
      '$path: no direct calls left, remove its entry',
];

void main() {
  test('snack bars go through the replacing showSnackBar helper', () {
    final root = _libRoot();
    final prefix = root.path.substring(0, root.path.length - 'lib'.length);
    final offenders = <String>[];
    for (final entity in root.listSync(recursive: true)) {
      if (entity is! File || !entity.path.endsWith('.dart')) continue;
      final path = entity.path.substring(prefix.length);
      if (_replacingHelpers.contains(path) || _legacy.containsKey(path)) {
        continue;
      }
      for (final line in _directCallLines(entity)) {
        offenders.add('$path:$line');
      }
    }
    expect(
      offenders,
      isEmpty,
      reason:
          'direct ScaffoldMessenger.showSnackBar queues the bar; '
          'call showSnackBar(context, ...) from ui_utils.dart instead',
    );
  });
  test('legacy files keep at most their frozen direct-call count', () {
    final root = _libRoot();
    final prefix = root.path.substring(0, root.path.length - 'lib'.length);
    final counts = {
      for (final path in _legacy.keys)
        path: File('$prefix$path').existsSync()
            ? _directCallLines(File('$prefix$path')).length
            : 0,
    };
    expect(
      legacyCountBreaches(counts, _legacy),
      isEmpty,
      reason:
          'a frozen count may only go down: migrate new calls to '
          'showSnackBar(context, ...), and drop an entry at 0',
    );
  });

  group('the frozen-count ratchet itself', () {
    const frozen = {'a.dart': 1, 'b.dart': 2};

    test('passes when every count is at or under its limit', () {
      expect(legacyCountBreaches({'a.dart': 1, 'b.dart': 1}, frozen), isEmpty);
    });

    test('fails when a count goes up', () {
      expect(
        legacyCountBreaches({'a.dart': 2, 'b.dart': 2}, frozen),
        [contains('a.dart: 2 direct calls, frozen at 1')],
      );
    });

    test('fails when a listed file reaches 0, so its entry goes', () {
      expect(
        legacyCountBreaches({'a.dart': 1}, frozen),
        [contains('b.dart: no direct calls left')],
      );
    });
  });
}
