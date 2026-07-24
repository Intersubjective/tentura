import 'dart:io';

import 'package:test/test.dart';

void main() {
  const forbiddenCallPatterns = <String>[
    '.notifyInviteAccepted(',
    '.dispatch(',
    '@override Future<void> dispatch',
    'outbox.enqueue',
    '_outbox.enqueue',
  ];

  const forbiddenSymbols = <String>[
    'BeaconRoomNotificationPort',
    'InviteAcceptedNotificationPort',
  ];

  test('production code must not reintroduce legacy notification producers', () {
    final sources = Directory('lib')
        .listSync(recursive: true)
        .whereType<File>()
        .where((file) => file.path.endsWith('.dart'));

    for (final source in sources) {
      final contents = source.readAsStringSync();
      final rel = source.path.replaceFirst('lib/', '');

      for (final pattern in forbiddenCallPatterns) {
        expect(
          contents,
          isNot(contains(pattern)),
          reason: '$rel still contains legacy call pattern $pattern',
        );
      }

      for (final symbol in forbiddenSymbols) {
        expect(
          contents,
          isNot(contains(symbol)),
          reason: '$rel still references legacy symbol $symbol',
        );
      }
    }
  });

  test('notification services must not call dispatch', () {
    final sources = Directory('lib/data/service')
        .listSync(recursive: true)
        .whereType<File>()
        .where(
          (file) =>
              file.path.endsWith('.dart') &&
              file.path.contains('notification'),
        );

    for (final source in sources) {
      final contents = source.readAsStringSync();
      final rel = source.path.replaceFirst('lib/', '');

      expect(
        contents,
        isNot(contains('.dispatch(')),
        reason: '$rel still calls notification dispatch',
      );
      expect(
        contents,
        isNot(contains('_outbox.enqueue')),
        reason: '$rel still writes notification outbox rows directly',
      );
    }
  });
}
