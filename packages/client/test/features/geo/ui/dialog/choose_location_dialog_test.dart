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

/// Only resolves once [complete] is called, so tests can observe UI state
/// while a reverse-geocode lookup is still in flight.
class _DelayedGeocodingService extends GoogleGeocodingService {
  _DelayedGeocodingService()
    : super.withClient(
        const Env(googleMapsApiKey: 'unused'),
        client: MockClient((_) async => http.Response('', 500)),
      );

  final _completer = Completer<String?>();

  void complete(String? label) => _completer.complete(label);

  @override
  Future<String?> reverseGeocode(Coordinates coordinates) => _completer.future;
}

class _DialogHarness extends StatelessWidget {
  const _DialogHarness({
    required this.onResult,
    required this.mapBuilder,
    this.locale = const Locale('en'),
    this.center,
  });

  final ValueChanged<Location?> onResult;
  final ChooseLocationMapBuilder mapBuilder;
  final Locale locale;
  final Coordinates? center;

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      locale: locale,
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
                    center: center,
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

  ChooseLocationMapBuilder fakeMapBuilder({List<Coordinates>? centers}) {
    return (context, initialCenter, selected, selectCoordinates) {
      centers?.add(initialCenter);
      return _FakeMap(
        selected: selected,
        selectCoordinates: selectCoordinates,
      );
    };
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

  testWidgets('disables confirm until reverse geocoding settles', (
    tester,
  ) async {
    final delayedGeocoding = _DelayedGeocodingService();
    await GetIt.I.reset();
    GetIt.I.registerSingleton<Env>(const Env(googleMapsApiKey: 'test-key'));
    GetIt.I.registerSingleton<GeoRepository>(GeoRepository(Logger('test')));
    GetIt.I.registerSingleton<GooglePlacesService>(placesService);
    GetIt.I.registerSingleton<GoogleGeocodingService>(delayedGeocoding);

    await openDialog(tester);

    await tester.tap(find.byKey(const Key('ChooseLocation.FakeMap')));
    await tester.pump();

    expect(
      tester
          .widget<FilledButton>(
            find.widgetWithText(FilledButton, 'Use this location'),
          )
          .onPressed,
      isNull,
      reason: 'still resolving the address, confirm must stay disabled',
    );
    expect(result, isNull);

    delayedGeocoding.complete('Prinsengracht 263, Amsterdam');
    await tester.pumpAndSettle();

    await tester.tap(find.text('Use this location'));
    await tester.pumpAndSettle();

    expect(result!.coords, _selectedFromMapTap);
    expect(result!.place.toString(), 'Prinsengracht 263, Amsterdam');
  });

  testWidgets('close button dismisses without a location', (tester) async {
    await openDialog(tester);

    await tester.tap(find.byKey(const Key('ChooseLocation.Close')));
    await tester.pumpAndSettle();

    expect(result, isNull);
    expect(find.byType(ChooseLocationDialog), findsNothing);
  });

  // #432: a refused Places request showed Google's raw error text.
  testWidgets('a refused address search shows a plain sentence', (
    tester,
  ) async {
    await GetIt.I.unregister<GooglePlacesService>();
    GetIt.I.registerSingleton<GooglePlacesService>(
      GooglePlacesService.withClient(
        const Env(googleMapsApiKey: 'test-key'),
        client: MockClient(
          (_) async => http.Response(
            '{"error":{"code":403,"message":"The caller does not have '
            'permission","status":"PERMISSION_DENIED"}}',
            403,
          ),
        ),
      ),
    );
    await openDialog(tester);

    await tester.tap(find.byType(SearchBar));
    await tester.pumpAndSettle();
    await tester.enterText(find.byType(EditableText).last, 'Museum');
    await tester.pump(const Duration(milliseconds: 350));
    await tester.pumpAndSettle();

    expect(
      find.text(
        'Address search isn’t available right now. Tap the map to drop a pin '
        'instead.',
      ),
      findsOneWidget,
    );
    expect(find.textContaining('request failed'), findsNothing);
    expect(find.textContaining('permission'), findsNothing);
  });

  testWidgets('an address search without a connection says so', (
    tester,
  ) async {
    await GetIt.I.unregister<GooglePlacesService>();
    GetIt.I.registerSingleton<GooglePlacesService>(
      GooglePlacesService.withClient(
        const Env(googleMapsApiKey: 'test-key'),
        client: MockClient((_) async => throw http.ClientException('offline')),
      ),
    );
    await openDialog(tester);

    await tester.tap(find.byType(SearchBar));
    await tester.pumpAndSettle();
    await tester.enterText(find.byType(EditableText).last, 'Museum');
    await tester.pump(const Duration(milliseconds: 350));
    await tester.pumpAndSettle();

    expect(
      find.text('Address search failed. Check your connection and try again.'),
      findsOneWidget,
    );
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

  group('initial camera never starts at 0,0 (#433)', () {
    bool nearNullIsland(Coordinates c) => c.lat.abs() < 5 && c.long.abs() < 5;

    // Rough bounding box of Russia (incl. Kaliningrad and the Far East).
    bool inRussia(Coordinates c) =>
        c.lat >= 41 && c.lat <= 82 && c.long >= 19 && c.long <= 180;

    Future<void> pumpHarness(
      WidgetTester tester, {
      required List<Coordinates> centers,
      Locale locale = const Locale('en'),
      Coordinates? center,
    }) async {
      await tester.pumpWidget(
        _DialogHarness(
          onResult: (location) => result = location,
          mapBuilder: fakeMapBuilder(centers: centers),
          locale: locale,
          center: center,
        ),
      );
    }

    Future<void> openPicker(WidgetTester tester) async {
      await tester.tap(find.text('Open picker'));
      await tester.pumpAndSettle();
    }

    testWidgets('a fresh picker with no pin and no device fix is not at 0,0', (
      tester,
    ) async {
      final centers = <Coordinates>[];
      await pumpHarness(tester, centers: centers);
      await openPicker(tester);

      expect(centers, isNotEmpty);
      expect(centers.last, isNot(Coordinates.zero));
      expect(
        nearNullIsland(centers.last),
        isFalse,
        reason: centers.last.toString(),
      );
    });

    testWidgets('the Russian locale opens over Russia', (tester) async {
      final centers = <Coordinates>[];
      await pumpHarness(tester, centers: centers, locale: const Locale('ru'));
      await openPicker(tester);

      expect(centers, isNotEmpty);
      expect(inRussia(centers.last), isTrue, reason: centers.last.toString());
    });

    testWidgets('the English locale default differs from the Russian one', (
      tester,
    ) async {
      final centers = <Coordinates>[];
      await pumpHarness(tester, centers: centers);
      await openPicker(tester);

      expect(centers, isNotEmpty);
      expect(
        nearNullIsland(centers.last),
        isFalse,
        reason: centers.last.toString(),
      );
      expect(inRussia(centers.last), isFalse, reason: centers.last.toString());
    });

    testWidgets('an empty 0,0 center is treated as no center', (tester) async {
      final centers = <Coordinates>[];
      await pumpHarness(tester, centers: centers, center: Coordinates.zero);
      await openPicker(tester);

      expect(centers, isNotEmpty);
      expect(
        nearNullIsland(centers.last),
        isFalse,
        reason: centers.last.toString(),
      );
      // Nothing is pre-selected either: confirm stays disabled.
      expect(
        tester
            .widget<FilledButton>(
              find.widgetWithText(FilledButton, 'Use this location'),
            )
            .onPressed,
        isNull,
      );
    });

    testWidgets('reopening starts at the last confirmed pin', (tester) async {
      final centers = <Coordinates>[];
      await pumpHarness(tester, centers: centers);
      await openPicker(tester);

      await tester.tap(find.byKey(const Key('ChooseLocation.FakeMap')));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Use this location'));
      await tester.pumpAndSettle();
      expect(result!.coords, _selectedFromMapTap);

      centers.clear();
      await openPicker(tester);

      expect(centers, isNotEmpty);
      expect(centers.first, _selectedFromMapTap);
    });

    testWidgets('a pin dropped and then cancelled is not remembered', (
      tester,
    ) async {
      final centers = <Coordinates>[];
      await pumpHarness(tester, centers: centers);
      await openPicker(tester);
      final firstCenter = centers.first;

      await tester.tap(find.byKey(const Key('ChooseLocation.FakeMap')));
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const Key('ChooseLocation.Close')));
      await tester.pumpAndSettle();
      expect(result, isNull);

      centers.clear();
      await openPicker(tester);

      expect(centers, isNotEmpty);
      expect(centers.first, isNot(_selectedFromMapTap));
      expect(centers.first, firstCenter);
    });

    testWidgets('an explicit center wins over the last pin', (tester) async {
      const draftCenter = Coordinates(lat: 48.8566, long: 2.3522);
      final centers = <Coordinates>[];
      await pumpHarness(tester, centers: centers);
      await openPicker(tester);
      await tester.tap(find.byKey(const Key('ChooseLocation.FakeMap')));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Use this location'));
      await tester.pumpAndSettle();

      centers.clear();
      await pumpHarness(tester, centers: centers, center: draftCenter);
      await openPicker(tester);

      expect(centers, isNotEmpty);
      expect(centers.first, draftCenter);
    });
  });
}
