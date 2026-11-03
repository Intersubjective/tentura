import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:get_it/get_it.dart';
import 'package:tentura/features/constellation/domain/entity/constellation_anchor_projection.dart';
import 'package:tentura/features/constellation/domain/entity/constellation_field.dart';
import 'package:tentura/features/constellation/ui/bloc/constellation_cubit.dart';
import 'package:tentura/features/constellation/ui/utils/constellation_presentation_frame.dart';
import 'package:tentura/features/constellation/ui/utils/constellation_tap_resolver.dart';
import 'package:tentura/features/constellation/ui/widget/constellation_body.dart';
import 'package:tentura/features/constellation/ui/widget/constellation_viewport_overlay.dart';
import 'package:tentura/features/people_tags/domain/entity/people_tags_entities.dart';
import 'package:tentura/features/people_tags/domain/use_case/people_tags_case.dart';
import 'package:tentura_root/domain/constellation/constellation_anchor.dart';

import '../../support/fake_people_tags_repository.dart';
import '../../support/phone_surface.dart';
import 'fixtures/constellation_reference_fixture.dart';

const _neighbours = PersonTag(
  id: 'neighbours',
  name: 'Neighbours',
  glyph: 'N',
  color: 0,
  ord: 0,
);
const _workshop = PersonTag(
  id: 'workshop',
  name: 'Workshop',
  glyph: 'W',
  color: 1,
  ord: 1,
);
const _ego = Offset(540, 600);
const _centres = [
  Offset(180, 180),
  Offset(396, 180),
  Offset(612, 180),
  Offset(828, 180),
];
const _counts = [40, 80, 120, 160];

Map<String, Offset> _positions() {
  final result = <String, Offset>{};
  var person = 0;
  for (var cell = 0; cell < _counts.length; cell++) {
    for (var i = 0; i < _counts[cell]; i++) {
      result['p${person++}'] =
          _centres[cell] + Offset(i.isEven ? -3 : 3, i % 4 < 2 ? -3 : 3);
    }
  }
  return result;
}

List<PersonTagMembers> _memberships({bool tied = false}) => [
  PersonTagMembers(
    tagId: 'neighbours',
    personIds: [
      for (var i = 0; i < (tied ? 40 : 10); i++) 'p$i',
      for (var i = 120; i < 180; i++) 'p$i',
      for (var i = 240; i < 340; i++) 'p$i',
    ],
  ),
  PersonTagMembers(
    tagId: 'workshop',
    personIds: [
      for (var i = 0; i < 40; i++) 'p$i',
      for (var i = 180; i < 240; i++) 'p$i',
      for (var i = 340; i < 400; i++) 'p$i',
    ],
  ),
];

void _expectNoClusterCountLabels(WidgetTester tester) {
  expect(
    find.descendant(
      of: find.byType(ConstellationViewportOverlay),
      matching: find.textContaining(RegExp(r'people|чел\.')),
    ),
    findsNothing,
  );
}

bool _isEgoToCellBundleStroke(_Stroke stroke) {
  if ((stroke.source - _ego).distance > 25) {
    return false;
  }
  for (final centre in _centres) {
    if ((stroke.target - centre).distance < 25) {
      return true;
    }
  }
  return false;
}

final class _Overview {
  _Overview(this.cubit, this.tags, this.holder);
  final ConstellationCubit cubit;
  final PeopleTagsTestRig tags;
  final ConstellationPresentationFrameHolder holder;

  ConstellationPresentationFrame get frame => holder.frame!;

  static Future<_Overview> mount(
    WidgetTester tester, {
    bool tagged = true,
    Size size = const Size(1200, 900),
    Locale locale = const Locale('en'),
    double targetScale = 0.4,
    bool zoomToMinimum = false,
  }) async {
    final members = tagged ? _memberships() : <PersonTagMembers>[];
    final rig = await PeopleTagsTestRig.create(
      FakePeopleTagsRepository(
        tagList: [_neighbours, _workshop],
        memberList: members,
      ),
    );
    GetIt.I.registerSingleton<PeopleTagsCase>(rig.peopleTags);
    final peers = [
      for (var i = 0; i < 400; i++)
        ConstellationPerson(id: 'p$i', displayName: 'Person $i'),
    ];
    final revision = ConstellationAnchorRevision(BigInt.one);
    final field = ConstellationField(
      loadedAt: DateTime.utc(2026, 10, 25),
      context: '',
      peers: peers,
      directContactIds: [for (final p in peers) p.id],
      edges: [
        const ConstellationTrustEdgeEntity(src: 'ego', dst: 'p0', tier: 1),
        for (var i = 1; i < 400; i++)
          ConstellationTrustEdgeEntity(src: 'p0', dst: 'p$i', tier: 1),
      ],
      anchorProjection: ConstellationAnchorProjection(
        revision: revision,
        anchors: [
          for (var i = 0; i < 400; i++)
            ConstellationAnchor(
              target: ConstellationAnchorTarget.person('p$i'),
              position: ConstellationAnchorPosition(
                xUnits: (i % 20 - 10) / 2,
                yUnits: (i ~/ 20 - 10) / 2,
                coordinateSpaceVersion: 1,
              ),
              revision: revision,
              placedAt: DateTime.utc(2026, 10, 25),
            ),
        ],
        pinnedPeers: peers,
        pinnedRequests: const [],
        supportPeers: const [],
        supportEdges: const [],
        serverFilteredBeaconIds: const [],
        serverFilteredBeaconCount: 0,
      ),
    );
    final cubit = await loadReferenceCubit(field: field);
    final holder = ConstellationPresentationFrameHolder();
    final result = _Overview(cubit, rig, holder);
    addTearDown(() async {
      await cubit.close();
      await GetIt.I.reset();
      await rig.dispose();
    });
    await pumpConstellationBody(
      tester,
      cubit,
      size: size,
      locale: locale,
      presentationFrameHolder: holder,
      disableAnimations: true,
    );
    await tester.pumpAndSettle();
    final controller = cubit.graphController;
    if (zoomToMinimum) {
      for (var i = 0; i < 80; i++) {
        controller.zoomBy(0.9);
        await tester.pump();
      }
      await tester.pumpAndSettle();
    } else {
      controller.zoomBy(targetScale / controller.cameraScale);
      await tester.pumpAndSettle();
    }
    await result.place(tester, _positions());
    return result;
  }

  Future<void> place(WidgetTester tester, Map<String, Offset> positions) async {
    final controller = cubit.graphController..clearAllPresentationPositions();
    for (final entry in {'ego': _ego, ...positions}.entries) {
      controller.beginNodePresentationDragForId(
        'fp:${entry.key}',
        controller.viewportLocalToScene(entry.value),
      );
    }
    await tester.pumpAndSettle();
    expect(frame.detail, ConstellationDetailLevel.overview);
    expect(
      frame.bodies.keys.where((id) => id.startsWith('fp:') && id != 'fp:ego'),
      hasLength(400),
    );
    expect(frame.labels, isEmpty, reason: 'individual names remain hidden');
    expect(frame.chips, isEmpty);
    for (final entry in positions.entries) {
      expect(
        (frame.bodies['fp:${entry.key}']!.center - entry.value).distance,
        lessThan(0.01),
      );
    }
    _expectNoClusterCountLabels(tester);
  }
}

typedef _Stroke = ({Offset source, Offset target, double width});

final class _StrokeCanvas implements Canvas {
  _StrokeCanvas(this.outer, this.origin) {
    _canvas = Canvas(_recorder);
  }
  final Matrix4 outer;
  final Offset origin;
  final _recorder = ui.PictureRecorder();
  late final Canvas _canvas;
  final strokes = <_Stroke>[];

  void _record(Offset a, Offset b, Paint paint) {
    if (paint.style != PaintingStyle.stroke || paint.color.a == 0) return;
    final matrix = outer.multiplied(
      Matrix4.fromFloat64List(_canvas.getTransform()),
    );
    final screenScale =
        (MatrixUtils.transformPoint(matrix, const Offset(1, 0)) -
                MatrixUtils.transformPoint(matrix, Offset.zero))
            .distance;
    strokes.add((
      source: MatrixUtils.transformPoint(matrix, a) - origin,
      target: MatrixUtils.transformPoint(matrix, b) - origin,
      width: paint.strokeWidth * screenScale,
    ));
  }

  @override
  void drawLine(Offset a, Offset b, Paint paint) => _record(a, b, paint);
  @override
  void drawPath(Path path, Paint paint) {
    final metrics = path.computeMetrics().toList();
    if (metrics.isEmpty) return;
    _record(
      metrics.first.getTangentForOffset(0)!.position,
      metrics.last.getTangentForOffset(metrics.last.length)!.position,
      paint,
    );
  }

  @override
  void save() => _canvas.save();
  @override
  void restore() => _canvas.restore();
  @override
  void translate(double dx, double dy) => _canvas.translate(dx, dy);
  @override
  void scale(double sx, [double? sy]) => _canvas.scale(sx, sy);
  @override
  void rotate(double radians) => _canvas.rotate(radians);
  @override
  void transform(Float64List matrix4) => _canvas.transform(matrix4);
  @override
  Float64List getTransform() => _canvas.getTransform();
  @override
  int getSaveCount() => _canvas.getSaveCount();
  @override
  dynamic noSuchMethod(Invocation invocation) => null;

  void dispose() => _recorder.endRecording().dispose();
}

List<_Stroke> _paintedStrokes(WidgetTester tester) {
  final origin = tester.getTopLeft(find.byType(ConstellationViewportOverlay));
  final strokes = <_Stroke>[];
  final painters = find.descendant(
    of: find.byType(ConstellationBody),
    matching: find.byType(CustomPaint),
  );
  for (final element in painters.evaluate()) {
    final widget = element.widget as CustomPaint;
    final box = element.renderObject! as RenderBox;
    final canvas = _StrokeCanvas(box.getTransformTo(null), origin);
    try {
      widget.painter?.paint(canvas, box.size);
      widget.foregroundPainter?.paint(canvas, box.size);
      strokes.addAll(canvas.strokes);
    } finally {
      canvas.dispose();
    }
  }
  return strokes;
}

void main() {
  group('Overview screen-grid presentation', () {
    testWidgets('at overview zoom paints no ego-to-cell bundle strokes', (
      tester,
    ) async {
      await _Overview.mount(tester);
      final bundleStrokes = _paintedStrokes(
        tester,
      ).where(_isEgoToCellBundleStroke);
      expect(
        bundleStrokes,
        isEmpty,
        reason: 'overview must not draw ego-to-cell edge bundles',
      );
    });

    testWidgets('overview still draws people as fixed-size dots', (
      tester,
    ) async {
      final overview = await _Overview.mount(tester);
      final sample = ['fp:p0', 'fp:p50', 'fp:p399'];
      for (final id in sample) {
        final body = overview.frame.bodies[id]!;
        expect(body.width, closeTo(5, 0.01), reason: id);
        expect(body.height, closeTo(5, 0.01), reason: id);
      }
    });

    testWidgets('district zoom still paints trust edges between nodes', (
      tester,
    ) async {
      final overview = await _Overview.mount(tester);
      expect(
        _paintedStrokes(tester).where(_isEgoToCellBundleStroke),
        isEmpty,
      );
      overview.cubit.graphController.zoomBy(
        kConstellationDistrictDetailScale /
            overview.cubit.graphController.cameraScale *
            1.05,
      );
      await tester.pumpAndSettle();
      expect(
        overview.holder.frame!.detail,
        ConstellationDetailLevel.district,
      );
      final strokes = _paintedStrokes(tester);
      expect(strokes, isNotEmpty, reason: 'district keeps per-edge rendering');
    });

    testWidgets(
      '375×667 RU at minimum zoom: overview dots, no bundle strokes',
      (
        tester,
      ) async {
        await usePhoneSurface(tester);
        final overview = await _Overview.mount(
          tester,
          size: kPhoneSurface,
          locale: const Locale('ru'),
          zoomToMinimum: true,
        );
        expect(
          overview.cubit.graphController.cameraScale,
          lessThan(kConstellationDistrictDetailScale),
        );
        expect(overview.frame.detail, ConstellationDetailLevel.overview);
        expect(
          _paintedStrokes(tester).where(_isEgoToCellBundleStroke),
          isEmpty,
        );
        expect(overview.frame.bodies['fp:p0']!.width, closeTo(5, 0.01));
        _expectNoClusterCountLabels(tester);
      },
    );
  });
}
