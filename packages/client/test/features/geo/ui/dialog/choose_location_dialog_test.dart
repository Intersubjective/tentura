import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:get_it/get_it.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:logging/logging.dart';

import 'package:tentura/design_system/tentura_theme.dart';
import 'package:tentura/domain/entity/coordinates.dart';
import 'package:tentura/env.dart';
import 'package:tentura/features/geo/data/repository/geo_repository.dart';
import 'package:tentura/features/geo/data/service/google_geocoding_service.dart';
import 'package:tentura/features/geo/data/service/google_places_service.dart';
import 'package:tentura/features/geo/domain/entity/location.dart';
import 'package:tentura/features/geo/ui/dialog/choose_location_dialog.dart';
import 'package:tentura/ui/l10n/l10n.dart';

const _selectedFromSearch = Coordinates(lat: 52.358, long: 4.881);
const _selectedFromMapTap = Coordinates(lat: 52.37, long: 4.9);
const _selectedFromMarkerDrag = Coordinates(lat: 52.371, long: 4.901);

class _FakePlacesService extends GooglePlacesService {
  _FakePlacesService()
    : super.withClient(
        const Env(googleMapsApiKey: 'unused'),
        client: MockClient((_) async => http.Response('', 500)),
      );

  final autocompleteTokens = <String>[];
  final detailTokens = <String>[];

  @override
  Future<List<GooglePlacePrediction>> autocomplete({
    required String input,
    required String sessionToken,
  }) async {
    autocompleteTokens.add(sessionToken);
    return const [
      GooglePlacePrediction(
        placeId: 'museumplein',
        description: 'Museumplein 6, Amsterdam',
      ),
    ];
  }

  @override
  Future<GoogleResolvedPlace> details({
    required String placeId,
    required String sessionToken,
  }) async {
    detailTokens.add(sessionToken);
    expect(placeId, 'museumplein');
    return const GoogleResolvedPlace(
      coordinates: _selectedFromSearch,
      addressLabel: 'Museumplein 6, Amsterdam',
    );
  }
}

class _FakeGeocodingService extends GoogleGeocodingService {
  _FakeGeocodingService()
    : super.withClient(
        const Env(googleMapsApiKey: 'unused'),
        client: MockClient((_) async => http.Response('', 500)),
      );

  final seenCoordinates = <Coordinates>[];

  @override
  Future<String?> reverseGeocode(Coordinates coordinates) async {
    seenCoordinates.add(coordinates);
    return 'Prinsengracht 263, Amsterdam';
  }
}

class _DialogHarness extends StatelessWidget {
  const _DialogHarness({
    required this.onResult,
    required this.mapBuilder,
  });

  final ValueChanged<Location?> onResult;
  final ChooseLocationMapBuilder mapBuilder;

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      locale: const Locale('en'),
      localizationsDelegates: L10n.localizationsDelegates,
      supportedLocales: L10n.supportedLocales,
      theme: TenturaTheme.light(),
      home: Builder(
        builder: (context) => Scaffold(
          body: Center(
            child: FilledButton(
              onPressed: () async {
                final location = await showDialog<Location>(
                  context: context,
                  useSafeArea: false,
                  builder: (_) => ChooseLocationDialog(
                    mapBuilder: mapBuilder,
                  ),
                );
                onResult(location);
              },
              child: const Text('Open picker'),
            ),
          ),
        ),
      ),
    );
  }
}

class _FakeMap extends StatelessWidget {
  const _FakeMap({
    required this.selected,
    required this.selectCoordinates,
  });

  final Coordinates? selected;
  final ChooseLocationCoordinateSelector selectCoordinates;

  @override
  Widget build(BuildContext context) {
    return ColoredBox(
      color: Theme.of(context).colorScheme.surfaceContainerHighest,
      child: Column(
        children: [
          Expanded(
            child: GestureDetector(
              key: const Key('ChooseLocation.FakeMap'),
              behavior: HitTestBehavior.opaque,
              onTap: () => unawaited(
                selectCoordinates(_selectedFromMapTap, moveCamera: false),
              ),
              child: Center(child: Text(selected?.toString() ?? 'Map')),
            ),
          ),
          TextButton(
            key: const Key('ChooseLocation.FakeMarkerDragEnd'),
            onPressed: () => unawaited(
              selectCoordinates(_selectedFromMarkerDrag, moveCamera: false),
            ),
            child: const Text('Drag marker'),
          ),
        ],
      ),
    );
  }
}

void main() {
  late _FakePlacesService placesService;
  late _FakeGeocodingService geocodingService;
  Location? result;

  setUp(() {
    result = null;
    placesService = _FakePlacesService();
    geocodingService = _FakeGeocodingService();

    GetIt.I.registerSingleton<Env>(const Env(googleMapsApiKey: 'test-key'));
    GetIt.I.registerSingleton<GeoRepository>(GeoRepository(Logger('test')));
    GetIt.I.registerSingleton<GooglePlacesService>(placesService);
    GetIt.I.registerSingleton<GoogleGeocodingService>(geocodingService);
  });

  tearDown(() async => GetIt.I.reset());

  ChooseLocationMapBuilder fakeMapBuilder() {
    return (context, initialCenter, selected, selectCoordinates) => _FakeMap(
      selected: selected,
      selectCoordinates: selectCoordinates,
    );
  }

  Future<void> openDialog(WidgetTester tester) async {
    await tester.pumpWidget(
      _DialogHarness(
        onResult: (location) => result = location,
        mapBuilder: fakeMapBuilder(),
      ),
    );
    await tester.tap(find.text('Open picker'));
    await tester.pumpAndSettle();
  }

  testWidgets('searches, selects a prediction, and returns stored label', (
    tester,
  ) async {
    await openDialog(tester);

    await tester.tap(find.byType(SearchBar));
    await tester.pumpAndSettle();
    await tester.enterText(find.byType(EditableText).last, 'Museum');
    await tester.pump(const Duration(milliseconds: 350));
    await tester.pumpAndSettle();

    expect(find.text('Museumplein 6, Amsterdam'), findsOneWidget);

    await tester.tap(find.text('Museumplein 6, Amsterdam'));
    await tester.pumpAndSettle();

    expect(find.text('Museumplein 6, Amsterdam'), findsOneWidget);
    expect(placesService.autocompleteTokens, hasLength(1));
    expect(placesService.detailTokens, [
      placesService.autocompleteTokens.single,
    ]);

    await tester.tap(find.text('Use this location'));
    await tester.pumpAndSettle();

    expect(result!.coords, _selectedFromSearch);
    expect(result!.place.toString(), 'Museumplein 6, Amsterdam');
  });

  testWidgets('reverse geocodes map taps before confirmation', (tester) async {
    await openDialog(tester);

    await tester.tap(find.byKey(const Key('ChooseLocation.FakeMap')));
    await tester.pumpAndSettle();

    expect(geocodingService.seenCoordinates, [_selectedFromMapTap]);
    expect(find.text('Prinsengracht 263, Amsterdam'), findsOneWidget);

    await tester.tap(find.text('Use this location'));
    await tester.pumpAndSettle();

    expect(result!.coords, _selectedFromMapTap);
    expect(result!.place.toString(), 'Prinsengracht 263, Amsterdam');
  });

  testWidgets('reverse geocodes marker drag end before confirmation', (
    tester,
  ) async {
    await openDialog(tester);

    await tester.tap(find.byKey(const Key('ChooseLocation.FakeMarkerDragEnd')));
    await tester.pumpAndSettle();

    expect(geocodingService.seenCoordinates, [_selectedFromMarkerDrag]);
    expect(find.text('Prinsengracht 263, Amsterdam'), findsOneWidget);

    await tester.tap(find.text('Use this location'));
    await tester.pumpAndSettle();

    expect(result!.coords, _selectedFromMarkerDrag);
    expect(result!.place.toString(), 'Prinsengracht 263, Amsterdam');
  });

  testWidgets('shows missing maps key guidance when Env key is empty', (
    tester,
  ) async {
    await GetIt.I.reset();
    GetIt.I.registerSingleton<Env>(const Env());
    GetIt.I.registerSingleton<GeoRepository>(GeoRepository(Logger('test')));
    GetIt.I.registerSingleton<GooglePlacesService>(placesService);
    GetIt.I.registerSingleton<GoogleGeocodingService>(geocodingService);

    await openDialog(tester);

    expect(find.textContaining('GOOGLE_MAPS_API_KEY'), findsWidgets);
  });
}
