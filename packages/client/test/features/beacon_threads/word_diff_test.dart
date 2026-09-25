import 'package:flutter_test/flutter_test.dart';
import 'package:tentura/features/beacon_threads/domain/util/word_diff.dart';

void main() {
  group('wordDiff', () {
    test('identical strings produce only same segments', () {
      const text = 'The quick fox jumps over the fence';

      final result = wordDiff(text, text);

      expect(result, isNotEmpty);
      expect(result.every((s) => s.kind == DiffKind.same), isTrue);
      expect(result.map((s) => s.text).join(), text);
    });

    test('appending text produces exactly one added run', () {
      // older already ends with the separator space, so the boundary is
      // unambiguous: the maximal LCS must match that trailing space (doing
      // otherwise would shorten the match), leaving 'Already sold.' as the
      // only possible added run — no leading-space token-boundary choice
      // is being assumed here.
      const older = 'Item available for sale. ';
      const newer = 'Item available for sale. Already sold.';

      final result = wordDiff(older, newer);

      final added = result.where((s) => s.kind == DiffKind.added).toList();
      expect(added.length, 1);
      expect(added.single.text, 'Already sold.');
      expect(result.any((s) => s.kind == DiffKind.removed), isFalse);

      final same = result.where((s) => s.kind == DiffKind.same).toList();
      expect(same, isNotEmpty);
      expect(same.map((s) => s.text).join(), older);

      final reconstructedNewer = result.map((s) => s.text).join();
      expect(reconstructedNewer, newer);
    });

    test('deleting the trailing word produces an exact removed segment', () {
      // newer is an exact prefix of older's tokens, so the removal is
      // unambiguous: the maximal LCS must match the whole newer string,
      // leaving exactly the trailing ' swiftly' (word plus its leading
      // separator) as removed — no word-vs-whitespace boundary guess.
      const older = 'The quick brown fox jumps swiftly';
      const newer = 'The quick brown fox jumps';

      final result = wordDiff(older, newer);

      final removed = result.where((s) => s.kind == DiffKind.removed).toList();
      expect(removed.length, 1);
      expect(removed.single.text, ' swiftly');
      expect(result.any((s) => s.kind == DiffKind.added), isFalse);

      final same = result.where((s) => s.kind == DiffKind.same).toList();
      expect(same, isNotEmpty);
      expect(same.map((s) => s.text).join(), newer);

      final reconstructedOlder = result.map((s) => s.text).join();
      expect(reconstructedOlder, older);
    });

    test(
      'replacing a single word inside unchanged text produces precise '
      'word-level same/removed/added segments, whitespace preserved',
      () {
        // older and newer are identical except for 'old' -> 'new'; the
        // unique maximal LCS keeps every other token matched, so a
        // word-level diff must yield exactly the unchanged text as 'same'
        // (not one big removed block plus one big added block covering
        // the whole strings).
        const older = 'Meet at the old cafe  tomorrow';
        const newer = 'Meet at the new cafe  tomorrow';

        final result = wordDiff(older, newer);

        final removed = result.where((s) => s.kind == DiffKind.removed).toList();
        final added = result.where((s) => s.kind == DiffKind.added).toList();
        expect(removed.length, 1);
        expect(added.length, 1);
        expect(removed.single.text, 'old');
        expect(added.single.text, 'new');

        final same = result.where((s) => s.kind == DiffKind.same).toList();
        expect(same.length, 2);
        expect(same.first.text, 'Meet at the ');
        expect(same.last.text, ' cafe  tomorrow');

        final reconstructedNewer = result
            .where((s) => s.kind != DiffKind.removed)
            .map((s) => s.text)
            .join();
        final reconstructedOlder = result
            .where((s) => s.kind != DiffKind.added)
            .map((s) => s.text)
            .join();

        expect(reconstructedNewer, newer);
        expect(reconstructedOlder, older);
      },
    );

    test('empty older string yields all-added segments equal to newer', () {
      const newer = 'Brand new fact text.';

      final result = wordDiff('', newer);

      expect(result, isNotEmpty);
      expect(result.every((s) => s.kind == DiffKind.added), isTrue);
      expect(result.map((s) => s.text).join(), newer);
    });

    test('empty newer string yields all-removed segments equal to older', () {
      const older = 'Old fact text.';

      final result = wordDiff(older, '');

      expect(result, isNotEmpty);
      expect(result.every((s) => s.kind == DiffKind.removed), isTrue);
      expect(result.map((s) => s.text).join(), older);
    });
  });
}
