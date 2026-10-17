// #444: the Request status sheet had no Cancel or ✕.

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:tentura/design_system/tentura_design_system.dart';
import 'package:tentura/domain/entity/beacon.dart';
import 'package:tentura/domain/entity/profile.dart';
import 'package:tentura/features/beacon_view/ui/bloc/beacon_view_cubit.dart';
import 'package:tentura/features/beacon_view/ui/widget/beacon_view_status_bottom_sheet.dart';
import 'package:tentura/ui/l10n/l10n.dart';

import '../../ui/effect/fake_ui_effect_port.dart';
import 'beacon_view_case_test_support.dart';
import 'beacon_view_initial_load_test.dart';

void main() {
  const author = Profile(id: 'Uauthor', displayName: 'Author');
  const beaconId = 'Bstatus01';

  testWidgets('the Close button closes the sheet', (tester) async {
    await tester.binding.setSurfaceSize(const Size(390, 1200));
    addTearDown(() => tester.binding.setSurfaceSize(null));
    final cubit = (await tester.runAsync(() async {
      final cubit = BeaconViewCubit(
        id: beaconId,
        myProfile: author,
        beaconViewCase: buildTestBeaconViewCase(
          beaconRepo: TrackingBeaconRepository()
            ..fetchByIdHandler = (_) async => Beacon(
              id: beaconId,
              title: 'Status beacon',
              createdAt: DateTime.utc(2026),
              updatedAt: DateTime.utc(2026),
              author: author,
            ),
        ),
        effects: FakeUiEffectPort(),
      );
      await pumpUntil(cubit.stream, () => cubit.state.beaconContextLoaded);
      return cubit;
    }))!;
    addTearDown(cubit.close);
    final l10n = lookupL10n(const Locale('en'));

    await tester.pumpWidget(
      MaterialApp(
        theme: TenturaTheme.light(),
        localizationsDelegates: L10n.localizationsDelegates,
        supportedLocales: L10n.supportedLocales,
        locale: const Locale('en'),
        home: MediaQuery(
          data: const MediaQueryData(size: Size(390, 1200)),
          child: TenturaResponsiveScope(
            child: Scaffold(
              body: Builder(
                builder: (ctx) => TextButton(
                  onPressed: () =>
                      showBeaconViewUpdateStatusSheet(ctx, cubit.state, cubit),
                  child: const Text('open'),
                ),
              ),
            ),
          ),
        ),
      ),
    );
    await tester.tap(find.text('open'));
    await tester.pumpAndSettle();
    expect(find.text(l10n.beaconStatusSheetTitle), findsOneWidget);

    await tester.tap(find.byTooltip(l10n.buttonClose));
    await tester.pumpAndSettle();

    expect(find.text(l10n.beaconStatusSheetTitle), findsNothing);
  });
}
