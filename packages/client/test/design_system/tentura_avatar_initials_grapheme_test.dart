// #1093 — emoji-leading and grapheme-safe initials (no UTF-16 surrogate splits).

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:tentura/design_system/tentura_design_system.dart';
import 'package:tentura/domain/entity/profile.dart';

Future<void> _pump(WidgetTester tester, Profile profile) => tester.pumpWidget(
  MaterialApp(
    theme: TenturaTheme.light(),
    home: Scaffold(
      body: Center(
        child: TenturaAvatar.medium(profile: profile),
      ),
    ),
  ),
);

void main() {
  test('emoji-leading two-word name uses letter initials', () {
    expect(
      TenturaAvatar.initialsForProfile(
        const Profile(id: 'u1', displayName: '😃 Bob Q'),
      ),
      'BQ',
    );
  });

  test('emoji-only name uses first two graphemes as fallback', () {
    expect(
      TenturaAvatar.initialsForProfile(
        const Profile(id: 'u1', displayName: '😀🎉'),
      ),
      '😀🎉',
    );
  });

  test('single emoji name shows that grapheme', () {
    expect(
      TenturaAvatar.initialsForProfile(const Profile(id: 'u1', displayName: '😀')),
      '😀',
    );
  });

  test('combining sequence: two letter clusters from one word', () {
    expect(
      TenturaAvatar.initialsForProfile(
        const Profile(id: 'u1', displayName: 'o\u0308leg'),
      ),
      // Uppercase keeps NFD (O + combining diaeresis), distinct from precomposed Ö.
      'O\u0308L',
    );
  });

  test('contact alias is used for initials when set', () {
    expect(
      TenturaAvatar.initialsForProfile(
        const Profile(
          id: 'u1',
          displayName: 'Objective X',
          contactName: '😃 Zara M',
        ),
      ),
      'ZM',
    );
  });

  testWidgets('paints non-empty initials for emoji-leading name', (
    tester,
  ) async {
    await _pump(
      tester,
      const Profile(id: 'u1', displayName: '😃 Bob Q'),
    );
    await tester.pumpAndSettle();

    expect(find.text('BQ'), findsOneWidget);
  });
}
