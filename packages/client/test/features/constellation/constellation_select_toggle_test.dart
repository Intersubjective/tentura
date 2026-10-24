import 'dart:ui' show Tristate;

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:tentura/design_system/tentura_design_system.dart';
import 'package:tentura/domain/entity/profile.dart';
import 'package:tentura/features/beacon_create/ui/bloc/beacon_create_cubit.dart';
import 'package:tentura/features/constellation/domain/entity/constellation_anchor_projection.dart';
import 'package:tentura/features/constellation/domain/entity/constellation_field.dart';
import 'package:tentura/features/constellation/domain/port/constellation_repository_port.dart';
import 'package:tentura/features/constellation/ui/bloc/constellation_composer_cubit.dart';
import 'package:tentura/features/constellation/ui/bloc/constellation_cubit.dart';
import 'package:tentura/features/constellation/ui/bloc/constellation_selection_cubit.dart';
import 'package:tentura/features/constellation/ui/widget/constellation_app_bar.dart';
import 'package:tentura/features/forward/ui/bloc/forward_cubit.dart';
import 'package:tentura/ui/l10n/l10n.dart';

import '../../support/constellation_store_fixture.dart';

// The select tool's toolbar toggle (#642): on the map only; on a phone it
// is in the field toolbar's overflow menu (#659).

const _ego = Profile(id: 'ego', displayName: 'Ego');

final class _StubRepository implements ConstellationRepositoryPort {
  @override
  Future<ConstellationField> fetch({
    ConstellationFieldMembershipFilters membershipFilters =
        ConstellationFieldMembershipFilters.defaults,
    ConstellationProjection projection = ConstellationProjection.full,
  }) async => ConstellationField(
    loadedAt: DateTime.utc(2026, 10, 22),
    context: '',
    peers: const [ConstellationPerson(id: 'a', displayName: 'Ann')],
    edges: const [ConstellationTrustEdgeEntity(src: 'ego', dst: 'a', tier: 1)],
  );
}

Future<void> _pump(
  WidgetTester tester, {
  required ConstellationCubit cubit,
  required ConstellationSelectionCubit selection,
  required Size size,
  Locale locale = const Locale('en'),
}) async {
  await tester.binding.setSurfaceSize(size);
  addTearDown(() => tester.binding.setSurfaceSize(null));
  final composer = ConstellationComposerCubit(
    positions: const {},
    eligible: const {},
    createCubitFactory: (kind) => BeaconCreateCubit(kind: kind),
    forwardCubitFactory: (beaconId) =>
        ForwardCubit(beaconId: beaconId, embedded: true),
  );
  addTearDown(composer.close);
  await tester.pumpWidget(
    MaterialApp(
      locale: locale,
      theme: TenturaTheme.light(),
      localizationsDelegates: L10n.localizationsDelegates,
      supportedLocales: L10n.supportedLocales,
      home: MediaQuery(
        data: MediaQueryData(size: size),
        child: TenturaResponsiveScope(
          child: MultiBlocProvider(
            providers: [
              BlocProvider.value(value: cubit),
              BlocProvider.value(value: selection),
              BlocProvider.value(value: composer),
            ],
            child: Builder(
              builder: (context) => Scaffold(
                appBar: TenturaTopBar.of(
                  context,
                  title: const SizedBox.shrink(),
                  row: ConstellationAppBarRow(
                    legendExpanded: false,
                    onToggleLegend: () {},
                  ),
                ),
                body: const SizedBox.expand(),
              ),
            ),
          ),
        ),
      ),
    ),
  );
  await tester.pumpAndSettle();
}

final _toggle = find.byKey(const Key('constellation.app_bar.select'));

void main() {
  late ConstellationCubit cubit;
  late ConstellationSelectionCubit selection;

  setUp(() {
    selection = ConstellationSelectionCubit();
    addTearDown(selection.close);
  });

  Future<void> load(WidgetTester tester) async {
    cubit = ConstellationCubit(
      case_: ConstellationStoreFixture(
        _StubRepository(),
        accountId: 'ego',
      ).store,
      viewer: _ego,
    );
    addTearDown(cubit.close);
    await tester.runAsync(
      () => cubit.stream.firstWhere((state) => state.status is StateIsSuccess),
    );
  }

  testWidgets('the toggle turns the select tool on and off', (tester) async {
    await load(tester);
    await _pump(
      tester,
      cubit: cubit,
      selection: selection,
      size: const Size(900, 800),
    );

    await tester.tap(_toggle);
    await tester.pumpAndSettle();
    expect(selection.state.selecting, isTrue);
    expect(tester.widget<IconButton>(_toggle).isSelected, isTrue);
    expect(find.byTooltip('Select several'), findsOneWidget);

    await tester.tap(_toggle);
    await tester.pumpAndSettle();
    expect(selection.state.selecting, isFalse);
  });

  // #678: the on/off state was exposed only as "current".
  testWidgets('the toggle exposes its on/off state', (tester) async {
    final semantics = tester.ensureSemantics();
    await load(tester);
    await _pump(
      tester,
      cubit: cubit,
      selection: selection,
      size: const Size(900, 800),
    );

    var data = tester.getSemantics(_toggle).getSemanticsData();
    expect(data.flagsCollection.isButton, isTrue);
    expect(data.flagsCollection.isToggled, Tristate.isFalse);

    await tester.tap(_toggle);
    await tester.pumpAndSettle();
    data = tester.getSemantics(_toggle).getSemanticsData();
    expect(data.flagsCollection.isToggled, Tristate.isTrue);
    semantics.dispose();
  });

  testWidgets('it is hidden in the list view', (tester) async {
    await load(tester);
    await _pump(
      tester,
      cubit: cubit,
      selection: selection,
      size: const Size(900, 800),
    );
    cubit.setViewMode(ConstellationViewMode.text);
    await tester.pumpAndSettle();

    final visibility = tester.widget<Visibility>(
      find.ancestor(of: _toggle, matching: find.byType(Visibility)).first,
    );
    expect(visibility.visible, isFalse);
  });

  for (final (locale, width) in [
    (const Locale('en'), 360.0),
    (const Locale('ru'), 360.0),
    (const Locale('ru'), 320.0),
  ]) {
    testWidgets('fits the toolbar at $width dp in $locale', (tester) async {
      await load(tester);
      await _pump(
        tester,
        cubit: cubit,
        selection: selection,
        size: Size(width, 800),
        locale: locale,
      );
      expect(tester.takeException(), isNull);
      // On a phone it sits in the bar's overflow menu (#659).
      expect(_toggle, findsNothing);
      await tester.tap(find.byKey(const Key('constellation.app_bar.more')));
      await tester.pumpAndSettle();
      await tester.tap(
        find.byKey(const Key('constellation.app_bar.more.select')),
      );
      await tester.pumpAndSettle();
      expect(selection.state.selecting, isTrue);
    });
  }
}
