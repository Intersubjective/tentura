import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:tentura/ui/widget/beacon_photo_count.dart';

void main() {
  testWidgets('BeaconPhotoCount hides when count is 0', (tester) async {
    await tester.pumpWidget(
      const MaterialApp(
        home: Scaffold(
          body: BeaconPhotoCount(count: 0),
        ),
      ),
    );
    expect(find.byType(BeaconPhotoCount), findsOneWidget);
    expect(find.byIcon(Icons.photo_library_outlined), findsNothing);
  });

  testWidgets('BeaconPhotoCount shows count and caps at 99+', (tester) async {
    await tester.pumpWidget(
      const MaterialApp(
        home: Scaffold(
          body: Column(
            children: [
              BeaconPhotoCount(count: 3),
              BeaconPhotoCount(count: 100),
            ],
          ),
        ),
      ),
    );
    expect(find.text('3'), findsOneWidget);
    expect(find.text('99+'), findsOneWidget);
  });
}
