// tentura-9f0 landing gate acceptance (trial merge tentura-rsm)

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:tentura/design_system/components/tentura_avatar.dart';
import 'package:tentura/design_system/components/tentura_avatar_stack.dart';
import 'package:tentura/design_system/tentura_design_system.dart';
import 'package:tentura/domain/entity/profile.dart';

Future<void> _pumpAvatarStack(
  WidgetTester tester, {
  required List<Profile> profiles,
  int max = 3,
}) async {
  await tester.pumpWidget(
    MaterialApp(
      theme: TenturaTheme.light(),
      home: TenturaResponsiveScope(
        child: Scaffold(
          body: Center(
            child: Builder(
              builder: (context) => TenturaAvatarStack(
                profiles: profiles,
                size: context.tt.metadataAvatarSize,
                max: max,
              ),
            ),
          ),
        ),
      ),
    ),
  );
  await tester.pumpAndSettle();
}

List<Profile> _profiles(int count) => [
  for (var i = 0; i < count; i++)
    Profile(id: 'p$i', displayName: 'Person $i'),
];

void main() {
  testWidgets('caps visible avatars at max without overflow badge', (
    tester,
  ) async {
    await _pumpAvatarStack(tester, profiles: _profiles(5), max: 3);

    expect(find.byType(TenturaAvatar), findsNWidgets(3));
    expect(find.textContaining('+'), findsNothing);
  });

  testWidgets('renders one avatar per profile when below max', (tester) async {
    await _pumpAvatarStack(tester, profiles: _profiles(2), max: 3);

    expect(find.byType(TenturaAvatar), findsNWidgets(2));
  });

  testWidgets('renders nothing when profiles is empty', (tester) async {
    await _pumpAvatarStack(tester, profiles: const [], max: 3);

    expect(find.byType(TenturaAvatar), findsNothing);
    expect(find.textContaining('+'), findsNothing);
  });
}
