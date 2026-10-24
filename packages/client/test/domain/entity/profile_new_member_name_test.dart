import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:tentura/domain/entity/profile.dart';
import 'package:tentura/domain/util/display_name_prompt.dart';
import 'package:tentura/ui/l10n/l10n.dart';

// #660 review: the server stores the English placeholder "New member"; the
// client shows it in the app language wherever a name is shown.
void main() {
  setUp(
    () => setNewMemberDisplayNameLabel(
      lookupL10n(const Locale('ru')).newMemberDisplayName,
    ),
  );
  tearDown(() => setNewMemberDisplayNameLabel(kNewMemberDisplayName));

  test('the Russian label is Новый участник', () {
    expect(
      lookupL10n(const Locale('ru')).newMemberDisplayName,
      'Новый участник',
    );
    expect(lookupL10n(const Locale('en')).newMemberDisplayName, 'New member');
  });

  test('a New member profile is shown in the app language', () {
    const profile = Profile(id: 'U1', displayName: 'New member');
    expect(profile.shownName, 'Новый участник');
    expect(profile.displayLabel('?'), 'Новый участник');
    expect(profile.canonicalPublicLabel, 'Новый участник');
    expect(profile.canonicalSecondaryLabel, isEmpty);
  });

  test('a New member with a handle keeps the handle as secondary', () {
    const profile = Profile(
      id: 'U1',
      displayName: 'New member',
      handle: 'anna',
    );
    expect(profile.canonicalPublicLabel, 'Новый участник · @anna');
    expect(profile.canonicalSecondaryLabel, '@anna');
  });

  test('the stored name itself stays the server constant', () {
    const profile = Profile(id: 'U1', displayName: 'New member');
    expect(profile.displayName, kNewMemberDisplayName);
    expect(profile.needsDisplayNamePrompt, isTrue);
  });

  test('guard: a contact name or a chosen name is not replaced', () {
    expect(
      const Profile(displayName: 'New member', contactName: 'Mom').shownName,
      'Mom',
    );
    expect(
      const Profile(displayName: 'New member Anna').shownName,
      'New member Anna',
    );
    expect(const Profile(displayName: 'Anna').shownName, 'Anna');
  });
}
