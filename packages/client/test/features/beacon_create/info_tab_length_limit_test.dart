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

Widget _infoTabHarness(BeaconCreateCubit cubit) {
  return MaterialApp(
    locale: const Locale('en'),
    localizationsDelegates: L10n.localizationsDelegates,
    supportedLocales: L10n.supportedLocales,
    theme: TenturaTheme.light(),
    home: MediaQuery(
      data: const MediaQueryData(size: Size(800, 1200)),
      child: Scaffold(
        body: BlocProvider<BeaconCreateCubit>.value(
          value: cubit,
          child: const Form(
            child: InfoTab(key: ValueKey('BeaconCreate.InfoTab')),
          ),
        ),
      ),
    ),
  );
}

/// B058 — the title and description fields capped by user-perceived
/// characters, while the validators and the server count `String.length`
/// (UTF-16 code units): a field full of emoji could never be saved.
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

  testWidgets('a pasted description with emoji is capped where it still saves', (
    tester,
  ) async {
    await tester.pumpWidget(_infoTabHarness(cubit));
    await tester.pumpAndSettle();

    await tester.enterText(
      find.byKey(TestIds.key(TestIds.requestTitle)),
      'Help me move 📦',
    );
    // 1 500 emoji: 1 500 characters, 3 000 UTF-16 code units.
    await tester.enterText(
      find.byKey(TestIds.key(TestIds.requestDescription)),
      '🙂' * 1500,
    );
    await tester.pump();

    final description = cubit.state.description;
    expect(description.length, lessThanOrEqualTo(kBeaconDescriptionMaxLength));
    expect(description.length, kBeaconDescriptionMaxLength);
    expect(cubit.state.publishBlocker, isNull);
    expect(
      find.text('$kBeaconDescriptionMaxLength/$kBeaconDescriptionMaxLength'),
      findsOneWidget,
    );
  });

  testWidgets('a title of emoji is capped where it still saves', (
    tester,
  ) async {
    await tester.pumpWidget(_infoTabHarness(cubit));
    await tester.pumpAndSettle();

    await tester.enterText(
      find.byKey(TestIds.key(TestIds.requestTitle)),
      '🎉' * kBeaconTitleMaxLength,
    );
    await tester.pump();

    expect(cubit.state.title.length, lessThanOrEqualTo(kBeaconTitleMaxLength));
    expect(cubit.state.title, '🎉' * (kBeaconTitleMaxLength ~/ 2));
  });
}
