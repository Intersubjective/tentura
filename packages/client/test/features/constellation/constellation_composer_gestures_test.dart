import 'dart:math' as math;

// Canvas entry gestures and the radius handle of the graph composer: a
// secondary tap or long press on empty canvas offers the kind menu and starts
// the composer there; dragging the radius handle resizes the circle live;
// panning the canvas leaves the radius alone.

import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:logging/logging.dart';
import 'package:force_directed_graphview/force_directed_graphview.dart';

import 'package:tentura/consts.dart';
import 'package:tentura/design_system/tentura_design_system.dart';
import 'package:tentura/domain/entity/profile.dart';
import 'package:tentura/env.dart';
import 'package:tentura/features/beacon_create/ui/bloc/beacon_create_cubit.dart';
import 'package:tentura/features/constellation/domain/entity/constellation_anchor_projection.dart';
import 'package:tentura/features/constellation/domain/entity/constellation_field.dart';
import 'package:tentura/features/constellation/domain/port/constellation_repository_port.dart';
import 'package:tentura/features/constellation/domain/use_case/constellation_field_case.dart';
import 'package:tentura/features/constellation/ui/bloc/constellation_composer_cubit.dart';
import 'package:tentura/features/constellation/ui/bloc/constellation_cubit.dart';
import 'package:tentura/features/constellation/ui/widget/constellation_app_bar.dart';
import 'package:tentura/features/constellation/ui/widget/constellation_body.dart';
import 'package:tentura/features/forward/ui/bloc/forward_cubit.dart';
import 'package:tentura/features/graph/domain/entity/edge_details.dart';
import 'package:tentura/features/graph/domain/entity/node_details.dart';
import 'package:tentura/features/graph/ui/bloc/graph_person_context_cubit.dart';
import 'package:tentura/ui/bloc/screen_cubit.dart';
import 'package:tentura/ui/l10n/l10n.dart';

import '../../ui/effect/fake_ui_effect_port.dart';
import '../beacon_create/fake_beacon_ports.dart';

const _ego = Profile(id: 'ego', displayName: 'Ego');

const _kindMenuRequest = Key('constellation.canvas.create_menu.request');
const _kindMenuPost = Key('constellation.canvas.create_menu.post');
const _createHereButton = Key('constellation.app_bar.create_here');

final class _StubRepository implements ConstellationRepositoryPort {
  _StubRepository(this.field);

  final ConstellationField field;

  @override
  Future<ConstellationField> fetch({
    ConstellationFieldMembershipFilters membershipFilters =
        ConstellationFieldMembershipFilters.defaults,
    ConstellationProjection projection = ConstellationProjection.full,
  }) async => field;
}

final class _StubContextCubit extends Cubit<GraphPersonContextState>
    implements GraphPersonContextCubit {
  _StubContextCubit() : super(const GraphPersonContextState());

  @override
  final void Function(Profile profile)? onProfilePatched = null;

  @override
  void selectProfile(Profile profile, {required bool intentional}) {}

  @override
  void dismiss() {}

  @override
  Future<void> trustSelected() async {}

  @override
  Future<void> untrustSelected() async {}

  @override
  void clearSelection() {}
}

const _peerIds = ['a', 'b', 'c', 'd', 'e', 'f'];

ConstellationField _field() => ConstellationField(
  loadedAt: DateTime.utc(2026, 10, 3),
  context: '',
  peers: [for (final id in _peerIds) ConstellationPerson(id: id)],
  edges: [
    for (final id in _peerIds)
      ConstellationTrustEdgeEntity(src: 'ego', dst: id, tier: 1),
  ],
  requests: const [],
);

void main() {
  late ConstellationCubit cubit;
  late ConstellationComposerCubit composer;
  late FakeUiEffectPort effects;
  late List<ForwardCubit> forwards;

  ConstellationComposerCubit makeComposer(Map<String, Offset> positions) =>
      ConstellationComposerCubit(
        positions: positions,
        eligible: _peerIds.toSet(),
        createCubitFactory: (kind) => BeaconCreateCubit(
          kind: kind,
          beaconCreateCase: fakeBeaconCreateCase(write: FakeBeaconWritePort()),
          effects: effects,
        ),
        forwardCubitFactory: (id) {
          final f = ForwardCubit(
            beaconId: id,
            embedded: true,
            effects: effects,
            debugSkipInitialLoad: true,
          );
          forwards.add(f);
          return f;
        },
      );

  Future<void> pumpTree(WidgetTester tester) async {
    const size = Size(1200, 900);
    await tester.pumpWidget(
      MaterialApp(
        locale: const Locale('en'),
        theme: TenturaTheme.light(),
        localizationsDelegates: L10n.localizationsDelegates,
        supportedLocales: L10n.supportedLocales,
        home: MediaQuery(
          data: const MediaQueryData(size: size),
          child: TenturaResponsiveScope(
            child: MultiBlocProvider(
              providers: [
                BlocProvider<ConstellationCubit>.value(value: cubit),
                BlocProvider<GraphPersonContextCubit>(
                  create: (_) => _StubContextCubit(),
                ),
                BlocProvider<ScreenCubit>(create: (_) => ScreenCubit(effects)),
                BlocProvider<ConstellationComposerCubit>.value(
                  value: composer,
                ),
              ],
              child: Column(
                children: [
                  const ConstellationAppBarRow(
                    legendExpanded: false,
                    onToggleLegend: _noop,
                  ),
                  Expanded(
                    child: ConstellationBody(
                      legendExpanded: false,
                      onToggleLegend: _noop,
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 400));
  }

  /// Settles the layout first, then swaps in a composer whose people sit at
  /// fixed scene distances from the empty-canvas entry point, so selection
  /// counts do not depend on the layout algorithm.
  Future<void> pump(WidgetTester tester) async {
    const size = Size(1200, 900);
    await tester.binding.setSurfaceSize(size);
    addTearDown(() => tester.binding.setSurfaceSize(null));
    await tester.runAsync(() async {
      cubit = ConstellationCubit(
        case_: ConstellationFieldCase(
          _StubRepository(_field()),
          env: const Env.fromEnvironment(),
          logger: Logger('ConstellationComposerGesturesTest'),
        ),
        viewer: _ego,
      );
      await cubit.stream.firstWhere((s) => s.status is StateIsSuccess);
    });
    effects = FakeUiEffectPort();
    forwards = [];
    composer = makeComposer(const {});
    await pumpTree(tester);
    await tester.pumpAndSettle(const Duration(milliseconds: 100));
    final entry = cubit.graphController.viewportLocalToScene(
      tester.getSize(find.byType(GraphView<NodeDetails, EdgeDetails>)).bottomRight(Offset.zero) - const Offset(40, 40),
    );
    const distances = <double>[40, 80, 120, 300, 600, 1000];
    composer = makeComposer({
      for (var i = 0; i < _peerIds.length; i++)
        _peerIds[i]: entry + Offset(distances[i], 0),
    });
    await pumpTree(tester);
    await tester.pump(const Duration(milliseconds: 400));
  }

  tearDown(() async {
    for (final f in forwards) {
      await f.close();
    }
  });

  Rect canvas(WidgetTester tester) => tester.getRect(find.byType(GraphView<NodeDetails, EdgeDetails>));

  /// Empty canvas spot near the bottom-right corner, in viewport-local space.
  Offset emptyLocal(WidgetTester tester) =>
      canvas(tester).size.bottomRight(Offset.zero) - const Offset(40, 40);

  Offset globalOf(WidgetTester tester, Offset scene) =>
      canvas(tester).topLeft + cubit.graphController.sceneToViewportLocal(scene);

  Future<void> secondaryTapAt(WidgetTester tester, Offset global) async {
    final g = await tester.createGesture(
      kind: PointerDeviceKind.mouse,
      buttons: kSecondaryMouseButton,
    );
    await g.down(global);
    await g.up();
    await tester.pump();
  }

  Future<void> startViaSecondaryTap(WidgetTester tester) async {
    await secondaryTapAt(tester, canvas(tester).topLeft + emptyLocal(tester));
    await tester.tap(find.byKey(_kindMenuRequest));
    await tester.pump();
  }

  group('canvas entry gestures', () {
    testWidgets('secondary tap on empty canvas opens the kind menu and starts '
        'the composer at that point', (tester) async {
      await pump(tester);
      final local = emptyLocal(tester);
      final scene = cubit.graphController.viewportLocalToScene(local);

      await secondaryTapAt(tester, canvas(tester).topLeft + local);
      expect(find.byKey(_kindMenuRequest), findsOneWidget);
      expect(composer.createCubit, isNull, reason: 'nothing starts before a choice');

      await tester.tap(find.byKey(_kindMenuRequest));
      await tester.pump();

      expect(composer.createCubit, isNotNull);
      expect(composer.kind.name, 'request');
      expect((composer.selection.center - scene).distance, lessThan(1));
    });

    testWidgets('long press on empty canvas opens the kind menu and starts the '
        'composer at that point', (tester) async {
      await pump(tester);
      final local = emptyLocal(tester);
      final scene = cubit.graphController.viewportLocalToScene(local);

      final g = await tester.createGesture();
      await g.down(canvas(tester).topLeft + local);
      await tester.pump(kLongPressTimeout + const Duration(milliseconds: 1));
      await g.up();
      await tester.pump();
      expect(find.byKey(_kindMenuRequest), findsOneWidget);
      expect(composer.createCubit, isNull, reason: 'nothing starts before a choice');

      await tester.tap(find.byKey(_kindMenuRequest));
      await tester.pump();

      expect(composer.createCubit, isNotNull);
      expect((composer.selection.center - scene).distance, lessThan(1));
    });

    testWidgets('the app bar create-here button offers the kind menu and '
        'starts the composer at the viewport centre', (tester) async {
      await pump(tester);
      final centre = cubit.graphController.viewportLocalToScene(
        canvas(tester).size.center(Offset.zero),
      );

      await tester.tap(find.byKey(_createHereButton));
      await tester.pump();
      expect(find.byKey(_kindMenuRequest), findsOneWidget);
      expect(composer.createCubit, isNull);

      await tester.tap(find.byKey(_kindMenuRequest));
      await tester.pump();

      expect(composer.createCubit, isNotNull);
      expect(composer.kind.name, 'request');
      expect((composer.selection.center - centre).distance, lessThan(2));
    });

    group('the kind menu offers both choices now posts are enabled', () {
      testWidgets('opened by secondary tap', (tester) async {
        expect(kPostsEnabled, isTrue, reason: 'this guards the enabled state');
        await pump(tester);

        await secondaryTapAt(
          tester,
          canvas(tester).topLeft + emptyLocal(tester),
        );

        expect(find.byKey(_kindMenuRequest), findsOneWidget);
        expect(find.byKey(_kindMenuPost), findsOneWidget);
      });

      testWidgets('opened by long press', (tester) async {
        await pump(tester);

        final g = await tester.createGesture();
        await g.down(canvas(tester).topLeft + emptyLocal(tester));
        await tester.pump(kLongPressTimeout + const Duration(milliseconds: 1));
        await g.up();
        await tester.pump();

        expect(find.byKey(_kindMenuRequest), findsOneWidget);
        expect(find.byKey(_kindMenuPost), findsOneWidget);
      });

      testWidgets('opened by the app bar button', (tester) async {
        await pump(tester);

        await tester.tap(find.byKey(_createHereButton));
        await tester.pump();

        expect(find.byKey(_kindMenuRequest), findsOneWidget);
        expect(find.byKey(_kindMenuPost), findsOneWidget);
      });
    });
  });

  group('radius handle', () {
    // The handle sits somewhere on the rim; probe the rim instead of assuming
    // an angle. A press that grows the radius when dragged outward is on it.
    Offset rimDirection(int step) => Offset.fromDirection(step * math.pi / 6);

    Future<Offset?> findHandleDirection(WidgetTester tester) async {
      final start = composer.selection;
      for (var step = 0; step < 12; step++) {
        final dir = rimDirection(step);
        final down = globalOf(tester, start.center + dir * start.radius);
        if (!canvas(tester).deflate(8).contains(down)) continue;
        final g = await tester.startGesture(down);
        await g.moveTo(down + dir * 120);
        await tester.pump();
        final grew = composer.selection.radius > start.radius;
        await g.up();
        await tester.pump();
        composer.setRadius(start.radius);
        if (grew) return dir;
      }
      return null;
    }

    testWidgets('dragging the handle outward grows the radius and selects '
        'more people live, while the pointer is still down', (tester) async {
      await pump(tester);
      await startViaSecondaryTap(tester);
      final before = composer.selection;
      final dir = await findHandleDirection(tester);
      expect(dir, isNotNull, reason: 'a handle must exist on the circle rim');
      final down = globalOf(tester, before.center + dir! * before.radius);

      final g = await tester.startGesture(down);
      await g.moveTo(down + dir * 60);
      await tester.pump();
      final mid = composer.selection.radius;
      expect(mid, greaterThan(before.radius), reason: 'live, before release');

      await g.moveTo(down + dir * 2500);
      await tester.pump();
      expect(composer.selection.radius, greaterThan(mid));
      expect(
        composer.selection.selected.length,
        greaterThan(before.selected.length),
        reason: 'people are selected live, before release',
      );
      await g.up();
      await tester.pump();

      expect(composer.selection.center, before.center);
    });

    testWidgets('a drag starting well outside the handle does not resize the '
        'circle', (tester) async {
      await pump(tester);
      await startViaSecondaryTap(tester);
      final before = composer.selection;
      final dir = await findHandleDirection(tester);
      expect(dir, isNotNull, reason: 'a handle must exist on the circle rim');
      final handle = globalOf(tester, before.center + dir! * before.radius);
      final miss = handle + dir * 150;
      expect(canvas(tester).contains(miss), isTrue);

      final g = await tester.startGesture(miss);
      await g.moveTo(miss + dir * 300);
      await tester.pump();
      await g.up();
      await tester.pump();

      expect(composer.selection.radius, before.radius);
      expect(composer.selection.selected, before.selected);
    });

    testWidgets('panning the canvas does not change the radius', (
      tester,
    ) async {
      await pump(tester);
      await startViaSecondaryTap(tester);
      final before = composer.selection;
      final from = canvas(tester).center + const Offset(200, 200);
      final probe = cubit.graphController.sceneToViewportLocal(before.center);

      final g = await tester.startGesture(from);
      await g.moveBy(const Offset(-80, -60));
      await g.moveBy(const Offset(-80, -60));
      await g.up();
      await tester.pump();

      expect(
        cubit.graphController.sceneToViewportLocal(before.center),
        isNot(probe),
        reason: 'the gesture must really have panned the camera',
      );
      expect(composer.selection.radius, before.radius);
      expect(composer.selection.center, before.center);
    });
  });
}

void _noop() {}
