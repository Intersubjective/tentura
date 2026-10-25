import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:get_it/get_it.dart';

import 'package:tentura/design_system/tentura_design_system.dart';
import 'package:tentura/domain/capability/capability_tag.dart';
import 'package:tentura/env.dart';
import 'package:tentura/features/beacon_create/ui/bloc/beacon_create_cubit.dart';
import 'package:tentura/features/beacon_create/ui/widget/info_tab.dart';
import 'package:tentura/features/capability/ui/widget/capability_chip_set.dart';
import 'package:tentura/ui/l10n/l10n.dart';
import 'package:tentura/ui/test_ids.dart';

import '../../ui/effect/fake_ui_effect_port.dart';
import 'fake_beacon_ports.dart';

// #436 (QA 7.50.6), the Requirements sheet:
// 1. On desktop at 150% zoom the group list overflows and the last group
//    ("Other") is clipped, with no scrollbar, fade or other cue below.
// 2. Select Logistics > Tools, Save, reopen: every group is folded and
//    Logistics shows only a "1" badge. The group holding the choice should
//    be open.

final _l10n = lookupL10n(const Locale('en'));

/// Chrome desktop 1280x800 at 150% browser zoom.
const _desktopZoomed = Size(853, 533);

Finder _inSheet(Finder finder) => find.descendant(
  of: find.byType(DraggableScrollableSheet),
  matching: finder,
);

Finder _chip(CapabilityTag tag) =>
    find.byKey(TestIds.key(TestIds.capabilityChip(tag.slug)));

void main() {
  late BeaconCreateCubit cubit;

  setUp(() {
    GetIt.I.registerSingleton<Env>(const Env(googleMapsApiKey: 'test-key'));
  });

  tearDown(() async {
    await cubit.close();
    await GetIt.I.reset();
  });

  Future<void> pumpInfoTab(WidgetTester tester) async {
    tester.view
      ..physicalSize = _desktopZoomed
      ..devicePixelRatio = 1;
    addTearDown(tester.view.reset);

    cubit = BeaconCreateCubit(
      beaconCreateCase: fakeBeaconCreateCase(),
      effects: FakeUiEffectPort(),
    );
    await tester.pumpWidget(
      MaterialApp(
        // As in the app: the scope sits above the Navigator, so the sheet's
        // dialog sees it.
        builder: (_, child) => TenturaResponsiveScope(child: child!),
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
  }

  Future<void> openSheet(WidgetTester tester) async {
    final row = find.byKey(const Key('BeaconCreate.RequirementsRow'));
    await tester.ensureVisible(row);
    await tester.pumpAndSettle();
    await tester.tap(row);
    await tester.pumpAndSettle();
    expect(find.byType(DraggableScrollableSheet), findsOneWidget);
  }

  Future<void> tapInSheet(WidgetTester tester, Finder finder) async {
    await tester.ensureVisible(finder);
    await tester.pumpAndSettle();
    await tester.tap(finder);
    await tester.pumpAndSettle();
  }

  group('#436 Requirements sheet', () {
    testWidgets('an overflowing group list keeps a scrollbar thumb shown', (
      tester,
    ) async {
      await pumpInfoTab(tester);
      await openSheet(tester);

      final list = _inSheet(find.byType(Scrollable)).first;
      // Vacuity guard: the groups really overflow the sheet here.
      expect(
        tester.state<ScrollableState>(list).position.maxScrollExtent,
        greaterThan(0),
      );

      final thumbs = _inSheet(
        find.byWidgetPredicate(
          (w) => w is Scrollbar && (w.thumbVisibility ?? false),
        ),
      );
      expect(thumbs, findsOneWidget);
    });

    testWidgets('reopened, the group with a selected tag is open', (
      tester,
    ) async {
      await pumpInfoTab(tester);
      await openSheet(tester);
      await tapInSheet(tester, find.text(_l10n.capabilityGroupLogistics));
      await tapInSheet(tester, _chip(CapabilityTag.tools));
      await tapInSheet(
        tester,
        _inSheet(find.widgetWithText(FilledButton, _l10n.buttonSave)),
      );
      expect(find.byType(DraggableScrollableSheet), findsNothing);
      expect(cubit.state.needs, {CapabilityTag.tools.slug});

      await openSheet(tester);

      final tools = _inSheet(_chip(CapabilityTag.tools));
      expect(tools, findsOneWidget);
      expect(tester.widget<FilterChip>(tools).selected, isTrue);
    });

    testWidgets('guard: with nothing selected every group starts folded', (
      tester,
    ) async {
      await pumpInfoTab(tester);
      await openSheet(tester);

      expect(_inSheet(find.byType(CapabilityChipSet)), findsOneWidget);
      expect(_inSheet(find.byType(FilterChip)), findsNothing);
    });
  });
}
