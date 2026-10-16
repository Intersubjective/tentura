// #339: the floating "What do you need?" label of the title field was
// clipped: the field sits at the very top of the Info tab's list, and the
// label floats half above the field's border, outside the list.

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:get_it/get_it.dart';

import 'package:tentura/design_system/tentura_theme.dart';
import 'package:tentura/env.dart';
import 'package:tentura/features/beacon_create/ui/bloc/beacon_create_cubit.dart';
import 'package:tentura/features/beacon_create/ui/widget/info_tab.dart';
import 'package:tentura/ui/l10n/l10n.dart';
import 'package:tentura/ui/test_ids.dart';

import '../../ui/effect/fake_ui_effect_port.dart';
import 'fake_beacon_ports.dart';

void main() {
  late BeaconCreateCubit cubit;

  setUp(() {
    cubit = BeaconCreateCubit(
      beaconCreateCase: fakeBeaconCreateCase(),
      effects: FakeUiEffectPort(),
    );
    GetIt.I.registerSingleton<Env>(const Env(googleMapsApiKey: 'test-key'));
  });

  tearDown(() async {
    await cubit.close();
    if (GetIt.I.isRegistered<Env>()) {
      await GetIt.I.unregister<Env>();
    }
  });

  testWidgets('the floated title label lies inside the scroll view', (
    tester,
  ) async {
    final l10n = lookupL10n(const Locale('en'));
    await tester.pumpWidget(
      MaterialApp(
        locale: const Locale('en'),
        localizationsDelegates: L10n.localizationsDelegates,
        supportedLocales: L10n.supportedLocales,
        theme: TenturaTheme.light(),
        home: MediaQuery(
          data: const MediaQueryData(size: Size(800, 1200)),
          child: Scaffold(
            body: BlocProvider<BeaconCreateCubit>.value(
              value: cubit,
              child: const Form(child: InfoTab()),
            ),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();

    final title = find.byKey(TestIds.key(TestIds.requestTitle));
    await tester.tap(title);
    await tester.enterText(title, 'Need a van');
    await tester.pumpAndSettle();

    final label = find.descendant(
      of: title,
      matching: find.text(l10n.beaconCreateTitleHint),
    );
    expect(label, findsOneWidget);
    final list = tester.getRect(find.byType(ListView).first);
    expect(tester.getRect(label).top, greaterThanOrEqualTo(list.top));
  });
}
