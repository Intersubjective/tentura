// The graph composer's sheet: «Получат · n» recipient chips with ×, a radius
// slider, a wide-layout side panel, and the «Списком» hand-off that opens the
// embedded `ForwardRecipientPicker` on the composer's `ForwardCubit` with its
// toggles routed through `ConstellationComposerCubit.toggle`.

import 'dart:async';
import 'dart:ui' show Offset;

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:get_it/get_it.dart';
import 'package:mockito/mockito.dart';

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
const _radiusSlider = Key('constellation.composer.radius_slider');

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
              body: ConstellationComposerSheet(composer: composer),
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
      await tester.drag(find.byKey(_radiusSlider), const Offset(2000, 0));
      await tester.pumpAndSettle();

      expect(composer.selection.radius, greaterThan(radiusBefore));
      expect(composer.selection.selected, containsAll(['Ua', 'Uc', 'Ud']));
      expect(composer.selection.selected, isNot(contains('Ub')));
      expect(forward.state.selectedIds, composer.selection.selected);
      expect(find.byKey(_chip('Ub')), findsNothing);
      expect(find.byKey(_chip('Ud')), findsOneWidget);
    });
  });

  group('composer sheet radius slider', () {
    testWidgets('dragging the slider up widens the radius and the selection', (
      tester,
    ) async {
      await startPost(tester);
      await pumpSheet(tester, size: narrow);
      final before = composer.selection;

      await tester.drag(find.byKey(_radiusSlider), const Offset(2000, 0));
      await tester.pumpAndSettle();

      expect(composer.selection.radius, greaterThan(before.radius));
      expect(
        composer.selection.selected.length,
        greaterThan(before.selected.length),
      );
      expect(composer.selection.selected, containsAll(before.selected));
    });

    testWidgets('dragging the slider down shrinks the radius', (tester) async {
      await startPost(tester);
      await pumpSheet(tester, size: narrow);
      final before = composer.selection;

      await tester.drag(find.byKey(_radiusSlider), const Offset(-2000, 0));
      await tester.pumpAndSettle();

      expect(composer.selection.radius, lessThan(before.radius));
      expect(
        composer.selection.selected.length,
        lessThan(before.selected.length),
      );
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

  group('composer sheet list hand-off', () {
    testWidgets('«Списком» opens the embedded picker on the composer forward '
        'cubit', (tester) async {
      final forward = await startPost(tester);
      await pumpSheet(tester, size: narrow);
      expect(find.byType(ForwardRecipientPicker), findsNothing);

      await tester.tap(find.byKey(_listButton));
      await tester.pumpAndSettle();

      final picker = tester.widget<ForwardRecipientPicker>(
        find.byType(ForwardRecipientPicker),
      );
      expect(picker.embedded, isTrue);
      expect(picker.beaconId, forward.state.beaconId);
      expect(find.text('Person Ua'), findsOneWidget);

      // The sheet supplies the override; a real tap on a row goes through it.
      expect(picker.onToggle, isNotNull);
      await tester.tap(
        find.byKey(TestIds.key(TestIds.forwardRecipientCheckbox('Ud'))),
      );
      await tester.pumpAndSettle();
      expect(composer.selection.manualAdded, {'Ud'});
      expect(forward.state.selectedIds, {'Ua', 'Ub', 'Uc', 'Ud'});
    });

    testWidgets('toggling a person inside the radius in the list removes them '
        'and a later radius change does not bring them back', (tester) async {
      final forward = await startPost(tester);
      await pumpSheet(tester, size: narrow);
      await tester.tap(find.byKey(_listButton));
      await tester.pumpAndSettle();

      // Precondition: Ua is selected only because the circle covers them.
      expect(
        (_positions['Ua']! - composer.selection.center).distance,
        lessThanOrEqualTo(composer.selection.radius),
      );
      expect(composer.selection.selected, contains('Ua'));
      expect(composer.selection.manualAdded, isEmpty);
      expect(composer.selection.manualRemoved, isEmpty);

      await tester.tap(
        find.byKey(TestIds.key(TestIds.forwardRecipientCheckbox('Ua'))),
      );
      await tester.pumpAndSettle();

      expect(composer.selection.manualRemoved, {'Ua'});
      expect(composer.selection.selected, {'Ub', 'Uc'});
      expect(forward.state.selectedIds, {'Ub', 'Uc'});

      final radiusBefore = composer.selection.radius;
      await tester.drag(find.byKey(_radiusSlider), const Offset(2000, 0));
      await tester.pumpAndSettle();

      expect(composer.selection.radius, greaterThan(radiusBefore));
      expect(composer.selection.selected, containsAll(['Ub', 'Uc', 'Ud']));
      expect(composer.selection.selected, isNot(contains('Ua')));
      expect(forward.state.selectedIds, composer.selection.selected);
    });

    testWidgets('toggling a person outside the radius in the list adds them '
        'and a smaller radius keeps them', (tester) async {
      final forward = await startPost(tester);
      await pumpSheet(tester, size: narrow);
      await tester.tap(find.byKey(_listButton));
      await tester.pumpAndSettle();

      await tester.tap(
        find.byKey(TestIds.key(TestIds.forwardRecipientCheckbox('Ue'))),
      );
      await tester.pumpAndSettle();

      expect(composer.selection.manualAdded, {'Ue'});
      expect(forward.state.selectedIds, {'Ua', 'Ub', 'Uc', 'Ue'});

      final radiusBefore = composer.selection.radius;
      await tester.drag(find.byKey(_radiusSlider), const Offset(-2000, 0));
      await tester.pumpAndSettle();

      expect(composer.selection.radius, lessThan(radiusBefore));
      expect(composer.selection.selected, contains('Ue'));
      expect(
        composer.selection.selected,
        isNot(containsAll(['Ua', 'Ub', 'Uc'])),
      );
      expect(forward.state.selectedIds, composer.selection.selected);
    });
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
