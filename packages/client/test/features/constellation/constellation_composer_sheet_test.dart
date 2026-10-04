// The graph composer's sheet: «Получат · n» recipient chips with ×, a
// wide-layout side panel and full-form hand-off. The radius itself is
// controlled on the canvas (the composer circle's rim handle, see
// constellation_composer_radius_test.dart), not by this sheet — these tests
// drive `composer.setRadius` directly to cover how the sheet reacts.

import 'dart:async';
import 'dart:ui' show Offset;

import 'package:auto_route/auto_route.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:get_it/get_it.dart';
import 'package:mockito/mockito.dart';

import 'package:tentura/app/router/root_router.dart';
import 'package:tentura/design_system/tentura_design_system.dart';
import 'package:tentura/domain/entity/beacon_kind.dart';
import 'package:tentura/domain/entity/invitation_entity.dart';
import 'package:tentura/domain/entity/profile.dart';
import 'package:tentura/features/beacon_create/ui/bloc/beacon_create_cubit.dart';
import 'package:tentura/features/constellation/ui/bloc/constellation_composer_cubit.dart';
import 'package:tentura/features/constellation/ui/widget/constellation_composer_sheet.dart';
import 'package:tentura/features/forward/domain/entity/forward_candidate.dart';
import 'package:tentura/features/forward/ui/bloc/forward_cubit.dart';
import 'package:tentura/features/forward/ui/widget/forward_recipient_picker.dart';
import 'package:tentura/features/invitation/data/repository/invitation_repository.dart';
import 'package:tentura/features/profile/ui/bloc/profile_cubit.dart';
import 'package:tentura/ui/effect/ui_effect_port.dart';
import 'package:tentura/ui/l10n/l10n.dart';
import 'package:tentura/ui/test_ids.dart';

import '../../ui/effect/fake_ui_effect_port.dart';
import '../beacon_create/fake_beacon_ports.dart';

const _sidePanel = Key('constellation.composer.side_panel');
const _bottomSheet = Key('constellation.composer.sheet');
const _listButton = Key('constellation.composer.list_button');
const _detailsButton = Key('constellation.composer.details_button');

/// Widens the circle past Ud (distance 100) but not Ue (distance 200).
const _wideRadius = 150.0;

/// Narrows the circle to exclude Ua, Ub and Uc (distances 10/20/30).
const _narrowRadius = 5.0;

Key _chip(String id) => Key('constellation.composer.chip.$id');

Key _chipRemove(String id) => Key('constellation.composer.chip_remove.$id');

/// Three people close to the draft, two far away.
const _positions = <String, Offset>{
  'Ua': Offset(10, 0),
  'Ub': Offset(20, 0),
  'Uc': Offset(30, 0),
  'Ud': Offset(100, 0),
  'Ue': Offset(200, 0),
};

final _profiles = [
  for (final id in _positions.keys)
    Profile(
      id: id,
      displayName: 'Person $id',
      sharesActiveContext: true,
      score: 1,
      rScore: 1,
    ),
];

class _MockProfileCubit extends Mock implements ProfileCubit {
  @override
  ProfileState get state => const ProfileState();

  @override
  Stream<ProfileState> get stream => Stream<ProfileState>.value(state);
}

class _FakeInvitationRepository extends Fake implements InvitationRepository {
  @override
  Stream<void> get changes => const Stream<void>.empty();

  @override
  Future<InvitationsFetchResult> fetchMine({
    int pendingOffset = 0,
    int pendingLimit = 0,
    int acceptedOffset = 0,
    int acceptedLimit = 0,
  }) async => (
    pending: <InvitationEntity>[],
    accepted: <InvitationEntity>[],
    pendingCount: 0,
  );

  @override
  Future<InvitationFetchByIdResult?> fetchById(String id) async => null;

  @override
  Future<void> dispose() async {}
}

void main() {
  late FakeUiEffectPort effects;
  late ConstellationComposerCubit composer;
  late List<ForwardCubit> forwards;

  setUp(() {
    effects = FakeUiEffectPort();
    forwards = [];
    GetIt.I
      ..registerSingleton<UiEffectPort>(effects)
      ..registerSingleton<InvitationRepository>(_FakeInvitationRepository());
    composer = ConstellationComposerCubit(
      positions: _positions,
      eligible: _positions.keys.toSet(),
      createCubitFactory: (kind) => BeaconCreateCubit(
        kind: kind,
        beaconCreateCase: fakeBeaconCreateCase(write: FakeBeaconWritePort()),
        effects: effects,
      ),
      forwardCubitFactory: (beaconId) {
        final cubit = ForwardCubit(
          beaconId: beaconId,
          embedded: true,
          effects: effects,
          debugSkipInitialLoad: true,
        );
        forwards.add(cubit);
        return cubit;
      },
    );
  });

  tearDown(() async {
    await composer.close();
    // A Post hand-off already closes its ForwardCubit via composer.finish()
    // — ForwardCubit.close() is a no-op when already closed.
    for (final f in forwards) {
      await f.close();
    }
    await GetIt.I.unregister<InvitationRepository>();
    await GetIt.I.unregister<UiEffectPort>();
  });

  /// Starts a Post composer at the origin (start radius 33: Ua, Ub, Uc are
  /// selected) and creates the server draft with its list candidates.
  Future<ForwardCubit> startPost(WidgetTester tester) async {
    composer.start(BeaconKind.post, Offset.zero);
    // Draft creation is real async work, outside the widget tester's clock.
    await tester.runAsync(() async {
      await composer.contentChanged();
      await Future<void>.delayed(Duration.zero);
    });
    final forward = composer.forwardCubit!;
    forward.emit(
      forward.state.copyWith(
        candidates: [for (final p in _profiles) ForwardCandidate(profile: p)],
        candidatesLoad: const ForwardCandidatesReady(),
      ),
    );
    return forward;
  }

  Future<void> pumpSheet(WidgetTester tester, {required Size size}) async {
    tester.view
      ..physicalSize = size
      ..devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    await tester.pumpWidget(
      MaterialApp(
        locale: const Locale('en'),
        theme: TenturaTheme.light(),
        localizationsDelegates: L10n.localizationsDelegates,
        supportedLocales: L10n.supportedLocales,
        home: TenturaResponsiveScope(
          child: MultiBlocProvider(
            providers: [
              BlocProvider<ConstellationComposerCubit>.value(value: composer),
              BlocProvider<ProfileCubit>.value(value: _MockProfileCubit()),
            ],
            child: Scaffold(
              body: ConstellationComposerSheet(
                composer: composer,
                onOpenFullForm: (_) {},
              ),
            ),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();
  }

  const narrow = Size(420, 900);
  const wide = Size(1200, 900);

  group('composer sheet recipients', () {
    testWidgets('shows one chip per selected person and none for the rest', (
      tester,
    ) async {
      await startPost(tester);
      await pumpSheet(tester, size: narrow);

      for (final id in ['Ua', 'Ub', 'Uc']) {
        expect(find.byKey(_chip(id)), findsOneWidget, reason: id);
      }
      expect(find.byKey(_chip('Ud')), findsNothing);
      expect(find.byKey(_chip('Ue')), findsNothing);
    });

    testWidgets('chip × removes the person from the selection and the forward '
        'draft, and a larger radius does not bring them back', (tester) async {
      final forward = await startPost(tester);
      await pumpSheet(tester, size: narrow);

      await tester.tap(find.byKey(_chipRemove('Ub')));
      await tester.pumpAndSettle();

      expect(find.byKey(_chip('Ub')), findsNothing);
      expect(composer.selection.selected, {'Ua', 'Uc'});
      expect(forward.state.selectedIds, {'Ua', 'Uc'});

      final radiusBefore = composer.selection.radius;
      composer.setRadius(_wideRadius);
      await tester.pumpAndSettle();

      expect(composer.selection.radius, greaterThan(radiusBefore));
      expect(composer.selection.selected, containsAll(['Ua', 'Uc', 'Ud']));
      expect(composer.selection.selected, isNot(contains('Ub')));
      expect(forward.state.selectedIds, composer.selection.selected);
      expect(find.byKey(_chip('Ub')), findsNothing);
      expect(find.byKey(_chip('Ud')), findsOneWidget);
    });
  });

  group('composer sheet reacts to radius changes', () {
    testWidgets('a wider radius grows the selection', (tester) async {
      await startPost(tester);
      await pumpSheet(tester, size: narrow);
      final before = composer.selection;

      composer.setRadius(_wideRadius);
      await tester.pumpAndSettle();

      expect(composer.selection.radius, greaterThan(before.radius));
      expect(
        composer.selection.selected.length,
        greaterThan(before.selected.length),
      );
      expect(composer.selection.selected, containsAll(before.selected));
    });

    testWidgets('a narrower radius shrinks the selection', (tester) async {
      await startPost(tester);
      await pumpSheet(tester, size: narrow);
      final before = composer.selection;

      composer.setRadius(_narrowRadius);
      await tester.pumpAndSettle();

      expect(composer.selection.radius, lessThan(before.radius));
      expect(
        composer.selection.selected.length,
        lessThan(before.selected.length),
      );
    });
  });

  group('composer sheet full-form hand-off button', () {
    testWidgets(
      'for a Post: labeled «Создать», opens PostCreateRoute with the '
      'current selection, and closes the composer',
      (tester) async {
        final opened = <PageRouteInfo>[];
        await startPost(tester);
        tester.view
          ..physicalSize = narrow
          ..devicePixelRatio = 1;
        addTearDown(tester.view.reset);
        await tester.pumpWidget(
          MaterialApp(
            locale: const Locale('en'),
            theme: TenturaTheme.light(),
            localizationsDelegates: L10n.localizationsDelegates,
            supportedLocales: L10n.supportedLocales,
            home: TenturaResponsiveScope(
              child: MultiBlocProvider(
                providers: [
                  BlocProvider<ConstellationComposerCubit>.value(
                    value: composer,
                  ),
                  BlocProvider<ProfileCubit>.value(value: _MockProfileCubit()),
                ],
                child: Scaffold(
                  body: ConstellationComposerSheet(
                    composer: composer,
                    onOpenFullForm: opened.add,
                  ),
                ),
              ),
            ),
          ),
        );
        await tester.pumpAndSettle();
        final l10n = lookupL10n(const Locale('en'));
        expect(find.text(l10n.constellationComposerCreate), findsOneWidget);
        composer.toggleManualSelection();
        composer.toggleMapRecipient('Ue');
        final centerBefore = composer.selection.center;
        final radiusBefore = composer.selection.radius;
        final selectedBefore = composer.selection.selected;

        await tester.tap(find.byKey(_detailsButton));
        await tester.pump();

        final route = opened.single;
        expect(route, isA<PostCreateRoute>());
        final args = route.args! as PostCreateRouteArgs;
        expect(args.initialRecipientIds, selectedBefore);
        expect(args.initialRecipientIds, contains('Ue'));
        args.onRecipientsChanged!.call({'Ud', 'Ue'}, const {});
        await tester.pumpAndSettle();
        expect(composer.selection.center, centerBefore);
        expect(composer.selection.radius, radiusBefore);
        expect(composer.selection.manualSelectionEnabled, isTrue);
        expect(composer.selection.selected, {'Ud', 'Ue'});
        expect(composer.selection.manualAdded, containsAll(['Ud', 'Ue']));
        composer.setRadius(_wideRadius);
        expect(composer.selection.selected, {'Ud', 'Ue'});
        expect(
          composer.createCubit,
          isNotNull,
          reason: 'closing the full form must restore the map session',
        );
      },
    );

    testWidgets('for a Request: labeled «Подробнее»', (tester) async {
      composer.start(BeaconKind.request, Offset.zero);
      await pumpSheet(tester, size: narrow);

      final l10n = lookupL10n(const Locale('en'));
      expect(find.byKey(_detailsButton), findsOneWidget);
      expect(find.text(l10n.constellationComposerDetails), findsOneWidget);
    });
  });

  group('composer sheet layout', () {
    testWidgets('narrow viewport shows the bottom sheet, not a side panel', (
      tester,
    ) async {
      await startPost(tester);
      await pumpSheet(tester, size: narrow);

      expect(find.byKey(_bottomSheet), findsOneWidget);
      expect(find.byKey(_sidePanel), findsNothing);
    });

    testWidgets('wide viewport shows a side panel, not the bottom sheet', (
      tester,
    ) async {
      await startPost(tester);
      await pumpSheet(tester, size: wide);

      expect(find.byKey(_sidePanel), findsOneWidget);
      expect(find.byKey(_bottomSheet), findsNothing);
      expect(find.byKey(_chip('Ua')), findsOneWidget);
    });
  });

  testWidgets('composer offers chips and create without a list picker', (
    tester,
  ) async {
    await startPost(tester);
    await pumpSheet(tester, size: narrow);

    expect(find.byKey(_listButton), findsNothing);
    expect(find.byType(ForwardRecipientPicker), findsNothing);
    expect(find.byKey(_detailsButton), findsOneWidget);
    expect(find.byKey(_chip('Ua')), findsOneWidget);
    final add = find.byKey(const Key('constellation.composer.add_person'));
    expect(tester.widget<IconButton>(add).isSelected, isFalse);
    await tester.tap(add);
    await tester.pumpAndSettle();
    expect(tester.widget<IconButton>(add).isSelected, isTrue);
    composer.toggleMapRecipient('Ue');
    await tester.pumpAndSettle();
    expect(find.byKey(_chip('Ue')), findsOneWidget);
    composer.setRadius(_narrowRadius);
    await tester.pumpAndSettle();
    expect(composer.selection.selected, {'Ue'});
    composer.toggleMapRecipient('Ue');
    await tester.pumpAndSettle();
    expect(find.byKey(_chip('Ue')), findsNothing);
    await tester.tap(add);
    await tester.pumpAndSettle();
    composer.toggleMapRecipient('Ud');
    expect(composer.selection.selected, isEmpty);
  });

  group('forward recipient picker toggle override', () {
    testWidgets('routes a row toggle to onToggle instead of the cubit', (
      tester,
    ) async {
      final forward = await startPost(tester);
      final toggled = <String>[];
      tester.view
        ..physicalSize = const Size(1200, 2400)
        ..devicePixelRatio = 1;
      addTearDown(tester.view.reset);
      await tester.pumpWidget(
        MaterialApp(
          locale: const Locale('en'),
          theme: TenturaTheme.light(),
          localizationsDelegates: L10n.localizationsDelegates,
          supportedLocales: L10n.supportedLocales,
          home: MultiBlocProvider(
            providers: [
              BlocProvider<ForwardCubit>.value(value: forward),
              BlocProvider<ProfileCubit>.value(value: _MockProfileCubit()),
            ],
            child: Scaffold(
              body: ForwardRecipientPicker(
                beaconId: forward.state.beaconId,
                embedded: true,
                onToggle: toggled.add,
              ),
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();
      final selectedBefore = forward.state.selectedIds;

      await tester.tap(
        find.byKey(TestIds.key(TestIds.forwardRecipientCheckbox('Ud'))),
      );
      await tester.pumpAndSettle();

      expect(toggled, ['Ud']);
      expect(forward.state.selectedIds, selectedBefore);
    });
  });
}
