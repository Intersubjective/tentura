import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:tentura/consts.dart';
import 'package:tentura/features/constellation/ui/screen/constellation_screen.dart';
import 'package:tentura/features/constellation/ui/widget/constellation_viewport_overlay.dart';
import 'package:tentura/features/home/ui/bloc/home_tab_reselect_cubit.dart';
import 'package:tentura/design_system/tentura_design_system.dart';
import 'package:tentura/domain/entity/lazy_write_notice.dart';
import 'package:tentura/domain/entity/profile.dart';
import 'package:tentura/features/constellation/ui/bloc/constellation_cubit.dart';
import 'package:tentura/features/constellation/ui/scene/constellation_zoom_level_controller.dart';
import 'package:tentura/features/constellation/ui/utils/constellation_presentation_frame.dart';
import 'package:tentura/features/constellation/ui/utils/constellation_tap_resolver.dart';
import 'package:tentura/features/constellation/ui/widget/constellation_body.dart';
import 'package:tentura/features/graph/domain/use_case/graph_trust_write_case.dart';
import 'package:tentura/features/graph/ui/bloc/graph_person_context_cubit.dart';
import 'package:tentura/ui/bloc/screen_cubit.dart';
import 'package:tentura/ui/l10n/l10n.dart';
import 'package:tentura/ui/test_ids.dart';
import 'package:tentura_root/domain/constellation/constellation_anchor.dart';

import '../../ui/effect/fake_ui_effect_port.dart';
import 'fixtures/constellation_reference_fixture.dart';

class _StubContextCubit extends Cubit<GraphPersonContextState>
    implements GraphPersonContextCubit {
  _StubContextCubit() : super(const GraphPersonContextState());

  @override
  Stream<LazyWriteNotice> get lazyWriteNotices => const Stream.empty();

  @override
  Future<void> retryTrust([GraphTrustRevert? revert]) async {}

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

/// Pumps the body the way the screen does: the screen owns the zoom-level
/// controller and provides it above the body and its viewport overlay.
Future<void> _pump(
  WidgetTester tester,
  ConstellationCubit cubit,
  ConstellationZoomLevelController zoom,
  ConstellationPresentationFrameHolder holder,
) async {
  const size = Size(1200, 900);
  await tester.binding.setSurfaceSize(size);
  addTearDown(() => tester.binding.setSurfaceSize(null));
  final fx = FakeUiEffectPort();
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
              RepositoryProvider<ConstellationZoomLevelController>.value(value: zoom),
              BlocProvider<ConstellationCubit>.value(value: cubit),
              BlocProvider<GraphPersonContextCubit>(
                create: (_) => _StubContextCubit(),
              ),
              BlocProvider<ScreenCubit>(create: (_) => ScreenCubit(fx)),
            ],
            child: ConstellationBody(
              legendExpanded: false,
              onToggleLegend: () {},
              presentationFrameHolder: holder,
            ),
          ),
        ),
      ),
    ),
  );
  await tester.pump();
  await tester.pump(const Duration(milliseconds: 400));
  await tester.pumpAndSettle();
}

void main() {
  gateOffPresentationTests();
  screenOwnershipTests();

  final pinned = [
    ConstellationAnchor(
      target: ConstellationAnchorTarget.beacon('req-in-2'),
      position: const ConstellationAnchorPosition(
        xUnits: -3,
        yUnits: 4,
        coordinateSpaceVersion: 1,
      ),
      revision: ConstellationAnchorRevision(BigInt.one),
      placedAt: DateTime.utc(2026, 9, 9, 12),
    ),
  ];

  Finder pinBadge() => find.descendant(
    of: find
        .ancestor(
          of: find.byKey(TestIds.key(TestIds.graphNode('req-in-2'))),
          matching: find.byWidgetPredicate(
            (w) =>
                w is Stack &&
                w.clipBehavior == Clip.none &&
                w.alignment == Alignment.center,
          ),
        )
        .first,
    matching: find.byKey(TestIds.key(TestIds.constellationPinMarker)),
  );

  group('zoom level shared by the map overlay and body', () {
    testWidgets(
      'overlay and body follow the provided controller, not their own state',
      (
        tester,
      ) async {
        final cubit = await loadReferenceCubit(
          field: constellationReferenceField(anchors: pinned),
        );
        addTearDown(cubit.close);
        final zoom = ConstellationZoomLevelController();
        addTearDown(zoom.dispose);
        final holder = ConstellationPresentationFrameHolder();
        await _pump(tester, cubit, zoom, holder);

        expect(zoom.value, ConstellationDetailLevel.close);
        expect(holder.frame!.detail, ConstellationDetailLevel.close);
        expect(pinBadge(), findsOneWidget);

        // The camera stays put; only the owner changes level.
        zoom.update(0.3, gestureActive: false);
        await tester.pumpAndSettle();
        expect(holder.frame!.detail, ConstellationDetailLevel.overview);
        expect(pinBadge(), findsNothing);

        zoom.update(0.6, gestureActive: false);
        await tester.pumpAndSettle();
        expect(holder.frame!.detail, ConstellationDetailLevel.district);
        expect(pinBadge(), findsNothing);

        zoom.update(1, gestureActive: false);
        await tester.pumpAndSettle();
        expect(holder.frame!.detail, ConstellationDetailLevel.close);
        expect(pinBadge(), findsOneWidget);
      },
    );

    testWidgets('camera zoom feeds the controller and the overlay agrees', (
      tester,
    ) async {
      final cubit = await loadReferenceCubit(
        field: constellationReferenceField(anchors: pinned),
      );
      addTearDown(cubit.close);
      final zoom = ConstellationZoomLevelController();
      addTearDown(zoom.dispose);
      final holder = ConstellationPresentationFrameHolder();
      await _pump(tester, cubit, zoom, holder);

      for (var i = 0; i < 20 && cubit.graphController.cameraScale >= 0.4; i++) {
        cubit.graphController.zoomBy(0.8);
        await tester.pump();
      }
      await tester.pumpAndSettle();
      final scale = cubit.graphController.cameraScale;
      expect(scale, lessThan(0.45));
      expect(zoom.value, ConstellationDetailLevel.overview);
      expect(holder.frame!.detail, zoom.value);
      expect(pinBadge(), findsNothing);

      for (var i = 0; i < 40 && cubit.graphController.cameraScale < 0.9; i++) {
        cubit.graphController.zoomBy(1.1);
        await tester.pump();
      }
      await tester.pumpAndSettle();
      expect(cubit.graphController.cameraScale, greaterThanOrEqualTo(0.85));
      expect(zoom.value, ConstellationDetailLevel.close);
      expect(holder.frame!.detail, ConstellationDetailLevel.close);
      expect(pinBadge(), findsOneWidget);
    });
  });
}

// With `kFieldSemanticZoomEnabled` off the map keeps the presentation it had
// before semantic zoom: every label and the pin badge up close, a reduced
// label set mid-way, and no label or chip at all when far out.
void gateOffPresentationTests() {
  final pinned = [
    ConstellationAnchor(
      target: ConstellationAnchorTarget.beacon('req-in-2'),
      position: const ConstellationAnchorPosition(
        xUnits: -3,
        yUnits: 4,
        coordinateSpaceVersion: 1,
      ),
      revision: ConstellationAnchorRevision(BigInt.one),
      placedAt: DateTime.utc(2026, 9, 9, 12),
    ),
  ];

  Finder pinBadge() => find.descendant(
    of: find
        .ancestor(
          of: find.byKey(TestIds.key(TestIds.graphNode('req-in-2'))),
          matching: find.byWidgetPredicate(
            (w) =>
                w is Stack &&
                w.clipBehavior == Clip.none &&
                w.alignment == Alignment.center,
          ),
        )
        .first,
    matching: find.byKey(TestIds.key(TestIds.constellationPinMarker)),
  );

  Future<void> zoomTo(
    WidgetTester tester,
    ConstellationCubit cubit,
    bool Function(double) done,
    double factor,
  ) async {
    for (var i = 0; i < 40 && !done(cubit.graphController.cameraScale); i++) {
      cubit.graphController.zoomBy(factor);
      await tester.pump();
    }
    await tester.pumpAndSettle();
    expect(done(cubit.graphController.cameraScale), isTrue);
  }

  group('map presentation with semantic zoom off', () {
    testWidgets('keeps today\'s pin, label and chip behaviour per scale', (
      tester,
    ) async {
      expect(kFieldSemanticZoomEnabled, isFalse);
      final cubit = await loadReferenceCubit(
        field: constellationReferenceField(anchors: pinned),
      );
      addTearDown(cubit.close);
      final zoom = ConstellationZoomLevelController();
      addTearDown(zoom.dispose);
      final holder = ConstellationPresentationFrameHolder();
      await _pump(tester, cubit, zoom, holder);

      final closeLabels = holder.frame!.labels.length;
      expect(closeLabels, greaterThan(0));
      expect(pinBadge(), findsOneWidget);

      // Between the old overview and normal thresholds, coming from close.
      await zoomTo(tester, cubit, (s) => s < 0.6, 0.9);
      expect(pinBadge(), findsNothing);
      expect(holder.frame!.labels.length, lessThanOrEqualTo(closeLabels));
      expect(holder.frame!.labels, isNotEmpty);

      // Past the old 0.3 cut-off: a clean map with no label and no chip.
      await zoomTo(tester, cubit, (s) => s < 0.3, 0.9);
      expect(holder.frame!.labels, isEmpty);
      expect(holder.frame!.chips, isEmpty);
      expect(pinBadge(), findsNothing);

      // The overview (below 0.45) draws dots only (#595).
      await zoomTo(tester, cubit, (s) => s >= 0.35 && s < 0.45, 1.05);
      expect(holder.frame!.labels, isEmpty);

      // From the district scale up the labels are back.
      await zoomTo(tester, cubit, (s) => s >= 0.45 && s < 0.6, 1.05);
      expect(holder.frame!.labels, isNotEmpty);

      await zoomTo(tester, cubit, (s) => s >= 0.9, 1.1);
      expect(holder.frame!.labels.length, closeLabels);
      expect(pinBadge(), findsOneWidget);
    });
  });
}

// The real screen owns the one controller its body and overlay read.
void screenOwnershipTests() {
  group('zoom level owned by the screen', () {
    testWidgets('body and overlay read the same controller the screen made', (
      tester,
    ) async {
      final cubit = await loadReferenceCubit();
      addTearDown(cubit.close);
      await tester.binding.setSurfaceSize(const Size(1200, 900));
      addTearDown(() => tester.binding.setSurfaceSize(null));
      await tester.pumpWidget(
        MaterialApp(
          locale: const Locale('en'),
          theme: TenturaTheme.light(),
          localizationsDelegates: L10n.localizationsDelegates,
          supportedLocales: L10n.supportedLocales,
          home: TenturaResponsiveScope(
            child: MultiBlocProvider(
              providers: [
                BlocProvider<ConstellationCubit>.value(value: cubit),
                BlocProvider<HomeTabReselectCubit>(
                  create: (_) => HomeTabReselectCubit(),
                ),
                BlocProvider<GraphPersonContextCubit>(
                  create: (_) => _StubContextCubit(),
                ),
                BlocProvider<ScreenCubit>(
                  create: (_) => ScreenCubit(FakeUiEffectPort()),
                ),
              ],
              child: const ConstellationScreen(),
            ),
          ),
        ),
      );
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 400));

      final fromBody = tester
          .element(find.byType(ConstellationBody))
          .read<ConstellationZoomLevelController>();
      final fromOverlay = tester
          .element(find.byType(ConstellationViewportOverlay))
          .read<ConstellationZoomLevelController>();
      expect(identical(fromBody, fromOverlay), isTrue);

      for (var i = 0; i < 20 && cubit.graphController.cameraScale >= 0.4; i++) {
        cubit.graphController.zoomBy(0.8);
        await tester.pump();
      }
      await tester.pumpAndSettle();
      expect(fromBody.value, ConstellationDetailLevel.overview);
    });
  });
}
