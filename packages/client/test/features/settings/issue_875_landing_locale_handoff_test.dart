import 'package:flutter_test/flutter_test.dart';

import 'package:tentura/app/platform/landing_locale_handoff_logic.dart';
import 'package:tentura/features/settings/ui/bloc/settings_state.dart';

void main() {
  group('resolveLocalePreferenceAfterLandingHandoff', () {
    test('landing ru with no stored preference resolves to ru', () {
      expect(
        resolveLocalePreferenceAfterLandingHandoff(
          storedRaw: null,
          landingLangQuery: 'ru',
        ),
        kLocalePreferenceRu,
      );
    });

    test('no landing query keeps system when nothing stored', () {
      expect(
        resolveLocalePreferenceAfterLandingHandoff(
          storedRaw: null,
          landingLangQuery: null,
        ),
        kLocalePreferenceSystem,
      );
    });

    test('stored explicit en blocks a later landing ru hand-off', () {
      expect(
        resolveLocalePreferenceAfterLandingHandoff(
          storedRaw: kLocalePreferenceEn,
          landingLangQuery: 'ru',
        ),
        kLocalePreferenceEn,
      );
    });

    test('stored explicit ru blocks a later landing en hand-off', () {
      expect(
        resolveLocalePreferenceAfterLandingHandoff(
          storedRaw: kLocalePreferenceRu,
          landingLangQuery: 'en',
        ),
        kLocalePreferenceRu,
      );
    });

    test('system stored preference accepts landing ru', () {
      expect(
        resolveLocalePreferenceAfterLandingHandoff(
          storedRaw: kLocalePreferenceSystem,
          landingLangQuery: 'ru',
        ),
        kLocalePreferenceRu,
      );
    });
  });

  group('storedLocalePreferenceBlocksLandingHandoff', () {
    test('null and system do not block', () {
      expect(storedLocalePreferenceBlocksLandingHandoff(null), isFalse);
      expect(
        storedLocalePreferenceBlocksLandingHandoff(kLocalePreferenceSystem),
        isFalse,
      );
    });

    test('explicit en and ru block', () {
      expect(
        storedLocalePreferenceBlocksLandingHandoff(kLocalePreferenceEn),
        isTrue,
      );
      expect(
        storedLocalePreferenceBlocksLandingHandoff(kLocalePreferenceRu),
        isTrue,
      );
    });
  });
}
