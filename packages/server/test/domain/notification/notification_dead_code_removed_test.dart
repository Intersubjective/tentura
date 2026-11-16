import 'dart:io';

import 'package:test/test.dart';

// Source readers: these members have no behaviour left to observe (the
// renderer owns the copy), so the only honest check is that nothing defines or
// calls them any more, anywhere in lib/ or test/. Removing the member by
// deleting its file is fine too: the scan only reads files that exist.

const _self = 'notification_dead_code_removed_test.dart';

/// Every Dart file under lib/ and test/ except this one, comments stripped.
Map<String, String> _sources() => {
  for (final dir in ['lib', 'test'])
    for (final entity in Directory(dir).listSync(recursive: true))
      if (entity is File &&
          entity.path.endsWith('.dart') &&
          !entity.path.endsWith(_self) &&
          !entity.path.endsWith('.g.dart') &&
          !entity.path.endsWith('.freezed.dart'))
        entity.path: entity
            .readAsLinesSync()
            .where((line) => !line.trimLeft().startsWith('//'))
            .join('\n'),
};

List<String> _hits(RegExp pattern) => [
  for (final MapEntry(:key, :value) in _sources().entries)
    if (pattern.hasMatch(value)) key,
];

void main() {
  group('retired notification copy members', () {
    test(
      'nothing defines or calls BeaconNotificationBatchAggregator.aggregate',
      () {
        // `aggregate(` as a whole identifier: a declaration or a call.
        expect(_hits(RegExp(r'(?<![\w$])aggregate\s*\(')), isEmpty);
      },
    );

    test('nothing defines or calls the intent-based lockScreenSafe on the '
        'copy builder', () {
      expect(
        _hits(
          RegExp(
            r'lockScreenSafe\(\s*(final\s+)?BeaconNotificationIntent\b',
          ),
        ),
        isEmpty,
        reason: 'declaration',
      );
      expect(
        _hits(RegExp(r'(?<![\w$])(\w*[bB]uilder)\.lockScreenSafe\(')),
        isEmpty,
        reason: 'call on the copy builder',
      );
    });
  });

  group('stored notification text is localized only for invite accepted', () {
    test('the push service never localizes stored text', () {
      final callers = _hits(RegExp(r'\.localizeStored\('));
      expect(
        callers.where(
          (path) => path.endsWith('beacon_notification_service.dart'),
        ),
        isEmpty,
      );
    });
  });
}
