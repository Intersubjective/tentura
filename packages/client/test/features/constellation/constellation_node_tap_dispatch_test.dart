import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:tentura/design_system/tentura_design_system.dart';
import 'package:tentura/domain/entity/profile.dart';
import 'package:tentura_root/domain/constellation/constellation_anchor.dart';
import 'package:tentura/features/constellation/domain/entity/constellation_anchor_projection.dart';
import 'package:tentura/features/constellation/domain/entity/constellation_field.dart';
import 'package:tentura/features/constellation/ui/bloc/constellation_cubit.dart';
import 'package:tentura/features/constellation/ui/bloc/constellation_state.dart';
import 'package:tentura/features/constellation/ui/widget/constellation_body.dart';
import 'package:tentura/features/graph/ui/bloc/graph_person_context_cubit.dart';
import 'package:tentura/ui/bloc/screen_cubit.dart';
import 'package:tentura/ui/l10n/l10n.dart';
import 'package:tentura/ui/test_ids.dart';

import '../../ui/effect/fake_ui_effect_port.dart';
import 'fixtures/constellation_reference_fixture.dart';

final class _CountingContextCubit extends Cubit<GraphPersonContextState>
    implements GraphPersonContextCubit {
  _CountingContextCubit() : super(const GraphPersonContextState());

  int selectProfileCalls = 0;

  @override
  final void Function(Profile profile)? onProfilePatched = null;

  @override
  void selectProfile(Profile profile, {required bool intentional}) {
    selectProfileCalls++;
    emit(state.copyWith(selectedProfile: profile));
  }

  @override
  void dismiss() {}

  @override
  Future<void> trustSelected() async {}

  @override
  void clearSelection() {
    emit(const GraphPersonContextState());
  }
}

Future<void> _pumpWithContext(
  WidgetTester tester,
  ConstellationCubit cubit,
  GraphPersonContextCubit contextCubit, {
  Locale locale = const Locale('en'),
}) async {
  const size = Size(375, 547);
  await tester.binding.setSurfaceSize(size);
  addTearDown(() => tester.binding.setSurfaceSize(null));
  await tester.pumpWidget(
    MaterialApp(
      locale: locale,
      theme: TenturaTheme.light(),
      localizationsDelegates: L10n.localizationsDelegates,
      supportedLocales: L10n.supportedLocales,
      home: Directionality(
        textDirection: TextDirection.ltr,
        child: MediaQuery(
          data: MediaQueryData(size: size),
          child: TenturaResponsiveScope(
            child: MultiBlocProvider(
              providers: [
                BlocProvider<ConstellationCubit>.value(value: cubit),
                BlocProvider<GraphPersonContextCubit>.value(
                  value: contextCubit,
                ),
                BlocProvider<ScreenCubit>(
                  create: (_) => ScreenCubit(FakeUiEffectPort()),
                ),
              ],
              child: ConstellationBody(
                legendExpanded: false,
                onToggleLegend: () {},
              ),
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
  group('Constellation node tap dispatch (R06)', () {
    testWidgets('single pointer dispatch calls selectProfile once', (
      tester,
    ) async {
      final cubit = await loadReferenceCubit();
      addTearDown(cubit.close);
      final contextCubit = _CountingContextCubit();
      addTearDown(contextCubit.close);

      await _pumpWithContext(tester, cubit, contextCubit);

      await tester.tap(find.byKey(TestIds.key(TestIds.graphNode('am'))));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 100));
      expect(contextCubit.selectProfileCalls, 1);
      expect(cubit.state.selectedPersonId, 'am');
    });

    testWidgets('request node tap opens preview sheet', (tester) async {
      final cubit = await loadReferenceCubit();
      addTearDown(cubit.close);

      await pumpConstellationBody(tester, cubit, locale: const Locale('en'));

      await tester.tap(find.byKey(TestIds.key(TestIds.graphNode('req-ego-1'))));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 300));

      expect(cubit.state.selectedRequestId, 'req-ego-1');
      expect(
        find.byKey(const Key('constellation.request_preview')),
        findsOneWidget,
      );
    });

    testWidgets('pan starting on label moves camera not placement', (
      tester,
    ) async {
      final cubit = await loadReferenceCubit();
      addTearDown(cubit.close);

      await pumpConstellationBody(tester, cubit, locale: const Locale('en'));
      final label = find.byKey(
        const ValueKey('constellation.label.fr:req-ego-1'),
      );
      final rect = tester.getRect(label);
      final revisionBefore = cubit.graphController.cameraRevision.value;

      final gesture = await tester.createGesture(kind: PointerDeviceKind.mouse);
      await gesture.down(rect.center);
      await tester.pump();
      await gesture.moveBy(const Offset(60, 0));
      await tester.pump();
      await gesture.up();
      await tester.pump();

      expect(
        cubit.state.placementPhase,
        ConstellationPlacementPhase.idle,
      );
      expect(
        cubit.graphController.cameraRevision.value,
        greaterThan(revisionBefore),
      );
    });

    test('later placedAt anchor sorts above earlier at same position (D22)', () {
      const shared = ConstellationAnchorPosition(
        xUnits: 4,
        yUnits: -2,
        coordinateSpaceVersion: 1,
      );
      final earlier = ConstellationAnchor(
        target: ConstellationAnchorTarget.beacon('req-in-1'),
        position: shared,
        revision: ConstellationAnchorRevision(BigInt.one),
        placedAt: DateTime.utc(2026, 1, 1),
      );
      final later = ConstellationAnchor(
        target: ConstellationAnchorTarget.beacon('req-in-2'),
        position: shared,
        revision: ConstellationAnchorRevision(BigInt.one),
        placedAt: DateTime.utc(2026, 6, 1),
      );
      expect(ConstellationAnchor.comparePaintOrder(earlier, later), lessThan(0));
    });

    testWidgets('combined semantics: one node label with status', (tester) async {
      final cubit = await loadReferenceCubit();
      addTearDown(cubit.close);

      await pumpConstellationBody(
        tester,
        cubit,
        locale: const Locale('en'),
      );

      final nodeFinder = find.byKey(TestIds.key(TestIds.graphNode('req-sm-1')));
      final semantics = tester.getSemantics(nodeFinder);
      expect(semantics.label, contains('I need documents'));
      expect(semantics.label, contains('Open'));
      expect(
        find.bySemanticsLabel(RegExp(r'I need documents')),
        findsOneWidget,
      );
    });

    testWidgets('placement drag gates camera until cancel', (tester) async {
      final cubit = await loadReferenceCubit(
        field: constellationReferenceField(
          anchors: _pinnedReferenceAnchors(),
        ),
      );
      addTearDown(cubit.close);

      await pumpConstellationBody(tester, cubit);

      cubit.beginDragExisting(
        target: ConstellationAnchorTarget.person('am'),
      );
      expect(
        cubit.state.placementPhase,
        ConstellationPlacementPhase.draggingExisting,
      );
      expect(cubit.graphController.isCameraGated, isTrue);

      cubit.cancelPlacement();
      expect(cubit.graphController.isCameraGated, isFalse);
      expect(
        cubit.state.placementPhase,
        ConstellationPlacementPhase.idle,
      );
    });
  });
}

List<ConstellationAnchor> _pinnedReferenceAnchors() {
  final loadedAt = DateTime.utc(2026, 9, 9, 12);
  final revision = ConstellationAnchorRevision(BigInt.one);
  return [
    ConstellationAnchor(
      target: ConstellationAnchorTarget.person('am'),
      position: const ConstellationAnchorPosition(
        xUnits: 4,
        yUnits: -2,
        coordinateSpaceVersion: 1,
      ),
      revision: revision,
      placedAt: loadedAt,
    ),
  ];
}
