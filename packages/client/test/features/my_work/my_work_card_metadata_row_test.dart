import 'package:flutter/material.dart';
import 'package:tentura_root/domain/entity/beacon_status.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:tentura/design_system/tentura_theme.dart';
import 'package:tentura/domain/entity/beacon.dart';
import 'package:tentura/domain/entity/beacon_activity_event.dart';
import 'package:tentura/domain/entity/beacon_activity_event_consts.dart';
import 'package:tentura/domain/entity/coordinates.dart';
import 'package:tentura/domain/entity/coordination_responsibility.dart';
import 'package:tentura/domain/entity/profile.dart';
import 'package:tentura/features/my_work/domain/entity/my_work_card_view_model.dart';
import 'package:tentura/features/my_work/domain/entity/my_work_last_event.dart';
import 'package:tentura/features/my_work/ui/widget/my_work_card_metadata_row.dart';
import 'package:tentura/features/my_work/ui/widget/my_work_card_status_strip.dart';
import 'package:tentura/features/my_work/ui/widget/my_work_last_event_row.dart';
import 'package:tentura/ui/l10n/l10n.dart';
import 'package:tentura/ui/widget/beacon_compact_metadata_strip.dart';
import 'package:tentura/ui/widget/beacon_hud_metadata_table.dart';
import 'package:tentura/ui/widget/beacon_hud_row_lead.dart';
import 'package:tentura/ui/widget/overlapping_people_avatars.dart';

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
      startAt: DateTime.utc(2099, 12, 20, 12),
      endAt: DateTime.utc(2099, 12, 25, 12),
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
    expect(find.byIcon(Icons.event_outlined), findsOneWidget);
    expect(find.byIcon(BeaconHudRowIcons.people), findsOneWidget);
    expect(find.byType(MyWorkCardMetadataRow), findsOneWidget);
    expect(find.byType(MyWorkCardStatusStrip), findsNothing);
    expect(find.byType(BeaconCompactMetadataStrip), findsOneWidget);

    final strip = find.byType(BeaconCompactMetadataStrip);
    final pileRect = tester.getRect(
      find.descendant(
        of: strip,
        matching: find.byType(OverlappingPeopleAvatars),
      ),
    );
    final scheduleX = tester.getTopLeft(
      find.descendant(
        of: strip,
        matching: find.byIcon(Icons.event_outlined),
      ),
    ).dx;
    expect(scheduleX, greaterThan(pileRect.right));
    expect(scheduleX, greaterThan(180));
  });

  testWidgets('metadata row shows NOW icon above YOU icon', (tester) async {
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

    expect(find.text('NOW'), findsNothing);
    expect(find.text('YOU'), findsNothing);
    expect(find.text('Pick up supplies at noon'), findsOneWidget);
    expect(find.byIcon(BeaconHudRowIcons.now), findsOneWidget);
    expect(find.byIcon(BeaconHudRowIcons.you), findsOneWidget);

    final nowX = tester.getTopLeft(find.byIcon(BeaconHudRowIcons.now)).dx;
    final youX = tester.getTopLeft(find.byIcon(BeaconHudRowIcons.you)).dx;
    expect(nowX, youX);
  });

  testWidgets('segment YOU icon x-aligns with NOW and last-event icons', (
    tester,
  ) async {
    const authorId = 'author1';
    final beacon = Beacon.empty.copyWith(
      id: 'b-align',
      author: const Profile(id: authorId, displayName: 'Alice'),
      createdAt: DateTime(2026, 6, 10, 9),
      updatedAt: DateTime(2026, 6, 12, 9),
    );
    final last = MyWorkLastEvent(
      event: BeaconActivityEvent(
        id: 'e1',
        beaconId: beacon.id,
        visibility: 0,
        type: BeaconActivityEventTypeBits.beaconPublished,
        createdAt: DateTime.now().subtract(const Duration(hours: 3)),
        actorId: authorId,
      ),
      actor: const Profile(id: authorId, displayName: 'Alice'),
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
                    roomCurrentLine: 'Enough help — in motion',
                    youResponsibility: CoordinationResponsibility(
                      beaconId: beacon.id,
                      promiseOpen: 1,
                      promiseNew: 1,
                    ),
                    lastActivityEvent: last,
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

    final nowX = tester.getTopLeft(find.byIcon(BeaconHudRowIcons.now)).dx;
    final youX = tester.getTopLeft(find.byIcon(BeaconHudRowIcons.you)).dx;
    final historyX =
        tester.getTopLeft(find.byIcon(BeaconHudRowIcons.lastEvent)).dx;
    expect(nowX, youX);
    expect(nowX, historyX);
  });

  testWidgets('hidden YOU row omitted on compact width with empty obligation', (
    tester,
  ) async {
    final beacon = Beacon.empty.copyWith(
      id: 'b-hidden-you',
      author: const Profile(id: 'a1', displayName: 'Alice'),
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
                  viewModel: _viewModel(beacon).copyWith(
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

    expect(find.byIcon(BeaconHudRowIcons.you), findsNothing);
    expect(find.byType(BeaconHudMetadataTable), findsOneWidget);
  });

  testWidgets('metadata row uses wrap layout on very narrow width', (
    tester,
  ) async {
    final beacon = Beacon.empty.copyWith(
      id: 'b2',
      author: const Profile(id: 'a1', displayName: 'Alice'),
      helpOfferCount: 1,
      helpOfferUsers: const [Profile(id: 'h1', displayName: 'Bob')],
      startAt: DateTime.utc(2099, 6, 20, 12),
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

    final strip = find.byType(BeaconCompactMetadataStrip);
    final pileRect = tester.getRect(
      find.descendant(
        of: strip,
        matching: find.byType(OverlappingPeopleAvatars),
      ),
    );
    final scheduleX = tester.getTopLeft(
      find.descendant(
        of: strip,
        matching: find.byIcon(Icons.event_outlined),
      ),
    ).dx;
    expect(scheduleX, greaterThan(pileRect.right));
  });

  testWidgets('finished beacon hides NOW, YOU, and last-event rows', (
    tester,
  ) async {
    const authorId = 'author1';
    final beacon = Beacon.empty.copyWith(
      id: 'b-finished',
      status: BeaconStatus.closed,
      author: const Profile(id: authorId, displayName: 'Alice Author'),
      helpOfferCount: 1,
      helpOfferUsers: const [Profile(id: 'h1', displayName: 'Bob')],
      startAt: DateTime.utc(2099, 6, 20, 12),
      endAt: DateTime.utc(2099, 6, 25, 12),
      coordinates: const Coordinates(lat: 52.52, long: 13.405),
    );
    final last = MyWorkLastEvent(
      event: BeaconActivityEvent(
        id: 'e1',
        beaconId: beacon.id,
        visibility: 0,
        type: BeaconActivityEventTypeBits.beaconPublished,
        createdAt: DateTime.now().subtract(const Duration(hours: 3)),
        actorId: authorId,
      ),
      actor: const Profile(id: authorId, displayName: 'Alice Author'),
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
                  viewModel: MyWorkCardViewModel(
                    beaconId: beacon.id,
                    role: MyWorkCardRole.authored,
                    kind: MyWorkCardKind.authoredFinished,
                    beacon: beacon,
                    roomCurrentLine: 'Pick up supplies at noon',
                    youResponsibility: CoordinationResponsibility(
                      beaconId: beacon.id,
                    ),
                    lastActivityEvent: last,
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

    expect(find.byType(BeaconCompactMetadataStrip), findsOneWidget);
    expect(find.byIcon(BeaconHudRowIcons.now), findsNothing);
    expect(find.byIcon(BeaconHudRowIcons.you), findsNothing);
    expect(find.byIcon(BeaconHudRowIcons.lastEvent), findsNothing);
    expect(find.byType(MyWorkLastEventBody), findsNothing);
    expect(find.text('Pick up supplies at noon'), findsNothing);
  });
}
