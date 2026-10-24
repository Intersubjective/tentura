// Issue #667: a recipient of a New chat sees "<author> started this chat with
// you" in the pinned strip, not "<author> forwarded this to you". The copy
// exists in every locale and is translated.

import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

const _key = 'postStartedByLine';

Map<String, dynamic> _arb(String locale) =>
    jsonDecode(File('l10n/app_$locale.arb').readAsStringSync())
        as Map<String, dynamic>;

void main() {
  group('#667 started-this-chat line', () {
    test('every locale has the copy with a {name} placeholder', () {
      for (final f in Directory('l10n').listSync().whereType<File>()) {
        final name = f.uri.pathSegments.last;
        if (!name.startsWith('app_') || !name.endsWith('.arb')) continue;
        final value =
            (jsonDecode(f.readAsStringSync()) as Map<String, dynamic>)[_key];
        expect(value, isA<String>(), reason: '$name needs "$_key"');
        expect(value as String, contains('{name}'), reason: name);
      }
    });

    test('English and Russian copy say started, not forwarded', () {
      expect(_arb('en')[_key], '{name} started this chat with you');
      final ru = _arb('ru')[_key] as String;
      expect(ru, contains('начал'));
      expect(ru, isNot(contains('переслал')));
    });
  });
}
