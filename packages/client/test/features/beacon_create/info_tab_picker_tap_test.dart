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
          child: const InfoTab(),
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
}
