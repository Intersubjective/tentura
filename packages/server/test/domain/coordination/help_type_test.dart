import 'package:test/test.dart';

import 'package:tentura_server/domain/capability/capability_tag.dart';
import 'package:tentura_server/domain/coordination/help_type.dart';

void main() {
  group('isAllowedHelpType', () {
    test('accepts null and empty', () {
      expect(isAllowedHelpType(null), isTrue);
      expect(isAllowedHelpType(''), isTrue);
    });

    test('accepts allowed capability slugs', () {
      expect(isAllowedHelpType('transport'), isTrue);
      expect(isAllowedHelpType('introductions'), isTrue);
    });

    test('rejects unknown slugs', () {
      expect(isAllowedHelpType('unknown_capability'), isFalse);
    });

    test('every allowed slug passes validation', () {
      for (final slug in kAllowedCapabilitySlugs) {
        expect(isAllowedHelpType(slug), isTrue, reason: slug);
      }
    });
  });
}
