import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
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
import 'package:tentura/features/geo/data/service/google_geocoding_service.dart';
import 'package:tentura/features/geo/data/service/google_places_service.dart';
import 'package:tentura/ui/l10n/l10n.dart';

import '../../ui/effect/fake_ui_effect_port.dart';

Future<void> _scrollToGroupInSheet(WidgetTester tester, String label) async {
  final scrollable = find.descendant(
    of: find.byType(DraggableScrollableSheet),
    matching: find.byType(Scrollable),
  );
  await tester.scrollUntilVisible(
    find.text(label),
    200,
    scrollable: scrollable,
  );
  await tester.pumpAndSettle();
}

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
          child: const Form(
            child: InfoTab(key: ValueKey('BeaconCreate.InfoTab')),
          ),
        ),
      ),
    ),
  );
}

void main() {
  late BeaconCreateCubit cubit;

  setUp(() {
    cubit = BeaconCreateCubit(
      beaconRepository: BeaconRepositoryMock(),
      imageRepository: ImageRepositoryMock(),
      effects: FakeUiEffectPort(),
    );
    GetIt.I.registerSingleton<Env>(
      const Env(googleMapsApiKey: 'test-key'),
    );
  });

  tearDown(() async {
    await cubit.close();
    if (GetIt.I.isRegistered<Env>()) {
      await GetIt.I.unregister<Env>();
    }
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

  testWidgets('deadline timing mode opens a single date picker', (
    tester,
  ) async {
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
    await tester.enterText(find.byType(TextFormField).at(2), needText);
    await tester.enterText(find.byType(TextFormField).at(3), successText);
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

    await tester.enterText(find.byType(TextFormField).at(2), needText);
    await tester.pump();

    cubit.setDeadline(DateTime(2026, 7));
    await tester.pump();
    cubit.clearTiming();
    await tester.pump();
    cubit.setEventDates(startAt: DateTime(2026, 7, 2));
    await tester.pump();

    expect(cubit.state.needSummary, needText);
    expect(find.text(needText), findsOneWidget);
  });

  testWidgets('tapping location field opens choose location dialog', (
    tester,
  ) async {
    final geo = _GeoRepositoryMock();
    when(geo.myCoordinates).thenReturn(null);

    GetIt.I.registerSingleton<GeoRepository>(geo);
    GetIt.I.registerSingleton<GooglePlacesService>(
      GooglePlacesService(const Env(googleMapsApiKey: 'test-key')),
    );
    GetIt.I.registerSingleton<GoogleGeocodingService>(
      GoogleGeocodingService(const Env(googleMapsApiKey: 'test-key')),
    );

    addTearDown(() async {
      if (GetIt.I.isRegistered<GeoRepository>()) {
        await GetIt.I.unregister<GeoRepository>();
      }
      if (GetIt.I.isRegistered<GooglePlacesService>()) {
        await GetIt.I.unregister<GooglePlacesService>();
      }
      if (GetIt.I.isRegistered<GoogleGeocodingService>()) {
        await GetIt.I.unregister<GoogleGeocodingService>();
      }
    });

    await tester.pumpWidget(_infoTabHarness(cubit));
    await tester.pumpAndSettle();

    await scrollToLocationControls(tester);
    await tester.tap(find.byKey(const Key('BeaconCreate.LocationField')));
    await tester.pumpAndSettle();

    expect(find.text('Tap to choose location'), findsOneWidget);
  });

  testWidgets('location field is hidden when maps key is not configured', (
    tester,
  ) async {
    await GetIt.I.unregister<Env>();
    GetIt.I.registerSingleton<Env>(const Env());

    await tester.pumpWidget(_infoTabHarness(cubit));
    await tester.pumpAndSettle();

    expect(find.byKey(const Key('BeaconCreate.LocationField')), findsNothing);
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

  testWidgets('coordinates without a resolved name show a clear placeholder', (
    tester,
  ) async {
    const coords = Coordinates(lat: 52.358, long: 4.881);
    cubit.setLocation(coords, '');
    await tester.pumpWidget(_infoTabHarness(cubit));
    await tester.pumpAndSettle();

    await scrollToLocationControls(tester);

    // Must not leak raw coordinates as the displayed location name.
    expect(find.text('(52.358, 4.881)'), findsNothing);
    expect(find.text('Pinned location (no address found)'), findsOneWidget);
    // Persisted addressLabel stays empty rather than storing the placeholder.
    expect(cubit.state.location, isEmpty);
  });

  testWidgets('removing a requirement chip updates cubit needs', (
    tester,
  ) async {
    cubit.setNeeds({'money', 'transport'});
    await tester.pumpWidget(_infoTabHarness(cubit));
    await tester.pumpAndSettle();

    expect(find.text('Money'), findsOneWidget);
    expect(find.text('Transport'), findsOneWidget);
    expect(cubit.state.needs, {'money', 'transport'});

    final moneyChip = find.ancestor(
      of: find.text('Money'),
      matching: find.byType(InputChip),
    );
    await tester.tap(
      find.descendant(
        of: moneyChip,
        matching: find.byIcon(Icons.clear),
      ),
    );
    await tester.pumpAndSettle();

    expect(cubit.state.needs, {'transport'});
    expect(find.text('Money'), findsNothing);
    expect(find.text('Transport'), findsOneWidget);
  });

  testWidgets('requirements sheet shows icon hint copy', (tester) async {
    await tester.pumpWidget(_infoTabHarness(cubit));
    await tester.pumpAndSettle();

    await _openRequirementsSheet(tester);

    expect(
      find.text(
        'Selected requirements appear as icons in the request form.',
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

  testWidgets('requirements sheet save preserves unrelated form fields', (
    tester,
  ) async {
    const titleText = 'Weekend move';
    const needText = 'Need help moving furniture this weekend';
    const successText = 'Everything is packed and loaded';

    await tester.pumpWidget(_infoTabHarness(cubit));
    await tester.pumpAndSettle();

    await tester.enterText(find.byType(TextFormField).at(0), titleText);
    await tester.enterText(find.byType(TextFormField).at(1), 'Desc');
    await tester.enterText(find.byType(TextFormField).at(2), needText);
    await tester.enterText(find.byType(TextFormField).at(3), successText);
    await tester.pump();

    await _openRequirementsSheet(tester);
    await _expandLogisticsGroup(tester);
    await tester.tap(find.widgetWithText(FilterChip, 'Transport'));
    await tester.pumpAndSettle();

    await tester.tap(find.text('Save'));
    await tester.pumpAndSettle();

    expect(cubit.state.title, titleText);
    expect(cubit.state.needSummary, needText);
    expect(cubit.state.successCriteria, successText);
    expect(cubit.state.needs, contains('transport'));
    expect(find.text(needText), findsOneWidget);
    expect(find.text(successText), findsOneWidget);
  });

  testWidgets('requirements sheet expands the tapped capability group', (
    tester,
  ) async {
    await tester.pumpWidget(_infoTabHarness(cubit));
    await tester.pumpAndSettle();

    await _openRequirementsSheet(tester);

    expect(find.widgetWithText(FilterChip, 'Calls'), findsNothing);
    expect(find.widgetWithText(FilterChip, 'Tech help'), findsNothing);

    await _scrollToGroupInSheet(tester, 'Technical');
    await tester.tap(find.text('Technical'));
    await tester.pumpAndSettle();

    expect(find.widgetWithText(FilterChip, 'Tech help'), findsOneWidget);
    expect(find.widgetWithText(FilterChip, 'Calls'), findsNothing);
  });

  testWidgets('requirements sheet escape closes when unchanged', (
    tester,
  ) async {
    await tester.pumpWidget(_infoTabHarness(cubit));
    await tester.pumpAndSettle();

    await _openRequirementsSheet(tester);
    expect(find.byType(DraggableScrollableSheet), findsOneWidget);

    await tester.sendKeyDownEvent(LogicalKeyboardKey.escape);
    await tester.sendKeyUpEvent(LogicalKeyboardKey.escape);
    await tester.pumpAndSettle();

    expect(find.byType(DraggableScrollableSheet), findsNothing);
  });
}
