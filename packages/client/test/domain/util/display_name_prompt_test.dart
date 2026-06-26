import 'package:flutter_test/flutter_test.dart';
import 'package:tentura/domain/util/display_name_prompt.dart';

void main() {
  group('needsDisplayNamePromptFor', () {
    test('empty name needs prompt', () {
      expect(needsDisplayNamePromptFor(''), isTrue);
      expect(needsDisplayNamePromptFor('   '), isTrue);
    });

    test('email-derived lowercase with digits needs prompt', () {
      expect(needsDisplayNamePromptFor('agent 3c4703tb'), isTrue);
    });

    test('chosen mixed-case name does not need prompt', () {
      expect(needsDisplayNamePromptFor('Ada Lovelace'), isFalse);
    });

    test('lowercase name without digits does not need prompt', () {
      expect(needsDisplayNamePromptFor('ada lovelace'), isFalse);
    });
  });
}
