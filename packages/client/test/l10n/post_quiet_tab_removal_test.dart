// Posts no longer fade to a «gone quiet» tab: a Post lives until its explicit
// expiry, so the quiet-tab copy, the quiet window and the unused
// «active for N more …» strings must not linger.

import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

Map<String, dynamic> _arb(String locale) =>
    jsonDecode(File('l10n/app_$locale.arb').readAsStringSync())
        as Map<String, dynamic>;

const _locales = ['en', 'ru'];
const _removedKeys = [
  'postsTabQuiet',
  'postInfoQuiet',
  'postInfoActiveHours',
  'postInfoActiveDays',
];

/// Identifiers of the retired quiet-window API, in addition to the ARB keys.
const _removedSymbols = [
  ..._removedKeys,
  'quietAfter',
];

/// Hand-written client sources. `lib/ui/l10n/` is generated from the ARB files
/// and git-ignored, so a stale local copy must not decide the result.
Iterable<File> _handWrittenSources() => Directory('lib')
    .listSync(recursive: true)
    .whereType<File>()
    .where((file) => file.path.endsWith('.dart'))
    .where((file) => !file.path.startsWith('lib/ui/l10n/'));

void main() {
  test('quiet-tab and active-for strings are gone from every ARB', () {
    for (final locale in _locales) {
      final arb = _arb(locale);
      for (final key in _removedKeys) {
        expect(arb.containsKey(key), isFalse, reason: 'app_$locale.arb: $key');
        expect(
          arb.containsKey('@$key'),
          isFalse,
          reason: 'app_$locale.arb: @$key',
        );
      }
    }
  });

  test('no client source refers to the retired quiet-window API', () {
    final offenders = <String>[];
    for (final file in _handWrittenSources()) {
      final source = file.readAsStringSync();
      for (final symbol in _removedSymbols) {
        if (source.contains(symbol)) offenders.add('${file.path}: $symbol');
      }
    }
    expect(offenders, isEmpty);
  });

  test('PostsCubit keeps no silence-based 72 h window of its own', () {
    final source = File(
      'lib/features/inbox/ui/bloc/posts_cubit.dart',
    ).readAsStringSync();
    expect(source, isNot(contains('quietAfter')));
    // Renaming the constant or moving the window elsewhere in the cubit would
    // keep the behaviour the expiry deadline replaced.
    expect(
      source,
      isNot(matches(RegExp(r'Duration\(\s*(hours:\s*72|days:\s*3)\b'))),
    );
  });
}
