import 'package:flutter/material.dart';
import 'package:tentura_root/domain/entity/beacon_status.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:tentura/design_system/tentura_design_system.dart';
import 'package:tentura/domain/entity/beacon.dart';
import 'package:tentura/features/beacon_view/domain/beacon_status_menu.dart';
import 'package:tentura/features/beacon_view/ui/widget/beacon_view_status_bottom_sheet.dart';
import 'package:tentura/ui/l10n/l10n.dart';

void main() {
  testWidgets('disabled status row shows hint when sheet passes null onTap', (
    tester,
  ) async {
    final beacon = Beacon.empty.copyWith(
      id: 'b1',
      status: BeaconStatus.open,
      helpOfferCount: 2,
    );
    const row = BeaconStatusMenuRow(
      id: BeaconStatusMenuRowId.closed,
      action: BeaconStatusMenuAction.closeDirect,
      isSelected: false,
      isEnabled: false,
      disabledReason: BeaconStatusMenuDisabledReason.finishReviewFirst,
    );

    await tester.pumpWidget(
      MaterialApp(
        locale: const Locale('en'),
        theme: TenturaTheme.light(),
        localizationsDelegates: L10n.localizationsDelegates,
        supportedLocales: L10n.supportedLocales,
        home: TenturaResponsiveScope(
          child: Scaffold(
            body: BeaconStatusMenuRowTile(
              row: row,
              beacon: beacon,
              isLoading: false,
              onTap: null,
            ),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();

    final l10n = lookupL10n(const Locale('en'));
    expect(
      find.text(l10n.beaconStatusHintFinishReviewFirst),
      findsOneWidget,
    );

    final listTile = tester.widget<ListTile>(find.byType(ListTile));
    expect(listTile.enabled, isFalse);
    expect(listTile.onTap, isNull);
    expect(listTile.subtitle, isNotNull);
  });

  testWidgets('enabled status row shows outcome subtitle', (tester) async {
    final beacon = Beacon.empty.copyWith(
      id: 'b1',
      status: BeaconStatus.open,
    );
    const row = BeaconStatusMenuRow(
      id: BeaconStatusMenuRowId.open,
      action: BeaconStatusMenuAction.setCoordinationNeutral,
      isSelected: true,
      isEnabled: true,
      disabledReason: BeaconStatusMenuDisabledReason.none,
    );

    await tester.pumpWidget(
      MaterialApp(
        locale: const Locale('en'),
        theme: TenturaTheme.light(),
        localizationsDelegates: L10n.localizationsDelegates,
        supportedLocales: L10n.supportedLocales,
        home: TenturaResponsiveScope(
          child: Scaffold(
            body: BeaconStatusMenuRowTile(
              row: row,
              beacon: beacon,
              isLoading: false,
              onTap: () {},
            ),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();

    final l10n = lookupL10n(const Locale('en'));
    expect(find.text(l10n.beaconStatusRowOutcomeOpen), findsOneWidget);
  });
}
