import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:tentura/design_system/tentura_design_system.dart';
import 'package:tentura/domain/entity/lazy_write_notice.dart';
import 'package:tentura/domain/entity/profile.dart';
import 'package:tentura/features/constellation/ui/bloc/constellation_cubit.dart';
import 'package:tentura/features/constellation/ui/bloc/constellation_selection_cubit.dart';
import 'package:tentura/features/constellation/ui/scene/constellation_zoom_level_controller.dart';
import 'package:tentura/features/constellation/ui/utils/constellation_presentation_frame.dart';
import 'package:tentura/features/constellation/ui/utils/constellation_tap_resolver.dart';
import 'package:tentura/features/constellation/ui/widget/constellation_body.dart';
import 'package:tentura/features/graph/domain/use_case/graph_trust_write_case.dart';
import 'package:tentura/features/graph/ui/bloc/graph_person_context_cubit.dart';
import 'package:tentura/ui/bloc/screen_cubit.dart';
import 'package:tentura/ui/l10n/l10n.dart';
import 'package:tentura_root/domain/constellation/constellation_anchor.dart';

import '../../ui/effect/fake_ui_effect_port.dart';
import 'fixtures/constellation_reference_fixture.dart';

// A rubber-band box selects people at every zoom level, not only close up
// (#642): at the district level people are initials circles and at the
// overview they are dots, and a box around them still picks them.

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

const _peopleIds = ['am', 'in', 'sm'];

/// Two people pinned close together and one pinned well apart, so a box can
/// surround the pair and leave the third out at every zoom level.
final _pinned = [
  for (final (id, x, y) in [
    ('am', -1.5, 0.6),
    ('in', -0.75, 0.6),
    ('sm', 2.5, 1.0),
  ])
    ConstellationAnchor(
      target: ConstellationAnchorTarget.person(id),
      position: ConstellationAnchorPosition(
        xUnits: x,
        yUnits: y,
        coordinateSpaceVersion: 1,
      ),
      revision: ConstellationAnchorRevision(BigInt.one),
      placedAt: DateTime.utc(2026, 10, 26),
    ),
];

/// How far outside the box a person must lie for leaving them out to be a
/// fair expectation, in screen pixels.
const _clearOfBox = 40.0;

/// Mounts the reference Field zoomed to [scale] and draws a Shift-drag box
/// around the people in [around]; returns the ids of the people that ended up
/// selected. Everyone else is clear of the box.
Future<Set<String>> _boxAround(
  WidgetTester tester, {
  required double scale,
  required ConstellationDetailLevel level,
  required List<String> around,
}) async {
  final cubit = ConstellationCubit(
    case_: constellationCaseForField(
      constellationReferenceField(anchors: _pinned),
    ),
    viewer: kRefEgo,
    semanticZoomEnabled: true,
  );
  await cubit.stream.firstWhere((state) => state.status is StateIsSuccess);
  final selection = ConstellationSelectionCubit();
  final zoom = ConstellationZoomLevelController();
  final holder = ConstellationPresentationFrameHolder();
  addTearDown(() async {
    await cubit.close();
    await selection.close();
    zoom.dispose();
  });
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
            RepositoryProvider<ConstellationZoomLevelController>.value(
              value: zoom,
            ),
            BlocProvider<ConstellationCubit>.value(value: cubit),
            BlocProvider<ConstellationSelectionCubit>.value(value: selection),
            BlocProvider<GraphPersonContextCubit>(
              create: (_) => _StubContextCubit(),
            ),
            BlocProvider<ScreenCubit>(
              create: (_) => ScreenCubit(FakeUiEffectPort()),
            ),
          ],
          child: Scaffold(
            body: ConstellationBody(
              legendExpanded: false,
              onToggleLegend: () {},
              presentationFrameHolder: holder,
            ),
          ),
        ),
      ),
    ),
  );
  await tester.pumpAndSettle();
  cubit.graphController.zoomBy(scale / cubit.graphController.cameraScale);
  await tester.pumpAndSettle();
  expect(holder.frame!.detail, level);

  final controller = cubit.graphController;
  final snapshot = controller.renderSnapshot;
  Offset centreOf(String id) {
    final point = snapshot.resolvePosition('fp:$id')!;
    return controller.sceneToViewportLocal(Offset(point.x, point.y));
  }

  final inside = [for (final id in around) centreOf(id)];
  final box = inside
      .skip(1)
      .fold(
        Rect.fromPoints(inside.first, inside.first),
        (rect, c) => rect.expandToInclude(Rect.fromPoints(c, c)),
      )
      .inflate(70);
  for (final id in _peopleIds.where((id) => !around.contains(id))) {
    expect(
      box.inflate(_clearOfBox).contains(centreOf(id)),
      isFalse,
      reason: '$id is clear of the box, so leaving them out is expected',
    );
  }

  await tester.sendKeyDownEvent(LogicalKeyboardKey.shiftLeft);
  final gesture = await tester.startGesture(
    box.topLeft,
    kind: PointerDeviceKind.mouse,
  );
  await tester.pump();
  for (var i = 1; i <= 8; i++) {
    await gesture.moveTo(Offset.lerp(box.topLeft, box.bottomRight, i / 8)!);
    await tester.pump(const Duration(milliseconds: 16));
  }
  await gesture.up();
  await tester.sendKeyUpEvent(LogicalKeyboardKey.shiftLeft);
  await tester.pumpAndSettle();
  return {
    for (final target in selection.state.targets)
      if (target.kind == ConstellationAnchorTargetKind.person) target.id,
  };
}

void main() {
  for (final (description, scale, level) in [
    ('at full size when zoomed in', 1.0, ConstellationDetailLevel.close),
    (
      'drawn as initials circles at the district level',
      0.6,
      ConstellationDetailLevel.district,
    ),
    ('drawn as dots at the overview', 0.3, ConstellationDetailLevel.overview),
  ]) {
    group('box selection $description', () {
      testWidgets('picks exactly the people it surrounds', (tester) async {
        final picked = await _boxAround(
          tester,
          scale: scale,
          level: level,
          around: ['am', 'in'],
        );

        expect(picked, {'am', 'in'});
      });

      testWidgets('picks everyone when it surrounds everyone', (tester) async {
        final picked = await _boxAround(
          tester,
          scale: scale,
          level: level,
          around: _peopleIds,
        );

        expect(picked, _peopleIds.toSet());
      });
    });
  }
}
