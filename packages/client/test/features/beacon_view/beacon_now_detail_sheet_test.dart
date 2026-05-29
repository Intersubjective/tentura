import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:tentura/design_system/tentura_design_system.dart';
import 'package:tentura/domain/entity/beacon_room_state.dart';
import 'package:tentura/domain/entity/coordination_item.dart';
import 'package:tentura/features/beacon_view/ui/util/beacon_hud_derivation.dart';
import 'package:tentura/features/beacon_view/ui/widget/beacon_now_detail_sheet.dart';
import 'package:tentura/ui/l10n/l10n.dart';
import 'package:tentura/ui/widget/hud_labeled_multiline.dart';

void main() {
  Future<void> pumpSheet(
    WidgetTester tester,
    BeaconNowDetailModel model,
  ) async {
    await tester.pumpWidget(
      MaterialApp(
        locale: const Locale('en'),
        theme: TenturaTheme.light(),
        localizationsDelegates: L10n.localizationsDelegates,
        supportedLocales: L10n.supportedLocales,
        home: TenturaResponsiveScope(
          child: Builder(
            builder: (context) => Scaffold(
              body: Center(
                child: FilledButton(
                  onPressed: () => showBeaconNowDetailSheet(
                    context,
                    model: model,
                  ),
                  child: const Text('Open'),
                ),
              ),
            ),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();
    await tester.tap(find.text('Open'));
    await tester.pumpAndSettle();
  }

  testWidgets('detail sheet shows Whats next label and blocker row', (
    tester,
  ) async {
    final model = BeaconNowDetailModel(
      whatsNextText: 'Ship the beta build tonight',
      blockerTitle: 'Waiting on credentials',
      blockerItem: CoordinationItem(
        id: 'b1',
        beaconId: 'beacon1',
        kind: CoordinationItemKind.blocker,
        status: CoordinationItemStatus.open,
        creatorId: 'u1',
        createdAt: DateTime.utc(2025),
        updatedAt: DateTime.utc(2025),
        title: 'Waiting on credentials',
        body: 'Need admin access from IT',
      ),
    );

    await pumpSheet(tester, model);

    expect(find.text("What's next?"), findsOneWidget);
    expect(find.text('Ship the beta build tonight'), findsOneWidget);
    expect(find.text('Waiting on credentials'), findsWidgets);
    expect(find.text('Need admin access from IT'), findsOneWidget);
  });

  testWidgets('room pin uses NOW label not Whats next strip label', (
    tester,
  ) async {
    final l10n = lookupL10n(const Locale('en'));
    final display = beaconRoomHudNowDisplay(
      l10n,
      roomState: BeaconRoomState(
        beaconId: 'b1',
        updatedAt: DateTime.utc(2025),
        currentLine: 'Coordinate pickup at noon',
      ),
    );

    await tester.pumpWidget(
      MaterialApp(
        locale: const Locale('en'),
        theme: TenturaTheme.light(),
        localizationsDelegates: L10n.localizationsDelegates,
        supportedLocales: L10n.supportedLocales,
        home: TenturaResponsiveScope(
          child: Scaffold(
            body: HudLabeledMultiline(
              label: l10n.beaconHudNowLabel,
              text: display.primaryText,
              mutedColor: Colors.grey,
              onShowDetail: () {},
            ),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();

    expect(find.text(l10n.beaconHudNowLabel), findsOneWidget);
    expect(find.text(l10n.beaconRoomStripCurrentLineLabel), findsNothing);
    expect(find.text('Coordinate pickup at noon'), findsOneWidget);
  });
}
