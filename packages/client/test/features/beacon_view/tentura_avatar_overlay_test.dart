import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:tentura/design_system/components/tentura_avatar.dart';
import 'package:tentura/design_system/tentura_theme.dart';
import 'package:tentura/domain/entity/profile.dart';

void main() {
  testWidgets('TenturaAvatar shows initials when profile has no photo', (
    tester,
  ) async {
    const profile = Profile(id: 'u1', displayName: 'Ada Lovelace');
    await tester.pumpWidget(
      MaterialApp(
        theme: TenturaTheme.light(),
        home: const Scaffold(
          body: Center(
            child: TenturaAvatar.medium(profile: profile),
          ),
        ),
      ),
    );

    expect(find.text('AL'), findsOneWidget);
    expect(
      tester.getSize(find.byType(TenturaAvatar)).width,
      36,
    );
  });
}
