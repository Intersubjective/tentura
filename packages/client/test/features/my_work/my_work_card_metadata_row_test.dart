import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:tentura/design_system/tentura_theme.dart';
import 'package:tentura/domain/entity/beacon.dart';
import 'package:tentura/domain/entity/coordinates.dart';
import 'package:tentura/domain/entity/coordination_responsibility.dart';
import 'package:tentura/domain/entity/profile.dart';
import 'package:tentura/features/my_work/domain/entity/my_work_card_view_model.dart';
import 'package:tentura/features/my_work/ui/widget/my_work_card_metadata_row.dart';
import 'package:tentura/ui/l10n/l10n.dart';

MyWorkCardViewModel _viewModel(Beacon beacon) => MyWorkCardViewModel(
  beaconId: beacon.id,
  role: MyWorkCardRole.authored,
  kind: MyWorkCardKind.authoredActive,
  beacon: beacon,
);

void main() {
  testWidgets('metadata row shows schedule and location at 360px', (
    tester,
  ) async {
    final beacon = Beacon.empty.copyWith(
      id: 'b1',
      author: const Profile(id: 'a1', displayName: 'Alice'),
      helpOfferCount: 1,
      helpOfferUsers: const [Profile(id: 'h1', displayName: 'Bob')],
      startAt: DateTime.utc(2099, 6, 20, 12),
      endAt: DateTime.utc(2099, 6, 25, 12),
      coordinates: const Coordinates(lat: 52.52, long: 13.405),
      createdAt: DateTime(2026, 6, 10, 9),
      updatedAt: DateTime(2026, 6, 10, 10),
    );

    await tester.pumpWidget(
      MaterialApp(
        theme: TenturaTheme.light(),
        localizationsDelegates: L10n.localizationsDelegates,
        supportedLocales: L10n.supportedLocales,
        locale: const Locale('en'),
        home: MediaQuery(
          data: const MediaQueryData(size: Size(360, 800)),
          child: Scaffold(
            body: Center(
              child: SizedBox(
                width: 360,
                child: MyWorkCardMetadataRow(
                  beacon: beacon,
                  viewModel: _viewModel(beacon),
                  currentUserId: 'viewer',
                ),
              ),
            ),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();

    expect(find.textContaining('updated'), findsOneWidget);
    expect(find.byIcon(Icons.schedule_outlined), findsOneWidget);
    expect(find.byType(MyWorkCardMetadataRow), findsOneWidget);
  });

  testWidgets('metadata row shows NOW label above YOU', (tester) async {
    final beacon = Beacon.empty.copyWith(
      id: 'b-now',
      author: const Profile(id: 'a1', displayName: 'Alice'),
    );

    await tester.pumpWidget(
      MaterialApp(
        theme: TenturaTheme.light(),
        localizationsDelegates: L10n.localizationsDelegates,
        supportedLocales: L10n.supportedLocales,
        locale: const Locale('en'),
        home: MediaQuery(
          data: const MediaQueryData(size: Size(360, 800)),
          child: Scaffold(
            body: Center(
              child: SizedBox(
                width: 360,
                child: MyWorkCardMetadataRow(
                  beacon: beacon,
                  viewModel: _viewModel(beacon).copyWith(
                    roomCurrentLine: 'Pick up supplies at noon',
                    youResponsibility: CoordinationResponsibility(
                      beaconId: beacon.id,
                    ),
                  ),
                  currentUserId: 'viewer',
                ),
              ),
            ),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();

    final l10n = lookupL10n(const Locale('en'));
    expect(find.text(l10n.beaconHudNowLabel), findsOneWidget);
    expect(find.text('Pick up supplies at noon'), findsOneWidget);
    expect(find.text(l10n.beaconHudYouLabel), findsOneWidget);
  });

  testWidgets('metadata row uses wrap layout on very narrow width', (
    tester,
  ) async {
    final beacon = Beacon.empty.copyWith(
      id: 'b2',
      endAt: DateTime(2026, 6, 25, 12),
      coordinates: const Coordinates(lat: 52.52, long: 13.405),
    );

    await tester.pumpWidget(
      MaterialApp(
        theme: TenturaTheme.light(),
        localizationsDelegates: L10n.localizationsDelegates,
        supportedLocales: L10n.supportedLocales,
        locale: const Locale('en'),
        home: MediaQuery(
          data: const MediaQueryData(size: Size(300, 800)),
          child: Scaffold(
            body: Center(
              child: SizedBox(
                width: 300,
                child: MyWorkCardMetadataRow(
                  beacon: beacon,
                  viewModel: _viewModel(beacon),
                  currentUserId: 'viewer',
                ),
              ),
            ),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();

    expect(find.byType(Wrap), findsOneWidget);
  });
}
