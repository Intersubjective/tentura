import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:force_directed_graphview/src/widget/graph_layout_view.dart';
import 'package:tentura/design_system/tentura_design_system.dart';
import 'package:tentura/domain/entity/profile.dart';
import 'package:tentura_root/domain/constellation/constellation_anchor.dart';
import 'package:tentura/features/constellation/domain/entity/constellation_anchor_projection.dart';
import 'package:tentura/features/constellation/domain/entity/constellation_field.dart';
import 'package:tentura/features/constellation/ui/bloc/constellation_cubit.dart';
import 'package:tentura/features/constellation/ui/widget/constellation_body.dart';
import 'package:tentura/features/graph/ui/bloc/graph_person_context_cubit.dart';
import 'package:tentura/features/constellation/ui/utils/constellation_graph_scene.dart';
import 'package:tentura/features/home/ui/widget/home_bottom_navigation_bar.dart';
import 'package:tentura/ui/bloc/screen_cubit.dart';
import 'package:tentura/ui/l10n/l10n.dart';
import 'package:tentura/ui/test_ids.dart';

import '../../ui/effect/fake_ui_effect_port.dart';
import 'fixtures/constellation_reference_fixture.dart';

class _ContextCubit extends Cubit<GraphPersonContextState>
    implements GraphPersonContextCubit {
  _ContextCubit() : super(const GraphPersonContextState());

  @override
  final void Function(Profile profile)? onProfilePatched = null;
  @override
  void selectProfile(Profile profile, {required bool intentional}) {}
  @override
  void dismiss() {}
  @override
  void clearSelection() {}
  @override
  Future<void> trustSelected() async {}
}

void main() {
  for (final height in [950.0, 1300.0]) {
    testWidgets('overlapping pins are tappable above shell chrome at $height', (
      tester,
    ) async {
      final placedAt = DateTime.utc(2026, 9, 15);
      final person = ConstellationAnchorTarget.person('peer');
      final request = ConstellationAnchorTarget.beacon('request');
      final cubit = await loadReferenceCubit(
        field: ConstellationField(
          loadedAt: placedAt,
          context: '',
          peers: const [ConstellationPerson(id: 'peer', displayName: 'Peer')],
          requests: const [
            ConstellationRequest(
              id: 'request',
              authorId: 'peer',
              title: 'Overlapping pin',
              status: 0,
            ),
          ],
          anchorProjection: ConstellationAnchorProjection(
            revision: ConstellationAnchorRevision(BigInt.two),
            anchors: [
              for (final target in [person, request])
                ConstellationAnchor(
                  target: target,
                  position: const ConstellationAnchorPosition(
                    xUnits: 2.5,
                    yUnits: 2.5,
                    coordinateSpaceVersion: 1,
                  ),
                  revision: ConstellationAnchorRevision(BigInt.two),
                  placedAt: target == request
                      ? placedAt.add(const Duration(seconds: 1))
                      : placedAt,
                ),
            ],
            pinnedPeers: const [],
            pinnedRequests: const [],
            supportPeers: const [],
            supportEdges: const [],
            serverFilteredBeaconIds: const [],
            serverFilteredBeaconCount: 0,
          ),
        ),
      );
      addTearDown(cubit.close);
      await tester.binding.setSurfaceSize(Size(390, height));
      addTearDown(() => tester.binding.setSurfaceSize(null));
      var navTaps = 0;
      await tester.pumpWidget(
        MaterialApp(
          theme: TenturaTheme.light(),
          locale: const Locale('en'),
          localizationsDelegates: L10n.localizationsDelegates,
          supportedLocales: L10n.supportedLocales,
          home: TenturaResponsiveScope(
            child: MultiBlocProvider(
              providers: [
                BlocProvider<ConstellationCubit>.value(value: cubit),
                BlocProvider<GraphPersonContextCubit>(
                  create: (_) => _ContextCubit(),
                ),
                BlocProvider<ScreenCubit>(
                  create: (_) => ScreenCubit(FakeUiEffectPort()),
                ),
              ],
              child: Scaffold(
                bottomNavigationBar: HomeBottomNavigationBar(
                  selectedIndex: 0,
                  onDestinationSelected: (_) => navTaps++,
                  destinations: const [
                    HomeNavDestination(
                      icon: Icon(Icons.home),
                      selectedIcon: Icon(Icons.home),
                      label: 'Home',
                    ),
                    HomeNavDestination(
                      icon: Icon(Icons.people),
                      selectedIcon: Icon(Icons.people),
                      label: 'People',
                    ),
                  ],
                ),
                body: Scaffold(
                  appBar: AppBar(title: const Text('Constellation')),
                  body: ConstellationBody(
                    legendExpanded: false,
                    onToggleLegend: () {},
                  ),
                ),
              ),
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();
      final controller = cubit.graphController;
      final viewerFinder = find.byType(InteractiveViewer);
      final viewport = tester.getRect(viewerFinder);
      final nav = tester.getRect(find.byType(HomeBottomNavigationBar));
      expect(viewport.bottom, nav.top);
      expect(controller.viewportSize, viewport.size);
      expect(controller.viewportSize!.height, lessThan(height));
      const scene = Offset(2473, 2473);
      final graphId = constellationGraphNodeIdForTarget(request);
      final pin = controller.renderSnapshot.resolvePosition(graphId)!;
      expect(Offset(pin.x, pin.y), scene);
      final peer = controller.renderSnapshot.resolvePosition(
        constellationGraphNodeIdForTarget(person),
      )!;
      expect(Offset(peer.x, peer.y), scene);

      // Pan horizontally only so the fixed pin is within the compact width.
      // At 1x it remains 425 pixels below the initially centered ego.
      controller.jumpToPosition(const Offset(2473, 2048));
      await tester.pumpAndSettle();
      Offset globalPin() => tester
          .renderObject<RenderBox>(
            find.byType(GraphLayoutView),
          )
          .localToGlobal(scene);
      expect(
        globalPin(),
        viewport.topLeft + controller.sceneToViewportLocal(scene),
      );
      if (height == 950) {
        // A correct transform can project an offscreen scene point into chrome.
        expect(nav.contains(globalPin()), isTrue);
        expect(viewport.contains(globalPin()), isFalse);
        await tester.tapAt(globalPin());
        await tester.pumpAndSettle();
        expect(navTaps, 1);
        expect(cubit.state.selectedRequestId, isNull);
      } else {
        expect(viewport.contains(globalPin()), isTrue);
      }

      // Use the same explicit camera recovery as a user: no auto-fit on reload.
      await tester.tap(find.byKey(TestIds.key(TestIds.constellationFitAll)));
      await tester.pumpAndSettle();
      expect(viewport.contains(globalPin()), isTrue);
      expect(nav.contains(globalPin()), isFalse);
      expect(controller.viewportSize!.width, closeTo(viewport.width, 0.001));
      expect(controller.viewportSize!.height, closeTo(viewport.height, 0.001));
      final afterFit = controller.renderSnapshot.resolvePosition(graphId)!;
      expect(Offset(afterFit.x, afterFit.y), scene);
      final navTapsBefore = navTaps;
      await tester.tapAt(globalPin());
      await tester.pumpAndSettle();
      expect(cubit.state.selectedRequestId, 'request');
      expect(cubit.state.selectedPersonId, isNull);
      expect(navTaps, navTapsBefore);

      // The actual lower edge also stays hittable; external chrome wins only
      // outside the graph viewport, never over a pin inside its boundary.
      await tester.tapAt(viewport.topLeft + const Offset(8, 8));
      await tester.pumpAndSettle();
      expect(cubit.state.selectedRequestId, isNull);
      controller.jumpToPosition(scene, resetScale: true);
      await tester.pumpAndSettle();
      controller.jumpToPosition(
        Offset(scene.dx, scene.dy - viewport.height / 2 + 32),
      );
      await tester.pumpAndSettle();
      expect(globalPin().dy, closeTo(viewport.bottom - 32, 0.001));
      await tester.tapAt(globalPin());
      await tester.pumpAndSettle();
      expect(cubit.state.selectedRequestId, 'request');
      expect(navTaps, navTapsBefore);
      expect(tester.takeException(), isNull);
    });
  }
}
