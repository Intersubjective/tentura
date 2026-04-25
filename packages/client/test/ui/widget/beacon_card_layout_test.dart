import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:tentura/domain/entity/beacon.dart';
import 'package:tentura/domain/entity/profile.dart';
import 'package:tentura/ui/widget/beacon_card_primitives.dart';
import 'package:tentura/ui/widget/beacon_identity_tile.dart';

void main() {
  testWidgets('compact header uses 40px identity and title max two lines at 360px', (
    tester,
  ) async {
    final beacon = Beacon.empty.copyWith(
      createdAt: DateTime(2025, 1, 1),
      updatedAt: DateTime(2025, 4, 18, 17, 6),
      id: 'b1',
      title:
          '"Sweet spot": разгребаем завалы и длинный хвост чтобы title занял две строки',
      context: 'General',
      author: const Profile(id: 'a1', title: 'Fionna Campbell'),
    );

    await tester.pumpWidget(
      MaterialApp(
        home: MediaQuery(
          data: const MediaQueryData(size: Size(360, 800)),
          child: Scaffold(
            body: Center(
              child: SizedBox(
                width: 360,
                child: BeaconCardShell(
                  child: BeaconCardHeaderRow(
                    beacon: beacon,
                    menu: const SizedBox(
                      width: 32,
                      height: 40,
                      child: Placeholder(),
                    ),
                  ),
                ),
              ),
            ),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();

    final box = tester.getSize(find.byType(BeaconIdentityTile));
    expect(box.width, 40);
    expect(box.height, 40);

    final titleFinder = find.textContaining('"Sweet spot"', findRichText: true);
    expect(titleFinder, findsOneWidget);
    final renderObject = tester.renderObject<RenderParagraph>(titleFinder);
    expect(renderObject.size.height <= 50, isTrue);
  });
}
