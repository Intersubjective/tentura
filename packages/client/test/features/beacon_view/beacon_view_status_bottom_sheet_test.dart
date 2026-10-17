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
  Widget host(Widget child) => MaterialApp(
    locale: const Locale('en'),
    theme: TenturaTheme.light(),
    localizationsDelegates: L10n.localizationsDelegates,
    supportedLocales: L10n.supportedLocales,
    home: TenturaResponsiveScope(child: Scaffold(body: child)),
  );

  const reviewRow = BeaconStatusMenuRow(
    id: BeaconStatusMenuRowId.wrappingUp,
    action: BeaconStatusMenuAction.openReview,
    isSelected: true,
    isEnabled: true,
    disabledReason: BeaconStatusMenuDisabledReason.none,
  );

  testWidgets('enabled wrapping-up row says it opens the sum-up', (
    tester,
  ) async {
    final beacon = Beacon.empty.copyWith(
      id: 'b1',
      status: BeaconStatus.reviewOpen,
    );
    await tester.pumpWidget(
      host(
        BeaconStatusMenuRowTile(
          row: reviewRow,
          beacon: beacon,
          isLoading: false,
          onTap: () {},
        ),
      ),
    );
    await tester.pumpAndSettle();

    final l10n = lookupL10n(const Locale('en'));
    expect(find.text(l10n.beaconStatusRowOutcomeSumUp), findsOneWidget);
    expect(find.text(l10n.beaconStatusRowOutcomeWrappingUp), findsNothing);
  });

  testWidgets('tapping a row closes only the sheet, not the page under it', (
    tester,
  ) async {
    final beacon = Beacon.empty.copyWith(
      id: 'b1',
      status: BeaconStatus.reviewOpen,
    );
    var tapped = 0;
    await tester.pumpWidget(
      host(
        Builder(
          builder: (context) => TextButton(
            onPressed: () => showModalBottomSheet<void>(
              context: context,
              builder: (_) => BeaconStatusMenuRowTile(
                row: reviewRow,
                beacon: beacon,
                isLoading: false,
                onTap: () => tapped++,
              ),
            ),
            child: const Text('Request page'),
          ),
        ),
      ),
    );
    await tester.tap(find.text('Request page'));
    await tester.pumpAndSettle();
    await tester.tap(
      find.descendant(
        of: find.byType(BeaconStatusMenuRowTile),
        matching: find.byType(ListTile),
      ),
    );
    await tester.pumpAndSettle();

    expect(tapped, 1);
    expect(find.byType(BeaconStatusMenuRowTile), findsNothing);
    expect(find.text('Request page'), findsOneWidget);
  });
}
