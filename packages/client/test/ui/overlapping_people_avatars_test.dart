import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:tentura/design_system/tentura_design_system.dart';
import 'package:tentura/domain/entity/profile.dart';
import 'package:tentura/ui/widget/overlapping_people_avatars.dart';

void main() {
  testWidgets('OverlappingPeopleAvatars shows overflow badge text', (
    tester,
  ) async {
    final profiles = [
      const Profile(id: 'a', displayName: 'Alice'),
      const Profile(id: 'b', displayName: 'Bob'),
    ];

    await tester.pumpWidget(
      MaterialApp(
        theme: TenturaTheme.light(),
        home: Scaffold(
          body: Center(
            child: OverlappingPeopleAvatars(
              profiles: profiles,
              overflowCount: 3,
            ),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();

    expect(find.text('+3'), findsOneWidget);
    expect(find.byType(OverlappingPeopleAvatars), findsOneWidget);
  });
}
