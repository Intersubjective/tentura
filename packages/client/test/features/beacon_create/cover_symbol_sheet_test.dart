import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:tentura_root/domain/entity/beacon_cover_source.dart';

import 'package:tentura/design_system/tentura_theme.dart';
import 'package:tentura/features/beacon_create/ui/bloc/beacon_create_cubit.dart';
import 'package:tentura/features/beacon_create/ui/widget/cover_symbol_sheet.dart';
import 'package:tentura/ui/l10n/l10n.dart';

import '../../ui/effect/fake_ui_effect_port.dart';
import 'fake_beacon_ports.dart';

Widget _harness(
  BeaconCreateCubit cubit, {
  required VoidCallback onManageCapabilities,
}) => MaterialApp(
  locale: const Locale('en'),
  localizationsDelegates: L10n.localizationsDelegates,
  supportedLocales: L10n.supportedLocales,
  theme: TenturaTheme.light(),
  home: MediaQuery(
    data: const MediaQueryData(size: Size(400, 800)),
    child: Scaffold(
      body: BlocProvider<BeaconCreateCubit>.value(
        value: cubit,
        child: CoverSymbolSheet(
          onManageCapabilities: onManageCapabilities,
        ),
      ),
    ),
  ),
);

void main() {
  late BeaconCreateCubit cubit;

  setUp(() {
    cubit = BeaconCreateCubit(
      beaconCreateCase: fakeBeaconCreateCase(),
      effects: FakeUiEffectPort(),
    );
    addTearDown(cubit.close);
  });

  testWidgets('only the capabilities of this request are offered', (
    tester,
  ) async {
    cubit.setNeeds({'food', 'transport'});

    await tester.pumpWidget(_harness(cubit, onManageCapabilities: () {}));

    expect(find.text('Transport'), findsOneWidget);
    expect(find.text('Food'), findsOneWidget);
    expect(find.text('Housing'), findsNothing);
  });

  testWidgets('capabilities are listed in canonical order', (tester) async {
    cubit.setNeeds({'food', 'transport', 'calls'});

    await tester.pumpWidget(_harness(cubit, onManageCapabilities: () {}));

    final listed = tester
        .widgetList<ListTile>(find.byType(ListTile))
        .map((tile) => ((tile.title!) as Text).data)
        .toList();
    expect(listed, ['Transport', 'Calls', 'Food']);
  });

  testWidgets('selecting a capability sets primary and symbol preference', (
    tester,
  ) async {
    cubit.setNeeds({'food', 'transport'});
    await tester.pumpWidget(_harness(cubit, onManageCapabilities: () {}));

    await tester.tap(find.byKey(const Key('BeaconCover.Symbol.food')));
    await tester.pumpAndSettle();

    expect(cubit.state.primaryNeedSlug, 'food');
    expect(cubit.state.coverSource, BeaconCoverSource.symbol);
  });

  testWidgets('with no capabilities it offers the manage escape only', (
    tester,
  ) async {
    var managed = 0;

    await tester.pumpWidget(
      _harness(cubit, onManageCapabilities: () => managed++),
    );

    expect(find.byType(ListTile), findsNothing);
    expect(
      find.text(
        'This request has no capabilities yet, so there is no symbol to show.',
      ),
      findsOneWidget,
    );

    await tester.tap(find.byKey(const Key('BeaconCover.ManageCapabilities')));
    await tester.pumpAndSettle();

    expect(managed, 1);
    expect(cubit.state.coverSource, BeaconCoverSource.photo);
  });
}
