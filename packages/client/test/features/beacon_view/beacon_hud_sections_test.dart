import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:tentura_root/domain/entity/beacon_status.dart';

import 'package:tentura/design_system/tentura_design_system.dart';
import 'package:tentura/domain/entity/beacon.dart';
import 'package:tentura/features/beacon_view/ui/widget/beacon_hud_sections.dart';
import 'package:tentura/ui/l10n/l10n.dart';

Future<void> _pump(WidgetTester tester, Widget child) => tester.pumpWidget(
  MaterialApp(
    theme: TenturaTheme.light(),
    localizationsDelegates: L10n.localizationsDelegates,
    supportedLocales: L10n.supportedLocales,
    home: Scaffold(body: child),
  ),
);

Beacon _beacon(BeaconStatus status, {String description = ''}) =>
    Beacon.empty.copyWith(status: status, description: description);

void main() {
  group('BeaconHudOutcomeSection', () {
    testWidgets('a live Request has no outcome', (tester) async {
      await _pump(
        tester,
        BeaconHudOutcomeSection(beacon: _beacon(BeaconStatus.open)),
      );
      expect(find.text('OUTCOME'), findsNothing);
    });

    testWidgets('a closed Request is completed and its chat readable', (
      tester,
    ) async {
      await _pump(
        tester,
        BeaconHudOutcomeSection(beacon: _beacon(BeaconStatus.closed)),
      );
      expect(find.text('OUTCOME'), findsOneWidget);
      expect(find.text('Completed'), findsOneWidget);
      expect(
        find.text('No new offers or messages. The chat stays readable.'),
        findsOneWidget,
      );
    });

    testWidgets('a cancelled Request says so', (tester) async {
      await _pump(
        tester,
        BeaconHudOutcomeSection(beacon: _beacon(BeaconStatus.cancelled)),
      );
      expect(find.text('Cancelled'), findsOneWidget);
    });

    testWidgets('a deleted Request carries no chat note', (tester) async {
      await _pump(
        tester,
        BeaconHudOutcomeSection(beacon: _beacon(BeaconStatus.deleted)),
      );
      expect(find.text('Deleted'), findsOneWidget);
      expect(
        find.text('No new offers or messages. The chat stays readable.'),
        findsNothing,
      );
    });
  });

  group('BeaconHudEssenceSection', () {
    testWidgets('shows the pitch under a header and opens Details', (
      tester,
    ) async {
      var opened = 0;
      const pitch = 'We build three garden beds.\nBring gloves.';
      await _pump(
        tester,
        BeaconHudEssenceSection(
          beacon: _beacon(BeaconStatus.open, description: pitch),
          onOpenDetails: () => opened++,
        ),
      );
      expect(find.text('ABOUT'), findsOneWidget);
      final text = tester.widget<Text>(find.text(pitch));
      expect(text.maxLines, BeaconHudEssenceSection.collapsedLines);
      await tester.tap(find.text('Details'));
      expect(opened, 1);
    });
  });
}
