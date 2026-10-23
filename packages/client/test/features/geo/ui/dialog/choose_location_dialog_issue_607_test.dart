// #607: location picker follow-ups (from #432/#433).
//  * The bottom bar and the search bar had hard-coded English strings.
//  * A failed place-details lookup after tapping a suggestion was an
//    uncaught async error, and the search failure was swallowed unlogged.
//  * The "key missing" case was told apart by sniffing the StateError text,
//    so any Google error text that happened to mention the key name was
//    shown as a local configuration problem.
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
import 'package:tentura/features/geo/data/service/google_maps_errors.dart';
import 'package:tentura/features/geo/data/service/google_places_service.dart';
import 'package:tentura/features/geo/domain/entity/location.dart';
import 'package:tentura/features/geo/ui/dialog/choose_location_dialog.dart';
import 'package:tentura/ui/l10n/l10n.dart';

const _prediction = GooglePlacePrediction(
  placeId: 'museumplein',
  description: 'Museumplein 6, Amsterdam',
);
const _mapTap = Coordinates(lat: 52.37, long: 4.9);

http.Client _unusedClient() => MockClient((_) async => http.Response('', 500));

/// Autocomplete answers with [_prediction] (or [autocompleteError], or waits
/// on [autocompleteGate]); details throws [detailsError] when set.
class _FakePlacesService extends GooglePlacesService {
  _FakePlacesService()
    : super.withClient(
        const Env(googleMapsApiKey: 'unused'),
        client: _unusedClient(),
      );

  Object? autocompleteError;
  Completer<void>? autocompleteGate;
  Object? detailsError;

  @override
  Future<List<GooglePlacePrediction>> autocomplete({
    required String input,
    required String sessionToken,
  }) async {
    await autocompleteGate?.future;
    final error = autocompleteError;
    if (error != null) Error.throwWithStackTrace(error, StackTrace.current);
    return const [_prediction];
  }

  @override
  Future<GoogleResolvedPlace> details({
    required String placeId,
    required String sessionToken,
  }) async {
    final error = detailsError;
    if (error != null) Error.throwWithStackTrace(error, StackTrace.current);
    return const GoogleResolvedPlace(
      coordinates: Coordinates(lat: 52.358, long: 4.881),
      addressLabel: 'Museumplein 6, Amsterdam',
    );
  }
}

class _FakeGeocodingService extends GoogleGeocodingService {
  _FakeGeocodingService()
    : super.withClient(
        const Env(googleMapsApiKey: 'unused'),
        client: _unusedClient(),
      );

  /// When set, lookups wait on it, so a test can see the in-flight state.
  Completer<void>? gate;

  @override
  Future<String?> reverseGeocode(Coordinates coordinates) async {
    await gate?.future;
    return 'Prinsengracht 263, Amsterdam';
  }
}

class _FakeMap extends StatelessWidget {
  const _FakeMap({required this.selectCoordinates});

  final ChooseLocationCoordinateSelector selectCoordinates;

  @override
  Widget build(BuildContext context) => GestureDetector(
    key: const Key('ChooseLocation.FakeMap'),
    behavior: HitTestBehavior.opaque,
    onTap: () => unawaited(selectCoordinates(_mapTap, moveCamera: false)),
    child: const SizedBox.expand(),
  );
}

void main() {
  late _FakePlacesService placesService;
  late _FakeGeocodingService geocodingService;
  Location? result;

  void register(GooglePlacesService places) {
    geocodingService = _FakeGeocodingService();
    GetIt.I.registerSingleton<Env>(const Env(googleMapsApiKey: 'test-key'));
    GetIt.I.registerSingleton<GeoRepository>(GeoRepository(Logger('test')));
    GetIt.I.registerSingleton<GooglePlacesService>(places);
    GetIt.I.registerSingleton<GoogleGeocodingService>(geocodingService);
  }

  setUp(() {
    result = null;
    placesService = _FakePlacesService();
    register(placesService);
  });

  tearDown(() async => GetIt.I.reset());

  Future<void> openDialog(
    WidgetTester tester, {
    Locale locale = const Locale('en'),
  }) async {
    await tester.pumpWidget(
      MaterialApp(
        locale: locale,
        localizationsDelegates: L10n.localizationsDelegates,
        supportedLocales: L10n.supportedLocales,
        theme: TenturaTheme.light(),
        home: Builder(
          builder: (context) => Scaffold(
            body: Center(
              child: FilledButton(
                onPressed: () async {
                  result = await showDialog<Location>(
                    context: context,
                    useSafeArea: false,
                    builder: (_) => ChooseLocationDialog(
                      mapBuilder: (context, center, selected, select) =>
                          _FakeMap(selectCoordinates: select),
                    ),
                  );
                },
                child: const Text('Open picker'),
              ),
            ),
          ),
        ),
      ),
    );
    await tester.tap(find.text('Open picker'));
    await tester.pumpAndSettle();
  }

  Future<void> typeQuery(WidgetTester tester, {bool settle = true}) async {
    await tester.tap(find.byType(SearchBar));
    await tester.pump();
    await tester.enterText(find.byType(EditableText).last, 'Museum');
    await tester.pump();
    if (settle) {
      await tester.pump(const Duration(milliseconds: 350));
      await tester.pumpAndSettle();
    }
  }

  List<LogRecord> captureLogs() {
    final records = <LogRecord>[];
    final sub = Logger.root.onRecord.listen(records.add);
    addTearDown(sub.cancel);
    return records;
  }

  const englishStrings = [
    'Search address',
    'Searching...',
    'Choose a location',
    'Resolving address...',
    'Use this location',
  ];

  group('picker strings are localized (#607)', () {
    testWidgets('English keeps the existing wording', (tester) async {
      await openDialog(tester);

      expect(find.text('Search address'), findsOneWidget);
      expect(find.text('Choose a location'), findsOneWidget);
      expect(
        find.widgetWithText(FilledButton, 'Use this location'),
        findsOneWidget,
      );
    });

    testWidgets('Russian shows no English text in the bars', (tester) async {
      final l10n = await L10n.delegate.load(const Locale('ru'));
      await openDialog(tester, locale: const Locale('ru'));

      for (final english in englishStrings) {
        expect(find.text(english), findsNothing, reason: english);
      }
      expect(find.text(l10n.chooseLocationSearchHint), findsOneWidget);
      expect(find.text(l10n.chooseLocationNoneSelected), findsOneWidget);
      expect(
        find.widgetWithText(FilledButton, l10n.chooseLocationConfirm),
        findsOneWidget,
      );
      expect(l10n.chooseLocationConfirm, isNot('Use this location'));
    });

    testWidgets('Russian "searching" row is translated', (tester) async {
      final l10n = await L10n.delegate.load(const Locale('ru'));
      placesService.autocompleteGate = Completer<void>();
      await openDialog(tester, locale: const Locale('ru'));

      await typeQuery(tester, settle: false);
      await tester.pump(const Duration(milliseconds: 350));

      expect(find.text('Searching...'), findsNothing);
      expect(find.text(l10n.chooseLocationSearching), findsOneWidget);

      placesService.autocompleteGate!.complete();
      await tester.pumpAndSettle();
    });

    testWidgets('Russian "resolving address" text is translated', (
      tester,
    ) async {
      final l10n = await L10n.delegate.load(const Locale('ru'));
      geocodingService.gate = Completer<void>();
      await openDialog(tester, locale: const Locale('ru'));

      await tester.tap(find.byKey(const Key('ChooseLocation.FakeMap')));
      await tester.pump();

      expect(find.text('Resolving address...'), findsNothing);
      expect(find.text(l10n.chooseLocationResolvingAddress), findsOneWidget);

      geocodingService.gate!.complete();
      await tester.pumpAndSettle();
    });
  });

  group('a failed place-details lookup is handled (#607)', () {
    Future<void> pickSuggestion(WidgetTester tester) async {
      await openDialog(tester);
      await typeQuery(tester);
      expect(find.text(_prediction.description), findsOneWidget);
      await tester.tap(find.text(_prediction.description));
      await tester.pumpAndSettle();
    }

    testWidgets('a refused lookup shows "search unavailable" and logs', (
      tester,
    ) async {
      final logs = captureLogs();
      placesService.detailsError = StateError(
        'Google Places details failed (403): PERMISSION_DENIED',
      );

      await pickSuggestion(tester);

      expect(tester.takeException(), isNull);
      expect(
        find.text(
          'Address search isn’t available right now. Tap the map to drop a '
          'pin instead.',
        ),
        findsOneWidget,
      );
      expect(
        logs.where(
          (r) =>
              r.loggerName == 'ChooseLocationDialog' && r.error is StateError,
        ),
        isNotEmpty,
      );

      // Nothing was picked: the bar still asks for a location.
      expect(find.text('Choose a location'), findsOneWidget);
    });

    testWidgets('a network failure shows "search failed"', (tester) async {
      placesService.detailsError = http.ClientException('offline');

      await pickSuggestion(tester);

      expect(tester.takeException(), isNull);
      expect(
        find.text(
          'Address search failed. Check your connection and try again.',
        ),
        findsOneWidget,
      );
    });

    testWidgets('the picker still works after a failed lookup', (
      tester,
    ) async {
      placesService.detailsError = http.ClientException('offline');
      await pickSuggestion(tester);

      await tester.tap(find.byKey(const Key('ChooseLocation.FakeMap')));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Use this location'));
      await tester.pumpAndSettle();

      expect(result?.coords, _mapTap);
    });
  });

  group('search failures are classified by type, not text (#607)', () {
    testWidgets('a missing key from the service shows the key hint', (
      tester,
    ) async {
      // The real service, with no key of its own: it refuses with the typed
      // error before any request is made.
      await GetIt.I.reset();
      register(
        GooglePlacesService.withClient(
          const Env(googleMapsApiKey: ''),
          client: _unusedClient(),
        ),
      );
      await openDialog(tester);

      await typeQuery(tester);

      expect(
        find.text(
          'Google Maps isn’t configured. Add GOOGLE_MAPS_API_KEY to .env, '
          'then restart the app.',
        ),
        findsOneWidget,
      );
    });

    testWidgets('Google text naming the key is not read as a missing key', (
      tester,
    ) async {
      placesService.autocompleteError = StateError(
        'Google Places autocomplete failed (400): '
        'GOOGLE_MAPS_API_KEY is not configured for this project',
      );
      await openDialog(tester);

      await typeQuery(tester);

      expect(find.textContaining('Google Maps isn’t configured'), findsNothing);
      expect(
        find.text(
          'Address search isn’t available right now. Tap the map to drop a '
          'pin instead.',
        ),
        findsOneWidget,
      );
    });

    testWidgets('a failed search is logged', (tester) async {
      final logs = captureLogs();
      placesService.autocompleteError = http.ClientException('offline');
      await openDialog(tester);

      await typeQuery(tester);

      expect(
        find.text(
          'Address search failed. Check your connection and try again.',
        ),
        findsOneWidget,
      );
      expect(
        logs.where(
          (r) =>
              r.loggerName == 'ChooseLocationDialog' &&
              r.error is http.ClientException,
        ),
        isNotEmpty,
      );
    });
  });

  group('services report a missing key with a typed error (#607)', () {
    test('places autocomplete and details', () async {
      final service = GooglePlacesService.withClient(
        const Env(googleMapsApiKey: ''),
        client: _unusedClient(),
      );
      await expectLater(
        service.autocomplete(input: 'Muse', sessionToken: 't'),
        throwsA(isA<GoogleMapsKeyMissingError>()),
      );
      await expectLater(
        service.details(placeId: 'p', sessionToken: 't'),
        throwsA(isA<GoogleMapsKeyMissingError>()),
      );
    });

    test('reverse geocoding', () async {
      final service = GoogleGeocodingService.withClient(
        const Env(googleMapsApiKey: ''),
        client: _unusedClient(),
      );
      await expectLater(
        service.reverseGeocode(_mapTap),
        throwsA(isA<GoogleMapsKeyMissingError>()),
      );
    });

    test('is still a StateError with the same message', () {
      final error = GoogleMapsKeyMissingError();
      expect(error, isA<StateError>());
      expect(error.message, 'GOOGLE_MAPS_API_KEY is not configured');
    });
  });
}
