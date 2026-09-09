import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:get_it/get_it.dart';
import 'package:tentura_root/domain/entity/beacon_status.dart';

import 'package:tentura/design_system/tentura_theme.dart';
import 'package:tentura/domain/entity/beacon.dart';
import 'package:tentura/domain/entity/profile.dart';
import 'package:tentura/env.dart';
import 'package:tentura/features/beacon/ui/widget/beacon_discoverability_control.dart';
import 'package:tentura/features/beacon_create/ui/bloc/beacon_create_cubit.dart';
import 'package:tentura/features/beacon_create/ui/widget/info_tab.dart';
import 'package:tentura/ui/l10n/l10n.dart';
import 'package:tentura/ui/test_ids.dart';

import '../../ui/effect/fake_ui_effect_port.dart';
import 'fake_beacon_ports.dart';

const _reachStatement =
    'Discoverable by people you and your network can both see';

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

Future<void> _scrollToDiscoverabilityToggle(WidgetTester tester) async {
  await tester.scrollUntilVisible(
    find.byKey(TestIds.key(TestIds.requestDiscoverableToggle)),
    120,
    scrollable: find.byType(Scrollable).first,
  );
  await tester.pumpAndSettle();
}

Widget _controlHarness({
  required bool isAuthor,
  required bool isDiscoverable,
  ValueChanged<bool>? onChanged,
}) {
  return MaterialApp(
    locale: const Locale('en'),
    localizationsDelegates: L10n.localizationsDelegates,
    supportedLocales: L10n.supportedLocales,
    theme: TenturaTheme.light(),
    home: Scaffold(
      body: BeaconDiscoverabilityControl(
        isAuthor: isAuthor,
        isDiscoverable: isDiscoverable,
        onChanged: onChanged ?? (_) {},
      ),
    ),
  );
}

void main() {
  setUp(() {
    GetIt.I.registerSingleton<Env>(
      const Env(googleMapsApiKey: 'test-key'),
    );
  });

  tearDown(() async {
    if (GetIt.I.isRegistered<Env>()) {
      await GetIt.I.unregister<Env>();
    }
  });

  testWidgets('new request defaults discoverability on', (tester) async {
    final write = FakeBeaconWritePort();
    final cubit = BeaconCreateCubit(
      beaconCreateCase: fakeBeaconCreateCase(write: write),
      effects: FakeUiEffectPort(),
    );
    addTearDown(cubit.close);

    expect(cubit.state.isDiscoverable, isTrue);

    await tester.pumpWidget(_infoTabHarness(cubit));
    await tester.pumpAndSettle();
    await _scrollToDiscoverabilityToggle(tester);

    final toggle = find.byKey(TestIds.key(TestIds.requestDiscoverableToggle));
    expect(toggle, findsOneWidget);
    expect(tester.widget<SwitchListTile>(toggle).value, isTrue);
    expect(find.text(_reachStatement), findsOneWidget);
  });

  testWidgets('toggling off round-trips through beaconUpdate on saveEdit', (
    tester,
  ) async {
    final write = FakeBeaconWritePort(
      beacon: Beacon.empty.copyWith(
        id: 'B-edit',
        status: BeaconStatus.open,
        author: const Profile(id: 'author-1'),
      ),
    );
    final cubit = BeaconCreateCubit(
      beaconCreateCase: fakeBeaconCreateCase(write: write),
      effects: FakeUiEffectPort(),
      editBeaconIdToLoad: 'B-edit',
    );
    addTearDown(cubit.close);

    await cubit.stream.firstWhere((s) => s.editId == 'B-edit');
    cubit
      ..setTitle('Need a piano moved')
      ..setDescription('Two flights of stairs, this weekend.');

    await tester.pumpWidget(_infoTabHarness(cubit));
    await tester.pumpAndSettle();
    await _scrollToDiscoverabilityToggle(tester);

    await tester.tap(find.byKey(TestIds.key(TestIds.requestDiscoverableToggle)));
    await tester.pumpAndSettle();
    expect(cubit.state.isDiscoverable, isFalse);

    await cubit.saveEdit(context: 'c', navigateBack: false);

    expect(write.updatedFields, hasLength(1));
    expect(write.updatedFields.single.isDiscoverable, isFalse);
  });

  testWidgets('reach statement is present whenever the toggle is', (
    tester,
  ) async {
    await tester.pumpWidget(
      _controlHarness(isAuthor: true, isDiscoverable: true),
    );
    await tester.pumpAndSettle();

    expect(find.text(_reachStatement), findsOneWidget);
    expect(
      find.byKey(TestIds.key(TestIds.requestDiscoverableToggle)),
      findsOneWidget,
    );
  });

  testWidgets('control is absent for non-authors', (tester) async {
    await tester.pumpWidget(
      _controlHarness(isAuthor: false, isDiscoverable: true),
    );
    await tester.pumpAndSettle();

    expect(find.text(_reachStatement), findsNothing);
    expect(
      find.byKey(TestIds.key(TestIds.requestDiscoverableToggle)),
      findsNothing,
    );
  });
}
