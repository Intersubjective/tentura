// Each field in RoomCubit keeps its own doc comment: a comment must sit
// directly above the field it describes, with no other declaration wedged
// between them. Read from source because the placement has no runtime effect.
// Run from packages/client.

import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

void main() {
  final lines = File(
    'lib/features/beacon_threads/ui/bloc/room_cubit.dart',
  ).readAsLinesSync().map((l) => l.trim()).toList();

  /// The comment block ending on the line just above [declaration].
  String commentAbove(String declaration) {
    final at = lines.indexOf(declaration);
    expect(at, greaterThan(0), reason: '$declaration is declared');
    final block = <String>[];
    for (var i = at - 1; i >= 0 && lines[i].startsWith('///'); i--) {
      block.insert(0, lines[i]);
    }
    return block.join(' ');
  }

  group('RoomCubit field doc comments', () {
    test('the unread-band comment sits directly above _unreadBandTaken', () {
      final doc = commentAbove('bool _unreadBandTaken = false;');
      expect(doc, contains('The unread band is taken once per visit'));
      expect(doc, isNot(contains('Fact to focus')));
    });

    test('the focus-fact comment sits directly above _focusFactId', () {
      final doc = commentAbove('String? _focusFactId;');
      expect(doc, contains('Fact to focus after the first fact load'));
      expect(doc, isNot(contains('unread band')));
    });
  });
}
