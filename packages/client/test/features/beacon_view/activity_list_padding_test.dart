import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:tentura/design_system/tentura_design_system.dart';
import 'package:tentura/domain/entity/beacon.dart';
import 'package:tentura/domain/entity/beacon_activity_event.dart';
import 'package:tentura/domain/entity/profile.dart';
import 'package:tentura/features/beacon_view/ui/widget/activity_list.dart';
import 'package:tentura/ui/l10n/l10n.dart';
import 'package:tentura_root/domain/entity/beacon_status.dart';

void main() {
  testWidgets('BeaconActivityList applies horizontal padding from tokens', (tester) async {
    final now = DateTime.utc(2026);
    final beacon = Beacon(
      id: 'B1',
      title: 'Test',
      createdAt: now,
      updatedAt: now,
      status: BeaconStatus.open,
      author: const Profile(id: 'U1', displayName: 'Author'),
    );

    final event = BeaconActivityEvent(
      id: 'E1',
      beaconId: 'B1',
      visibility: 1,
      type: 101, // coordination type
      createdAt: now,
      actorId: 'U1',
    );

    await tester.pumpWidget(
      MaterialApp(
        theme: TenturaTheme.light(),
        localizationsDelegates: L10n.localizationsDelegates,
        supportedLocales: L10n.supportedLocales,
        home: TenturaResponsiveScope(
          child: Scaffold(
            body: BeaconActivityList(
              timeline: const [],
              beacon: beacon,
              isAuthorView: true,
              roomActivityEvents: [event],
              coordinationLogOnly: true,
            ),
          ),
        ),
      ),
    );

    // Find the Padding widget that wraps the Column
    final paddingFinder = find.byType(Padding);
    final paddingWidget = tester.widget<Padding>(
      paddingFinder.at(0), // The first one should be our injected padding
    );

    final tt = tester.element(find.byType(BeaconActivityList)).tt;
    expect(paddingWidget.padding, EdgeInsets.symmetric(
      horizontal: tt.screenHPadding,
      vertical: tt.rowGap,
    ));
  });
}
