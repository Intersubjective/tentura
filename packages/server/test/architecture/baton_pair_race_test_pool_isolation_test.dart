// The baton pair case's join-versus-withdrawal race needs two live
// connections, so it must carry the multi-connection tag (kept out of the
// pool-size-1 CI pass) while every other test in that file stays untagged.
// The race test itself asserts that its own pool holds several connections.
// Cheap source check of the tag placement; no database needed.

import 'dart:io';

import 'package:test/test.dart';

const _file = 'test/domain/use_case/room_baton_pair_case_pg_test.dart';
const _raceName = 'racing join against withdrawal always ends consistent';

void main() {
  group('baton pair race tag placement', () {
    final source = File(_file).readAsStringSync();
    final starts = RegExp(
      r'^\s*test\(',
      multiLine: true,
    ).allMatches(source).map((m) => m.start).toList();

    String declaration(int i) => source.substring(
      starts[i],
      i + 1 < starts.length ? starts[i + 1] : source.length,
    );

    test('the race test carries the multi-connection tag', () {
      final race = [
        for (var i = 0; i < starts.length; i++)
          if (declaration(i).contains("'$_raceName'")) declaration(i),
      ];
      expect(race, hasLength(1));
      expect(
        RegExp(r"tags:\s*\[[^\]]*'multi-connection'").hasMatch(race.single),
        isTrue,
      );
    });

    test('no other test in the file is tagged multi-connection', () {
      final tagged = [
        for (var i = 0; i < starts.length; i++)
          if (!declaration(i).contains("'$_raceName'") &&
              declaration(i).contains('multi-connection'))
            declaration(i).split('\n').first,
      ];
      expect(tagged, isEmpty);
      expect(
        source.split('\n').take(3).join(),
        isNot(contains('multi-connection')),
        reason: 'a file-level tag would pull every test out of the pool-1 pass',
      );
    });
  });
}
