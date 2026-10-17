import 'dart:io';

import 'package:test/test.dart';

/// The client's `RealtimeSyncCase.blockMarkers` treats every
/// `constellation_field` change whose id is not `global` as a block or unblock
/// (B056). That holds only while the `user_block` trigger
/// (`notify_constellation_field_block`, m0232) is the one producer that
/// addresses `constellation_field` to specific users. A new addressed producer
/// must update the client filter too; this test makes that visible.
void main() {
  test(
    'only the user_block trigger emits an addressed constellation_field',
    () {
      final producers = <String>{};
      final migrations = Directory(
        'lib/data/database/migration',
      ).listSync().whereType<File>().where((f) => f.path.endsWith('.dart'));
      final functionHeader = RegExp(
        r'CREATE (?:OR REPLACE )?FUNCTION public\.(\w+)\(',
      );
      for (final file in migrations) {
        final source = file.readAsStringSync();
        for (final match in "'constellation_field'".allMatches(source)) {
          final before = source.substring(0, match.start);
          final headers = functionHeader.allMatches(before);
          producers.add(
            headers.isEmpty
                ? '${file.path}: outside a function'
                : headers.last[1]!,
          );
        }
      }

      expect(producers, {
        'notify_constellation_field_global',
        'notify_constellation_field_block',
      });
    },
  );

  test('the global producer always sends the id "global"', () {
    final source = File(
      'lib/data/database/migration/m0232.dart',
    ).readAsStringSync();
    final start = source.indexOf(
      'FUNCTION public.notify_constellation_field_global()',
    );
    final end = source.indexOf(r'$$', source.indexOf(r'$$', start) + 2);
    expect(source.substring(start, end), contains("'id', 'global'"));
  });
}
