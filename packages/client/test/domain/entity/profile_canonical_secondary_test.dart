import 'package:flutter_test/flutter_test.dart';

import 'package:tentura/domain/entity/profile.dart';

void main() {
  group('Profile.canonicalSecondaryLabel', () {
    test('alias Mom, public Alice, handle alice → Alice · @alice', () {
      const profile = Profile(
        contactName: 'Mom',
        displayName: 'Alice',
        handle: 'alice',
      );
      expect(profile.shownName, 'Mom');
      expect(profile.canonicalSecondaryLabel, 'Alice · @alice');
    });

    test('alias equals public, handle set → @alice', () {
      const profile = Profile(
        contactName: 'Alice',
        displayName: 'Alice',
        handle: 'alice',
      );
      expect(profile.shownName, 'Alice');
      expect(profile.canonicalSecondaryLabel, '@alice');
    });

    test('no alias, handle set → secondary is @handle', () {
      const profile = Profile(
        displayName: 'Alice',
        handle: 'alice',
      );
      expect(profile.shownName, 'Alice');
      expect(profile.canonicalSecondaryLabel, '@alice');
    });

    test('no alias, no handle → empty', () {
      const profile = Profile(displayName: 'Alice');
      expect(profile.canonicalSecondaryLabel, isEmpty);
    });

    test('empty shownName + handle → @handle', () {
      const profile = Profile(handle: 'alice');
      expect(profile.shownName, isEmpty);
      expect(profile.canonicalSecondaryLabel, '@alice');
    });

    test('empty profile → empty', () {
      const profile = Profile();
      expect(profile.canonicalSecondaryLabel, isEmpty);
    });
  });

  group('Profile.canonicalPublicLabel', () {
    test('joins displayName and handle', () {
      const profile = Profile(displayName: 'Alice', handle: 'alice');
      expect(profile.canonicalPublicLabel, 'Alice · @alice');
    });

    test('displayName only', () {
      const profile = Profile(displayName: 'Alice');
      expect(profile.canonicalPublicLabel, 'Alice');
    });

    test('handle only', () {
      const profile = Profile(handle: 'alice');
      expect(profile.canonicalPublicLabel, '@alice');
    });

    test('both empty', () {
      const profile = Profile();
      expect(profile.canonicalPublicLabel, isEmpty);
    });
  });
}
