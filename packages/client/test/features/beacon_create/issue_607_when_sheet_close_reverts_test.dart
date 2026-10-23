import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:get_it/get_it.dart';

import 'package:tentura/design_system/tentura_design_system.dart';
import 'package:tentura/domain/entity/beacon_schedule.dart';
import 'package:tentura/env.dart';
import 'package:tentura/features/beacon_create/ui/bloc/beacon_create_cubit.dart';
import 'package:tentura/features/beacon_create/ui/widget/info_tab.dart';
import 'package:tentura/ui/l10n/l10n.dart';

import '../../ui/effect/fake_ui_effect_port.dart';
import 'fake_beacon_ports.dart';

// #607: in the When? sheet, picking a date and then closing the sheet with
// (x) kept the picked date. Only OK confirms; (x) puts the timing back as it
// was when the sheet opened.

Widget _infoTabHarness(BeaconCreateCubit cubit) => MaterialApp(
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
);

Finder _segmentedButton() => find.byType(SegmentedButton<BeaconScheduleKind>);

Set<BeaconScheduleKind> _selectedKind(WidgetTester tester) => tester
    .widget<SegmentedButton<BeaconScheduleKind>>(_segmentedButton())
    .selected;

DateTime _day(DateTime d) => DateTime(d.year, d.month, d.day);

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
    await GetIt.I.reset();
  });

  Future<void> openWhenSheet(WidgetTester tester) async {
    await tester.ensureVisible(find.byKey(const Key('BeaconCreate.TimingRow')));
    await tester.tap(find.byKey(const Key('BeaconCreate.TimingRow')));
    await tester.pumpAndSettle();
    expect(_segmentedButton(), findsOneWidget);
  }

  Future<void> tapSegment(WidgetTester tester, String label) async {
    await tester.tap(
      find.descendant(of: _segmentedButton(), matching: find.text(label)),
    );
    await tester.pumpAndSettle();
  }

  /// Opens the date picker from the sheet's date row, optionally taps
  /// [dayOfMonth] in the calendar, and confirms the picker with its OK.
  Future<void> pickDeadline(WidgetTester tester, {int? dayOfMonth}) async {
    await tester.tap(find.byKey(const Key('BeaconCreate.TimingField')));
    await tester.pumpAndSettle();
    final dialog = find.byType(DatePickerDialog);
    expect(dialog, findsOneWidget);
    if (dayOfMonth != null) {
      await tester.tap(
        find.descendant(of: dialog, matching: find.text('$dayOfMonth')),
      );
      await tester.pumpAndSettle();
    }
    await tester.tap(find.descendant(of: dialog, matching: find.text('OK')));
    await tester.pumpAndSettle();
    expect(dialog, findsNothing);
    // Still in the When? sheet.
    expect(_segmentedButton(), findsOneWidget);
  }

  Future<void> tapCloseX(WidgetTester tester) async {
    await tester.tap(find.byTooltip('Close'));
    await tester.pumpAndSettle();
    expect(_segmentedButton(), findsNothing);
  }

  group('When? sheet (x) reverts a picked date (#607)', () {
    testWidgets('new request: Deadline, pick a date, (x) leaves no date', (
      tester,
    ) async {
      await tester.pumpWidget(_infoTabHarness(cubit));
      await tester.pumpAndSettle();

      await openWhenSheet(tester);
      await tapSegment(tester, 'Deadline');
      await pickDeadline(tester);
      // Raw precondition: the pick reached the form state.
      expect(cubit.state.endAt, isNotNull);

      await tapCloseX(tester);

      expect(cubit.state.startAt, isNull);
      expect(cubit.state.endAt, isNull);
      // Reopening shows the mode the request had before: no date.
      await openWhenSheet(tester);
      expect(_selectedKind(tester), {BeaconScheduleKind.none});
    });

    testWidgets('existing deadline: pick another day, (x) keeps the original '
        'deadline', (tester) async {
      final original = _day(DateTime.now().add(const Duration(days: 200)));
      cubit.setDeadline(original);
      await tester.pumpWidget(_infoTabHarness(cubit));
      await tester.pumpAndSettle();

      await openWhenSheet(tester);
      expect(_selectedKind(tester), {BeaconScheduleKind.deadline});
      final otherDay = original.day == 15 ? 14 : 15;
      await pickDeadline(tester, dayOfMonth: otherDay);
      expect(cubit.state.endAt?.day, otherDay);

      await tapCloseX(tester);

      expect(cubit.state.startAt, isNull);
      expect(cubit.state.endAt, original);
      await openWhenSheet(tester);
      expect(_selectedKind(tester), {BeaconScheduleKind.deadline});
    });

    testWidgets('existing event: switching to Deadline then (x) keeps the '
        'event dates', (tester) async {
      final start = _day(DateTime.now().add(const Duration(days: 30)));
      final end = start.add(const Duration(days: 2));
      cubit.setEventDates(startAt: start, endAt: end);
      await tester.pumpWidget(_infoTabHarness(cubit));
      await tester.pumpAndSettle();

      await openWhenSheet(tester);
      await tapSegment(tester, 'Deadline');
      // Raw precondition: the switch moved the dates to a deadline.
      expect(cubit.state.startAt, isNull);
      expect(cubit.state.endAt, isNotNull);

      await tapCloseX(tester);

      expect(cubit.state.startAt, start);
      expect(cubit.state.endAt, end);
      await openWhenSheet(tester);
      expect(_selectedKind(tester), {BeaconScheduleKind.event});
    });

    testWidgets('Escape after picking a date reverts too', (tester) async {
      await tester.pumpWidget(_infoTabHarness(cubit));
      await tester.pumpAndSettle();

      await openWhenSheet(tester);
      await tapSegment(tester, 'Deadline');
      await pickDeadline(tester);
      expect(cubit.state.endAt, isNotNull);

      await tester.sendKeyEvent(LogicalKeyboardKey.escape);
      await tester.pumpAndSettle();
      expect(_segmentedButton(), findsNothing);

      expect(cubit.state.endAt, isNull);
    });
  });

  group('When? sheet OK still confirms (#607 guards)', () {
    testWidgets('pick a date then OK keeps it', (tester) async {
      await tester.pumpWidget(_infoTabHarness(cubit));
      await tester.pumpAndSettle();

      await openWhenSheet(tester);
      await tapSegment(tester, 'Deadline');
      await pickDeadline(tester);
      final picked = cubit.state.endAt;
      expect(picked, isNotNull);

      await tester.tap(find.widgetWithText(FilledButton, 'OK'));
      await tester.pumpAndSettle();
      expect(_segmentedButton(), findsNothing);

      expect(cubit.state.startAt, isNull);
      expect(cubit.state.endAt, picked);
      await openWhenSheet(tester);
      expect(_selectedKind(tester), {BeaconScheduleKind.deadline});
    });

    testWidgets('switching the mode without a date then (x) reverts the mode', (
      tester,
    ) async {
      await tester.pumpWidget(_infoTabHarness(cubit));
      await tester.pumpAndSettle();

      await openWhenSheet(tester);
      await tapSegment(tester, 'Date / period');
      await tapCloseX(tester);

      expect(cubit.state.startAt, isNull);
      expect(cubit.state.endAt, isNull);
      await openWhenSheet(tester);
      expect(_selectedKind(tester), {BeaconScheduleKind.none});
    });
  });
}
