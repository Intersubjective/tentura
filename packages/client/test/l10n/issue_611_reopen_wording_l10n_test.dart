import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

// Issue #611 (#366 follow-up): Reopen from the final check lands in Open
// (Coordinating), not in «Needs more help». Translator notes must not say
// otherwise, and the Reopen string nothing shows any more is gone.
//
// Run from packages/client: the ARB files are read by relative path.
Map<String, dynamic> _arb(String path) =>
    jsonDecode(File(path).readAsStringSync()) as Map<String, dynamic>;

void main() {
  final en = _arb('l10n/app_en.arb');
  final ru = _arb('l10n/app_ru.arb');

  test('no translator note says a reopen lands in Needs more help', () {
    for (final arb in [en, ru]) {
      for (final entry in arb.entries.where((e) => e.key.startsWith('@'))) {
        final meta = entry.value;
        if (meta is! Map<String, dynamic>) continue;
        final description = (meta['description'] as String? ?? '')
            .toLowerCase();
        if (!description.contains('needs more help')) continue;
        expect(
          description,
          isNot(contains('reopen')),
          reason: '${entry.key}: a reopen lands in Open, not Needs more help',
        );
      }
    }
  });

  test('the unused Reopen success message is gone from every locale', () {
    expect(en.containsKey('beaconReviewReopenSuccess'), isFalse);
    expect(ru.containsKey('beaconReviewReopenSuccess'), isFalse);
    expect(en.containsKey('@beaconReviewReopenSuccess'), isFalse);
    expect(ru.containsKey('@beaconReviewReopenSuccess'), isFalse);
  });

  test('guard: the closure page Return to work label stays (still used)', () {
    expect(en['closureAuthorReopen'], 'Return to work');
    expect(ru['closureAuthorReopen'], isNotEmpty);
  });
}
