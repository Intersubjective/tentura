import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:get_it/get_it.dart';
import 'package:mockito/mockito.dart';

import 'package:tentura/design_system/tentura_theme.dart';
import 'package:tentura/domain/entity/beacon_schedule.dart';
import 'package:tentura/env.dart';
import 'package:tentura/features/beacon_create/ui/bloc/beacon_create_cubit.dart';
import 'package:tentura/features/beacon_create/ui/widget/info_tab.dart';
import 'package:tentura/features/geo/data/repository/geo_repository.dart';
import 'package:tentura/features/geo/data/service/google_geocoding_service.dart';
import 'package:tentura/features/geo/data/service/google_places_service.dart';
import 'package:tentura/features/geo/ui/dialog/choose_location_dialog.dart';
import 'package:tentura/ui/l10n/l10n.dart';

import '../../ui/effect/fake_ui_effect_port.dart';
import 'fake_beacon_ports.dart';

class _GeoRepositoryMock extends Mock implements GeoRepository {}

/// One Request-editor row that opens an overlay, plus how to count the
/// overlays currently stacked for it.
class _SheetRow {
  const _SheetRow({
    required this.name,
    required this.rowKey,
    required this.openOverlays,
  });

  final String name;
  final Key rowKey;
  final Finder Function() openOverlays;
}

final _sheetRows = <_SheetRow>[
  _SheetRow(
    name: 'requirements',
    rowKey: const Key('BeaconCreate.RequirementsRow'),
    openOverlays: () => find.byType(DraggableScrollableSheet),
  ),
  _SheetRow(
    name: 'cover',
    rowKey: const Key('BeaconCreate.CoverRow'),
    openOverlays: () => find.byType(DraggableScrollableSheet),
  ),
  _SheetRow(
    name: 'timing',
    rowKey: const Key('BeaconCreate.TimingRow'),
    openOverlays: () => find.byType(SegmentedButton<BeaconScheduleKind>),
  ),
];

Widget _editorHarness(BeaconCreateCubit cubit) => MaterialApp(
  locale: const Locale('en'),
  localizationsDelegates: L10n.localizationsDelegates,
  supportedLocales: L10n.supportedLocales,
  theme: TenturaTheme.light(),
  home: MediaQuery(
    data: const MediaQueryData(size: Size(390, 1200)),
    child: Scaffold(
      body: BlocProvider<BeaconCreateCubit>.value(
        value: cubit,
        child: const Form(child: InfoTab()),
      ),
    ),
  ),
);

void main() {
  late BeaconCreateCubit cubit;

  setUp(() {
    GetIt.I.registerSingleton<Env>(const Env(googleMapsApiKey: 'test-key'));
  });

  tearDown(() async {
    await cubit.close();
    await GetIt.I.reset();
  });

  void registerGeoServices() {
    final geo = _GeoRepositoryMock();
    when(geo.myCoordinates).thenReturn(null);
    GetIt.I
      ..registerSingleton<GeoRepository>(geo)
      ..registerSingleton<GooglePlacesService>(
        GooglePlacesService(const Env(googleMapsApiKey: 'test-key')),
      )
      ..registerSingleton<GoogleGeocodingService>(
        GoogleGeocodingService(const Env(googleMapsApiKey: 'test-key')),
      );
  }

  /// Fires the row's tap handler directly. A real tap would hit the modal
  /// barrier while an overlay is up, but a second handler call can still
  /// arrive from a queued tap, a keyboard activation or a double-click.
  void activateRow(WidgetTester tester, Key rowKey) =>
      tester.widget<InkWell>(find.byKey(rowKey)).onTap!();

  BeaconCreateCubit buildCubit({FakeBeaconWritePort? write}) =>
      cubit = BeaconCreateCubit(
        beaconCreateCase: fakeBeaconCreateCase(write: write),
        effects: FakeUiEffectPort(),
      );

  /// Taps [target] [times] times back to back, with no frame in between, like
  /// a user hammering a control that has not reacted yet.
  Future<void> rapidTaps(
    WidgetTester tester,
    Finder target, {
    int times = 3,
  }) async {
    await tester.ensureVisible(target);
    for (var i = 0; i < times; i++) {
      await tester.tap(target);
    }
  }

  group('Request editor overlay rows ignore repeat taps', () {
    for (final row in _sheetRows) {
      testWidgets(
        'taps made while the ${row.name} sheet is still being prepared do not '
        'queue more sheets behind it',
        (tester) async {
          // A title and description make the draft flush before the sheet
          // opens hit the (held) server, so the open is slow.
          final write = FakeBeaconWritePort()..createHold = Completer<void>();
          buildCubit(write: write)
            ..setTitle('Need a piano moved')
            ..setDescription('Two flights of stairs, this weekend.');
          await tester.pumpWidget(_editorHarness(cubit));
          await tester.pumpAndSettle();

          await rapidTaps(tester, find.byKey(row.rowKey));
          await tester.pump();
          expect(row.openOverlays(), findsNothing);

          write.createHold!.complete();
          await tester.pumpAndSettle();

          expect(row.openOverlays(), findsOneWidget);
        },
      );

      testWidgets(
        'taps made while the ${row.name} sheet is already open do not stack '
        'another one on top',
        (tester) async {
          await tester.pumpWidget(_editorHarness(buildCubit()));
          await tester.pumpAndSettle();

          await rapidTaps(tester, find.byKey(row.rowKey), times: 1);
          await tester.pumpAndSettle();
          expect(row.openOverlays(), findsOneWidget);

          activateRow(tester, row.rowKey);
          activateRow(tester, row.rowKey);
          await tester.pumpAndSettle();

          expect(row.openOverlays(), findsOneWidget);
        },
      );

      testWidgets(
        'the ${row.name} row opens its sheet again after the previous one '
        'was dismissed',
        (tester) async {
          await tester.pumpWidget(_editorHarness(buildCubit()));
          await tester.pumpAndSettle();

          await rapidTaps(tester, find.byKey(row.rowKey), times: 1);
          await tester.pumpAndSettle();
          expect(row.openOverlays(), findsOneWidget);

          await tester.tapAt(const Offset(20, 20));
          await tester.pumpAndSettle();
          expect(row.openOverlays(), findsNothing);

          await rapidTaps(tester, find.byKey(row.rowKey), times: 1);
          await tester.pumpAndSettle();
          expect(row.openOverlays(), findsOneWidget);
        },
      );
    }

    testWidgets(
      'taps made while the location dialog is still being prepared do not '
      'queue more dialogs behind it',
      (tester) async {
        registerGeoServices();
        final write = FakeBeaconWritePort()..createHold = Completer<void>();
        buildCubit(write: write)
          ..setTitle('Need a piano moved')
          ..setDescription('Two flights of stairs, this weekend.');
        await tester.pumpWidget(_editorHarness(cubit));
        await tester.pumpAndSettle();

        await rapidTaps(
          tester,
          find.byKey(const Key('BeaconCreate.LocationRow')),
        );
        await tester.pump();
        expect(find.byType(ChooseLocationDialog), findsNothing);

        write.createHold!.complete();
        await tester.pumpAndSettle();

        expect(find.byType(ChooseLocationDialog), findsOneWidget);
      },
    );

    testWidgets(
      'taps made while the location dialog is already open do not stack '
      'another one on top',
      (tester) async {
        registerGeoServices();
        await tester.pumpWidget(_editorHarness(buildCubit()));
        await tester.pumpAndSettle();
        const locationRow = Key('BeaconCreate.LocationRow');

        await rapidTaps(tester, find.byKey(locationRow), times: 1);
        await tester.pumpAndSettle();
        expect(find.byType(ChooseLocationDialog), findsOneWidget);

        activateRow(tester, locationRow);
        activateRow(tester, locationRow);
        await tester.pumpAndSettle();

        expect(find.byType(ChooseLocationDialog), findsOneWidget);
      },
    );
  });
}
