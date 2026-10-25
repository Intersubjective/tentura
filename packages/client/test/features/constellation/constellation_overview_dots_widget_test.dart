import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:get_it/get_it.dart';
import 'package:tentura/design_system/tentura_design_system.dart';
import 'package:tentura/domain/entity/lazy_write_notice.dart';
import 'package:tentura/domain/entity/profile.dart';
import 'package:tentura/features/constellation/ui/bloc/constellation_cubit.dart';
import 'package:tentura/features/constellation/ui/bloc/constellation_tag_lens_cubit.dart';
import 'package:tentura/features/constellation/ui/scene/constellation_zoom_level_controller.dart';
import 'package:tentura/features/constellation/domain/entity/constellation_anchor_projection.dart';
import 'package:tentura/features/constellation/domain/entity/constellation_field.dart';
import 'package:tentura_root/domain/constellation/constellation_anchor.dart';
import 'package:tentura/features/constellation/ui/utils/constellation_presentation_frame.dart';
import 'package:tentura/features/constellation/ui/utils/constellation_tap_resolver.dart';
import 'package:tentura/features/constellation/ui/widget/constellation_body.dart';
import 'package:tentura/features/constellation/ui/widget/constellation_viewport_overlay.dart';
import 'package:tentura/features/graph/domain/use_case/graph_trust_write_case.dart';
import 'package:tentura/features/graph/ui/bloc/graph_person_context_cubit.dart';
import 'package:tentura/features/people_tags/domain/entity/people_tags_entities.dart';
import 'package:tentura/features/people_tags/domain/use_case/people_tags_case.dart';
import 'package:tentura/ui/bloc/screen_cubit.dart';
import 'package:tentura/ui/l10n/l10n.dart';
import 'package:tentura/ui/test_ids.dart';

import '../../support/fake_people_tags_repository.dart';
import '../../ui/effect/fake_ui_effect_port.dart';
import 'fixtures/constellation_reference_fixture.dart';
import 'fixtures/synthetic_field.dart';

// Colour index 4 for the first own tag, 6 for the second: a person in both
// must take the first (by tag order), never the second.
const _first = PersonTag(
  id: 'T-first',
  name: 'First',
  glyph: 'F',
  color: 4,
  ord: 0,
);
const _second = PersonTag(
  id: 'T-second',
  name: 'Second',
  glyph: 'S',
  color: 6,
  ord: 1,
);

const _firstOnly = 'p2';
const _both = 'p3';
const _secondOnly = 'p4';
const _untagged = 'p5';

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

/// 400 people; p0 and p1 are pinned a hair apart so their tap targets
/// overlap whatever the generated layout does.
ConstellationField _field() {
  final base = syntheticConstellationField(size: 400);
  final projection = base.anchorProjection!;
  ConstellationAnchor pin(String id, double x, double y) => ConstellationAnchor(
    target: ConstellationAnchorTarget.person(id),
    position: ConstellationAnchorPosition(
      xUnits: x,
      yUnits: y,
      coordinateSpaceVersion: 1,
    ),
    revision: projection.revision,
    placedAt: base.loadedAt,
  );
  return base.copyWith(
    anchorProjection: ConstellationAnchorProjection(
      revision: projection.revision,
      anchors: [
        for (final a in projection.anchors)
          if (![
            'p0',
            'p1',
            _firstOnly,
            _both,
            _secondOnly,
            _untagged,
          ].any((id) => a.target == ConstellationAnchorTarget.person(id)))
            a,
        pin('p0', 4, 3),
        pin('p1', 4.5, 3),
        // Near the middle of the viewport, so the nodes are built.
        pin(_firstOnly, -4, -3),
        pin(_both, -3, -3),
        pin(_secondOnly, 3, -3),
        pin(_untagged, 4, -3),
      ],
      pinnedPeers: projection.pinnedPeers,
      pinnedRequests: projection.pinnedRequests,
      supportPeers: const [],
      supportEdges: const [],
      serverFilteredBeaconIds: const [],
      serverFilteredBeaconCount: 0,
    ),
  );
}

/// Graph ids of the people the frame lays out (the field is capped).
List<String> _peopleIn(ConstellationPresentationFrame frame) => [
  for (final id in frame.paintOrder)
    if (id.startsWith('fp:') && id != 'fp:ego') id,
];

Finder _graphNode(String id) => find.byKey(TestIds.key(TestIds.graphNode(id)));

bool _paints(Widget w, bool Function(Color) test) => switch (w) {
  DecoratedBox(:final decoration) =>
    decoration is BoxDecoration &&
        decoration.color != null &&
        test(decoration.color!),
  ColoredBox(:final color) => test(color),
  Material(:final color) => color != null && test(color),
  Container(:final color) => color != null && test(color),
  _ => false,
};

/// Anything painted inside one node in a colour that satisfies [test].
Finder _paintedIn(String id, bool Function(Color) test) => find.descendant(
  of: _graphNode(id),
  matching: find.byWidgetPredicate((w) => _paints(w, test)),
);

Finder _dotOf(String id, Color colour) => _paintedIn(id, (c) => c == colour);

void main() {
  late PeopleTagsTestRig rig;

  setUp(() async {
    rig = await PeopleTagsTestRig.create(
      FakePeopleTagsRepository(
        tagList: [_first, _second],
        memberList: const [
          PersonTagMembers(tagId: 'T-first', personIds: [_firstOnly, _both]),
          PersonTagMembers(tagId: 'T-second', personIds: [_both, _secondOnly]),
        ],
      ),
    );
    GetIt.I.registerSingleton<PeopleTagsCase>(rig.peopleTags);
  });

  tearDown(() async {
    await GetIt.I.reset();
    await rig.dispose();
  });

  Future<(ConstellationCubit, ConstellationPresentationFrameHolder)>
  mountAtScale0_4(WidgetTester tester) async {
    final cubit = await loadReferenceCubit(field: _field());
    final zoom = ConstellationZoomLevelController();
    addTearDown(zoom.dispose);
    addTearDown(cubit.close);
    final lens = ConstellationTagLensCubit(
      ownTagIdsOf: rig.peopleTags.tagsOfPerson,
    );
    addTearDown(lens.close);
    final holder = ConstellationPresentationFrameHolder();
    const size = Size(1200, 900);
    await tester.binding.setSurfaceSize(size);
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
              BlocProvider<ConstellationTagLensCubit>.value(value: lens),
              BlocProvider<GraphPersonContextCubit>(
                create: (_) => _StubContextCubit(),
              ),
              BlocProvider<ScreenCubit>(
                create: (_) => ScreenCubit(FakeUiEffectPort()),
              ),
            ],
            child: ConstellationBody(
              legendExpanded: false,
              onToggleLegend: () {},
              presentationFrameHolder: holder,
            ),
          ),
        ),
      ),
    );
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 400));
    await tester.pumpAndSettle();

    for (var i = 0; i < 60; i++) {
      final scale = cubit.graphController.cameraScale;
      if (scale >= 0.36 && scale <= 0.44) {
        break;
      }
      cubit.graphController.zoomBy(scale > 0.44 ? 0.93 : 1.05);
      await tester.pump();
    }
    await tester.pumpAndSettle();
    final scale = cubit.graphController.cameraScale;
    expect(scale, inInclusiveRange(0.36, 0.44), reason: 'camera at ~0.4');
    return (cubit, holder);
  }

  group('overview map of 400 people at scale 0.4', () {
    testWidgets('draws no label, chip or forced label for anyone', (
      tester,
    ) async {
      final (_, holder) = await mountAtScale0_4(tester);
      final frame = holder.frame!;

      expect(frame.detail, ConstellationDetailLevel.overview);
      expect(frame.labels, isEmpty);
      expect(frame.chips, isEmpty);
      expect(frame.forcedLabels, isEmpty);
      expect(find.text('Person 7'), findsNothing);
      expect(find.text('Request 3'), findsNothing);
      expect(find.textContaining('more'), findsNothing);
    });

    testWidgets('has a tap target of at least the minimum for every person', (
      tester,
    ) async {
      final (_, holder) = await mountAtScale0_4(tester);
      final frame = holder.frame!;

      final people = _peopleIn(frame);
      expect(people.length, greaterThan(100), reason: 'a crowded map');
      for (final id in people) {
        final target = frame.tapTargets[id];
        expect(target, isNotNull, reason: '$id has a tap target');
        expect(
          math.min(target!.width, target.height),
          greaterThanOrEqualTo(kMinInteractiveDimension - 1e-6),
          reason: id,
        );
      }
    });

    testWidgets('draws people as 5 pt dots', (tester) async {
      final (_, holder) = await mountAtScale0_4(tester);
      final frame = holder.frame!;

      for (final id in _peopleIn(frame)) {
        final body = frame.bodies[id]!;
        expect(body.width, closeTo(5, 0.01), reason: id);
        expect(body.height, closeTo(5, 0.01), reason: id);
      }
    });

    testWidgets('colours a dot by the first own tag, grey without a tag', (
      tester,
    ) async {
      await mountAtScale0_4(tester);
      const palette = TenturaTagColors.light;
      final firstAccent = palette.swatches[_first.color].accent;
      final secondAccent = palette.swatches[_second.color].accent;

      expect(_dotOf(_firstOnly, firstAccent), findsWidgets);
      expect(_dotOf(_both, firstAccent), findsWidgets);
      expect(_dotOf(_both, secondAccent), findsNothing);
      expect(_dotOf(_secondOnly, secondAccent), findsWidgets);
      for (final swatch in palette.swatches) {
        expect(_dotOf(_untagged, swatch.accent), findsNothing);
      }
      expect(
        _paintedIn(
          _untagged,
          (c) => HSLColor.fromColor(c).saturation < 0.1 && c.a > 0,
        ),
        findsWidgets,
      );
    });

    testWidgets('a tap between two overlapping dots selects the nearer one', (
      tester,
    ) async {
      final (cubit, holder) = await mountAtScale0_4(tester);
      final origin = tester.getTopLeft(
        find.byType(ConstellationViewportOverlay),
      );

      // Only nodes whose tap target holds the point compete.
      String expectedAt(ConstellationPresentationFrame frame, Offset p) {
        String? id;
        var dist = double.infinity;
        for (final entry in frame.tapTargets.entries) {
          if (!constellationTapTargetContains(entry.value, p)) continue;
          final d = (frame.bodies[entry.key]!.center - p).distance;
          if (d < dist) {
            dist = d;
            id = entry.key;
          }
        }
        return id!;
      }

      for (final t in [0.3, 0.7]) {
        // A tap that opens the panel may pan the camera: read the frame anew.
        final frame = holder.frame!;
        final c0 = frame.bodies['fp:p0']!.center;
        final c1 = frame.bodies['fp:p1']!.center;
        expect((c0 - c1).distance, lessThan(kMinInteractiveDimension));
        final p = c0 + (c1 - c0) * t;
        final want = expectedAt(frame, p);
        cubit.selectPerson(null);
        await tester.pump();

        await tester.tapAt(origin + p);
        await tester.pumpAndSettle();

        expect(
          cubit.state.selectedPersonId,
          want.substring('fp:'.length),
          reason: 't=$t',
        );
      }
    });
  });
}
