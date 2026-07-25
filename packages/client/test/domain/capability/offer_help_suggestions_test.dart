import 'package:flutter_test/flutter_test.dart';

import 'package:tentura/domain/capability/capability_tag.dart';
import 'package:tentura/domain/capability/offer_help_classification.dart';
import 'package:tentura/domain/capability/offer_help_suggestions.dart';

void main() {
  group('keywordHintsFromOfferMessage', () {
    test('maps sewing / costume to manual_work', () {
      expect(
        keywordHintsFromOfferMessage('I can help with the costume'),
        contains(CapabilityTag.manualWork.slug),
      );
      expect(
        keywordHintsFromOfferMessage('могу шить костюм'),
        contains(CapabilityTag.manualWork.slug),
      );
    });

    test('maps lift/carry to physical_help', () {
      expect(
        keywordHintsFromOfferMessage('I can lift heavy boxes'),
        contains(CapabilityTag.physicalHelp.slug),
      );
    });

    test('returns empty for blank message', () {
      expect(keywordHintsFromOfferMessage(''), isEmpty);
      expect(keywordHintsFromOfferMessage('   '), isEmpty);
    });
  });

  group('suggestOfferHelpSlugs', () {
    test('prioritizes automatic needs, then keyword hints', () {
      final slugs = suggestOfferHelpSlugs(
        message: 'I can sew the costume',
        automaticSlugs: {CapabilityTag.transport.slug},
      );
      expect(slugs.first, CapabilityTag.transport.slug);
      expect(slugs, contains(CapabilityTag.manualWork.slug));
      expect(slugs, isNot(contains(CapabilityTag.other.slug)));
    });

    test('returns empty without message or needs', () {
      expect(
        suggestOfferHelpSlugs(message: '', automaticSlugs: {}),
        isEmpty,
      );
    });

    test('caps at maxSuggestions', () {
      final needs = {
        for (final t in CapabilityTag.values.take(8)) t.slug,
      };
      final slugs = suggestOfferHelpSlugs(
        message: '',
        automaticSlugs: needs,
        maxSuggestions: 6,
      );
      expect(slugs.length, 6);
    });

    test('skips unknown and other automatic slugs', () {
      expect(
        suggestOfferHelpSlugs(
          message: '',
          automaticSlugs: {
            'not_a_real_slug',
            CapabilityTag.other.slug,
          },
        ),
        isEmpty,
      );
    });
  });

  group('resolveOfferHelpClassificationPath', () {
    test('textOnly when no chips', () {
      expect(
        resolveOfferHelpClassificationPath(
          selectedSlugs: {},
          suggestedSlugsAtSubmit: {CapabilityTag.other.slug},
          browsedFullTaxonomy: false,
        ),
        OfferHelpClassificationPath.textOnly,
      );
    });

    test('suggestedChip when selection subset of suggestions', () {
      expect(
        resolveOfferHelpClassificationPath(
          selectedSlugs: {CapabilityTag.manualWork.slug},
          suggestedSlugsAtSubmit: {
            CapabilityTag.manualWork.slug,
            CapabilityTag.other.slug,
          },
          browsedFullTaxonomy: false,
        ),
        OfferHelpClassificationPath.suggestedChip,
      );
    });

    test('fullBrowser when browse was opened', () {
      expect(
        resolveOfferHelpClassificationPath(
          selectedSlugs: {CapabilityTag.other.slug},
          suggestedSlugsAtSubmit: {CapabilityTag.other.slug},
          browsedFullTaxonomy: true,
        ),
        OfferHelpClassificationPath.fullBrowser,
      );
    });

    test('fullBrowser when chip outside suggestions without browse flag', () {
      expect(
        resolveOfferHelpClassificationPath(
          selectedSlugs: {CapabilityTag.money.slug},
          suggestedSlugsAtSubmit: {CapabilityTag.other.slug},
          browsedFullTaxonomy: false,
        ),
        OfferHelpClassificationPath.fullBrowser,
      );
    });
  });
}
