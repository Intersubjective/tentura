import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:get_it/get_it.dart';
import 'package:mockito/mockito.dart';

import 'package:tentura/data/repository/mock/client_repository_mocks.dart';
import 'package:tentura/design_system/tentura_theme.dart';
import 'package:tentura/domain/entity/coordinates.dart';
import 'package:tentura/env.dart';
import 'package:tentura/features/beacon_create/ui/bloc/beacon_create_cubit.dart';
import 'package:tentura/features/beacon_create/ui/widget/info_tab.dart';
import 'package:tentura/features/geo/data/repository/geo_repository.dart';
import 'package:tentura/ui/l10n/l10n.dart';

import '../../ui/effect/fake_ui_effect_port.dart';

Future<void> _openRequirementsSheet(WidgetTester tester) async {
  await tester.ensureVisible(find.text('Requirements'));
  await tester.tap(find.text('Requirements'));
  await tester.pumpAndSettle();
}

Future<void> _expandLogisticsGroup(WidgetTester tester) async {
  await tester.ensureVisible(find.text('Logistics'));
  await tester.tap(find.text('Logistics'));
  await tester.pumpAndSettle();
}

class _GeoRepositoryMock extends Mock implements GeoRepository {}

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
          child: Form(
            child: const InfoTab(key: ValueKey('BeaconCreate.InfoTab')),
          ),
        ),
      ),
    ),
  );
}

Finder _fieldByLabel(String label) => find.widgetWithText(TextFormField, label);

void main() {
  late BeaconCreateCubit cubit;

  setUp(() {
    cubit = BeaconCreateCubit(
      beaconRepository: BeaconRepositoryMock(),
      imageRepository: ImageRepositoryMock(),
      effects: FakeUiEffectPort(),
    );
  });

  tearDown(() async {
    await cubit.close();
  });

  Future<void> scrollToLocationControls(WidgetTester tester) async {
    await tester.scrollUntilVisible(
      find.byKey(const Key('BeaconCreate.LocationField')),
      120,
      scrollable: find.byType(Scrollable).first,
    );
    await tester.pumpAndSettle();
  }

  testWidgets('event timing mode opens the date range picker', (tester) async {
    await tester.pumpWidget(_infoTabHarness(cubit));
    await tester.pumpAndSettle();

    // Declare the timing meaning first, then the contextual picker appears.
    await tester.tap(find.text('Date / period'));
    await tester.pumpAndSettle();

    await tester.ensureVisible(
      find.byKey(const Key('BeaconCreate.TimingField')),
    );
    await tester.tap(find.byKey(const Key('BeaconCreate.TimingField')));
    await tester.pumpAndSettle();

    expect(find.byType(DateRangePickerDialog), findsOneWidget);
  });

  testWidgets('deadline timing mode opens a single date picker', (tester) async {
    await tester.pumpWidget(_infoTabHarness(cubit));
    await tester.pumpAndSettle();

    await tester.tap(find.text('Deadline'));
    await tester.pumpAndSettle();

    await tester.ensureVisible(
      find.byKey(const Key('BeaconCreate.TimingField')),
    );
    await tester.tap(find.byKey(const Key('BeaconCreate.TimingField')));
    await tester.pumpAndSettle();

    expect(find.byType(DatePickerDialog), findsOneWidget);
  });

  testWidgets('tap on timing hint text opens the date picker', (tester) async {
    await tester.pumpWidget(_infoTabHarness(cubit));
    await tester.pumpAndSettle();

    await tester.tap(find.text('Deadline'));
    await tester.pumpAndSettle();

    await tester.ensureVisible(find.text('Tap to choose'));
    await tester.tap(find.text('Tap to choose'));
    await tester.pumpAndSettle();

    expect(find.byType(DatePickerDialog), findsOneWidget);
  });

  test('cubit timing setters write intent-correct nullability', () {
    final start = DateTime(2026, 6, 20);
    final end = DateTime(2026, 6, 23);

    cubit.setDeadline(end);
    expect(cubit.state.startAt, isNull);
    expect(cubit.state.endAt, end);

    cubit.setEventDates(startAt: start, endAt: end);
    expect(cubit.state.startAt, start);
    expect(cubit.state.endAt, end);

    cubit.setEventDates(startAt: start);
    expect(cubit.state.startAt, start);
    expect(cubit.state.endAt, isNull);

    cubit.clearTiming();
    expect(cubit.state.startAt, isNull);
    expect(cubit.state.endAt, isNull);
  });

  testWidgets('timing mode changes preserve unrelated form fields', (
    tester,
  ) async {
    const needText = 'Need help moving furniture this weekend';
    const successText = 'Everything is packed and loaded';
    const titleText = 'Weekend move';

    await tester.pumpWidget(_infoTabHarness(cubit));
    await tester.pumpAndSettle();

    await tester.enterText(find.byType(TextFormField).at(0), titleText);
    await tester.enterText(
      _fieldByLabel('What is needed?'),
      needText,
    );
    await tester.enterText(
      _fieldByLabel('What counts as done?'),
      successText,
    );
    await tester.pump();

    expect(cubit.state.title, titleText);
    expect(cubit.state.needSummary, needText);
    expect(cubit.state.successCriteria, successText);

    await tester.tap(find.text('Deadline'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Date / period'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('No date'));
    await tester.pumpAndSettle();

    expect(cubit.state.title, titleText);
    expect(cubit.state.needSummary, needText);
    expect(cubit.state.successCriteria, successText);
    expect(find.text(needText), findsOneWidget);
    expect(find.text(successText), findsOneWidget);
  });

  testWidgets('cubit date updates preserve unrelated form fields', (
    tester,
  ) async {
    const needText = 'Need a volunteer to water plants';

    await tester.pumpWidget(_infoTabHarness(cubit));
    await tester.pumpAndSettle();

    await tester.enterText(
      _fieldByLabel('What is needed?'),
      needText,
    );
    await tester.pump();

    cubit.setDeadline(DateTime(2026, 7, 1));
    await tester.pump();
    cubit.clearTiming();
    await tester.pump();
    cubit.setEventDates(startAt: DateTime(2026, 7, 2));
    await tester.pump();

    expect(cubit.state.needSummary, needText);
    expect(find.text(needText), findsOneWidget);
  });

  testWidgets('tapping location field opens choose location dialog', (tester) async {
    final geo = _GeoRepositoryMock();
    when(geo.myCoordinates).thenReturn(null);

    GetIt.I.registerSingleton<Env>(const Env());
    GetIt.I.registerSingleton<GeoRepository>(geo);

    addTearDown(() async => GetIt.I.reset());

    await tester.pumpWidget(_infoTabHarness(cubit));
    await tester.pumpAndSettle();

    await scrollToLocationControls(tester);
    await tester.tap(find.byKey(const Key('BeaconCreate.LocationField')));
    await tester.pumpAndSettle();

    expect(find.text('Tap to choose location'), findsOneWidget);
  });

  testWidgets('location clear button clears coords without opening map', (
    tester,
  ) async {
    const coords = Coordinates(lat: 1, long: 2);
    cubit.setLocation(coords, 'Test place');
    await tester.pumpWidget(_infoTabHarness(cubit));
    await tester.pumpAndSettle();

    expect(cubit.state.coordinates, coords);

    await scrollToLocationControls(tester);
    await tester.tap(find.byKey(const Key('BeaconCreate.LocationClearButton')));
    await tester.pumpAndSettle();

    expect(cubit.state.coordinates, isNull);
    expect(cubit.state.location, isEmpty);
    expect(find.text('Tap to choose location'), findsNothing);
  });

  testWidgets('requirements sheet shows icon hint copy', (tester) async {
    await tester.pumpWidget(_infoTabHarness(cubit));
    await tester.pumpAndSettle();

    await _openRequirementsSheet(tester);

    expect(
      find.text(
        'Selected requirements appear as icons in the beacon form.',
      ),
      findsOneWidget,
    );
  });

  testWidgets('requirements sheet closes without confirm when unchanged', (
    tester,
  ) async {
    await tester.pumpWidget(_infoTabHarness(cubit));
    await tester.pumpAndSettle();

    await _openRequirementsSheet(tester);
    expect(find.byType(DraggableScrollableSheet), findsOneWidget);

    await tester.tapAt(const Offset(20, 20));
    await tester.pumpAndSettle();

    expect(find.byType(DraggableScrollableSheet), findsNothing);
  });

  testWidgets('requirements sheet confirms before discarding changes', (
    tester,
  ) async {
    await tester.pumpWidget(_infoTabHarness(cubit));
    await tester.pumpAndSettle();

    await _openRequirementsSheet(tester);
    await _expandLogisticsGroup(tester);
    await tester.tap(find.widgetWithText(FilterChip, 'Transport'));
    await tester.pumpAndSettle();

    await tester.tapAt(const Offset(20, 20));
    await tester.pumpAndSettle();

    expect(find.text('Discard selections?'), findsOneWidget);

    await tester.tap(find.text('Cancel'));
    await tester.pumpAndSettle();

    expect(find.byType(DraggableScrollableSheet), findsOneWidget);
    expect(cubit.state.needs, isEmpty);

    await tester.tapAt(const Offset(20, 20));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Discard'));
    await tester.pumpAndSettle();

    expect(find.byType(DraggableScrollableSheet), findsNothing);
    expect(cubit.state.needs, isEmpty);
  });

  testWidgets('requirements sheet save applies selection', (tester) async {
    await tester.pumpWidget(_infoTabHarness(cubit));
    await tester.pumpAndSettle();

    await _openRequirementsSheet(tester);
    await _expandLogisticsGroup(tester);
    await tester.tap(find.widgetWithText(FilterChip, 'Transport'));
    await tester.pumpAndSettle();

    await tester.tap(find.text('Save'));
    await tester.pumpAndSettle();

    expect(find.byType(DraggableScrollableSheet), findsNothing);
    expect(cubit.state.needs, contains('transport'));
  });
}
