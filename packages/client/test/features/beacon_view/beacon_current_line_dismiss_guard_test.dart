import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:get_it/get_it.dart';

import 'package:tentura/design_system/tentura_theme.dart';
import 'package:tentura/features/beacon_view/ui/widget/beacon_current_line_sheet.dart';
import 'package:tentura/features/coordination_item/domain/use_case/coordination_item_case.dart';
import 'package:tentura/ui/l10n/l10n.dart';

import '../beacon_room/fake_coordination_item_case.dart';

Future<void> _pumpSheet(
  WidgetTester tester, {
  String initialText = 'Ship the beta',
}) async {
  await tester.pumpWidget(
    MaterialApp(
      locale: const Locale('en'),
      localizationsDelegates: L10n.localizationsDelegates,
      supportedLocales: L10n.supportedLocales,
      theme: TenturaTheme.light(),
      home: Scaffold(
        body: Builder(
          builder: (context) => TextButton(
            onPressed: () => showBeaconCurrentLineSheet(
              context,
              beaconId: 'beacon-1',
              initialText: initialText,
            ),
            child: const Text('open'),
          ),
        ),
      ),
    ),
  );
  await tester.pumpAndSettle();
  await tester.tap(find.text('open'));
  await tester.pumpAndSettle();
}

void main() {
  setUp(() {
    if (GetIt.I.isRegistered<CoordinationItemCase>()) {
      GetIt.I.unregister<CoordinationItemCase>();
    }
    GetIt.I.registerSingleton<CoordinationItemCase>(
      const FakeCoordinationItemCaseForRoom(),
    );
  });

  tearDown(() async {
    if (GetIt.I.isRegistered<CoordinationItemCase>()) {
      await GetIt.I.unregister<CoordinationItemCase>();
    }
  });

  testWidgets('Barrier tap with unchanged text closes immediately', (
    tester,
  ) async {
    await _pumpSheet(tester);

    expect(find.byType(TextField), findsOneWidget);

    await tester.tapAt(const Offset(20, 20));
    await tester.pumpAndSettle();

    expect(find.text('Discard changes?'), findsNothing);
    expect(find.byType(TextField), findsNothing);
  });

  testWidgets('Barrier tap with edited text prompts discard', (tester) async {
    await _pumpSheet(tester);

    await tester.enterText(find.byType(TextField), 'New plan line');
    await tester.pumpAndSettle();

    await tester.tapAt(const Offset(20, 20));
    await tester.pumpAndSettle();

    expect(find.text('Discard changes?'), findsOneWidget);
    expect(find.byType(TextField), findsOneWidget);

    await tester.tap(find.text('Discard'));
    await tester.pumpAndSettle();

    expect(find.byType(TextField), findsNothing);
  });
}
