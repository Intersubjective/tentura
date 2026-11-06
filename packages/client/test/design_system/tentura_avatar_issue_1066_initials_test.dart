// #1066: two-word names like «Bob Q1106» vs «Boris Q912» used to show the same «BQ»
// initials; second word Q + digits now contributes the last digit as the second glyph.

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:tentura/design_system/components/tentura_avatar.dart';
import 'package:tentura/design_system/tentura_theme.dart';
import 'package:tentura/domain/entity/profile.dart';

void main() {
  testWidgets(
    'Q-code second word uses last digit so BQ collisions differ (#1066)',
    (tester) async {
      Future<void> pump(Profile p) => tester.pumpWidget(
        MaterialApp(
          theme: TenturaTheme.light(),
          home: Scaffold(
            body: Center(
              child: TenturaAvatar.medium(profile: p),
            ),
          ),
        ),
      );

      await pump(
        const Profile(id: 'user-bob', displayName: 'Bob Q1106'),
      );
      expect(find.text('B6'), findsOneWidget);

      await pump(
        const Profile(id: 'user-boris', displayName: 'Boris Q912'),
      );
      expect(find.text('B2'), findsOneWidget);
    },
  );

  testWidgets('initials are stable across rebuilds for the same profile', (
    tester,
  ) async {
    const profile = Profile(id: 'stable-id', displayName: 'Bob Q1106');
    await tester.pumpWidget(
      MaterialApp(
        theme: TenturaTheme.light(),
        home: Scaffold(
          body: Center(child: TenturaAvatar.medium(profile: profile)),
        ),
      ),
    );
    expect(find.text('B6'), findsOneWidget);
    await tester.pumpWidget(
      MaterialApp(
        theme: TenturaTheme.light(),
        home: Scaffold(
          body: Center(child: TenturaAvatar.medium(profile: profile)),
        ),
      ),
    );
    expect(find.text('B6'), findsOneWidget);
  });

  test('initialsForProfile keeps ordinary two-word names as first letters', () {
    expect(
      TenturaAvatar.initialsForProfile(
        const Profile(id: 'a', displayName: 'Ada Lovelace'),
      ),
      'AL',
    );
    expect(
      TenturaAvatar.initialsForProfile(
        const Profile(id: 'b', displayName: 'Олег Петров'),
      ),
      'ОП',
    );
  });

  test('case-insensitive Q prefix matches q123', () {
    expect(
      TenturaAvatar.initialsForProfile(
        const Profile(id: 'c', displayName: 'Bob q99'),
      ),
      'B9',
    );
  });
}
