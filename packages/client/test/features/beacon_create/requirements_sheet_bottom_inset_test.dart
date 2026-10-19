import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:get_it/get_it.dart';

import 'package:tentura/design_system/tentura_theme.dart';
import 'package:tentura/env.dart';
import 'package:tentura/features/beacon_create/ui/bloc/beacon_create_cubit.dart';
import 'package:tentura/features/beacon_create/ui/widget/info_tab.dart';
import 'package:tentura/features/capability/ui/widget/capability_chip_set.dart';
import 'package:tentura/ui/l10n/l10n.dart';

import '../../ui/effect/fake_ui_effect_port.dart';
import 'fake_beacon_ports.dart';

// #436: the last category ("Other") of the Requirements sheet was cut off at
// the bottom. On a phone the sheet runs under the home indicator, and the
// list bottom padding was smaller than that inset, so even fully scrolled the
// last row sat partly behind it.

const _screen = Size(390, 844);
const _bottomInset = 34.0; // iPhone home indicator

void main() {
  late BeaconCreateCubit cubit;

  setUp(() {
    GetIt.I.registerSingleton<Env>(const Env(googleMapsApiKey: 'test-key'));
  });

  tearDown(() async {
    await cubit.close();
    await GetIt.I.reset();
  });

  testWidgets(
    'scrolled to the end, the last category clears the bottom safe area',
    (tester) async {
      tester.view
        ..physicalSize = _screen
        ..devicePixelRatio = 1
        ..padding = const FakeViewPadding(bottom: _bottomInset)
        ..viewPadding = const FakeViewPadding(bottom: _bottomInset);
      addTearDown(tester.view.reset);

      cubit = BeaconCreateCubit(
        beaconCreateCase: fakeBeaconCreateCase(),
        effects: FakeUiEffectPort(),
      );
      await tester.pumpWidget(
        MaterialApp(
          locale: const Locale('en'),
          localizationsDelegates: L10n.localizationsDelegates,
          supportedLocales: L10n.supportedLocales,
          theme: TenturaTheme.light(),
          home: Scaffold(
            body: BlocProvider<BeaconCreateCubit>.value(
              value: cubit,
              child: const Form(child: InfoTab()),
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();

      final row = find.byKey(const Key('BeaconCreate.RequirementsRow'));
      await tester.ensureVisible(row);
      await tester.pumpAndSettle();
      await tester.tap(row);
      await tester.pumpAndSettle();
      expect(find.byType(DraggableScrollableSheet), findsOneWidget);

      final list = find
          .descendant(
            of: find.byType(DraggableScrollableSheet),
            matching: find.byType(Scrollable),
          )
          .first;
      final position = tester.state<ScrollableState>(list).position;
      // Vacuity guard: the categories overflow the sheet, so the last one is
      // only reachable by scrolling.
      expect(position.maxScrollExtent, greaterThan(0));
      position.jumpTo(position.maxScrollExtent);
      await tester.pumpAndSettle();

      final l10n = lookupL10n(const Locale('en'));
      final lastCategory = find.descendant(
        of: find.byType(CapabilityChipSet),
        matching: find.byType(ExpansionTile),
      );
      expect(
        find.descendant(
          of: lastCategory.last,
          matching: find.text(l10n.capabilityGroupSpecial),
        ),
        findsOneWidget,
      );

      final visibleBottom = _screen.height - _bottomInset;
      expect(
        tester.getBottomLeft(lastCategory.last).dy,
        lessThanOrEqualTo(visibleBottom),
      );
    },
  );
}
