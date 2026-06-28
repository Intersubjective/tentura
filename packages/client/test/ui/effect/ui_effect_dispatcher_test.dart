import 'package:flutter_test/flutter_test.dart';
import 'package:tentura/ui/effect/ui_effect_dispatcher.dart';

void main() {
  group('maybePopOrReplaceWithHomeForTesting', () {
    test('does not replace home when the current route pops', () async {
      var replaceCount = 0;
      Object? observedResult;

      await maybePopOrReplaceWithHomeForTesting(
        result: 'done',
        maybePop: (result) async {
          observedResult = result;
          return true;
        },
        replaceWithHome: () async {
          replaceCount++;
        },
      );

      expect(observedResult, 'done');
      expect(replaceCount, 0);
    });

    test('replaces home when the current route cannot pop', () async {
      var replaceCount = 0;

      await maybePopOrReplaceWithHomeForTesting(
        maybePop: (_) async => false,
        replaceWithHome: () async {
          replaceCount++;
        },
      );

      expect(replaceCount, 1);
    });
  });
}
