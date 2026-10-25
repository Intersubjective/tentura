import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:tentura/features/constellation/domain/constellation_minimap.dart';
import 'package:tentura/features/constellation/domain/entity/constellation_anchor_projection.dart';
import 'package:tentura/features/constellation/domain/entity/constellation_field.dart';
import 'package:tentura/features/constellation/domain/layout/layout_geometry.dart';
import 'package:tentura/features/constellation/ui/bloc/constellation_cubit.dart';
import 'package:tentura/features/constellation/ui/utils/constellation_presentation_frame.dart';
import 'package:tentura/features/constellation/ui/utils/constellation_tap_resolver.dart';
import 'package:tentura_root/domain/constellation/constellation_anchor.dart';

import 'fixtures/constellation_reference_fixture.dart';

const _surface = Size(1200, 900);
const _map = Key('constellation.minimap');
const _frameKey = Key('constellation.minimap.frame');
const _toggle = Key('constellation.minimap.toggle');

/// Eight columns by five rows of people, 500 screen points apart and centred
/// on the viewport, so the whole field is about three viewports wide and the
/// viewport frame sits well inside the minimap. The viewer is the middle.
final _screenPositions = <String, Offset>{
  'ego': const Offset(600, 450),
  for (var i = 0; i < 40; i++)
    'p$i': Offset(600 + (i % 8 - 3.5) * 500, 450 + (i ~/ 8 - 2) * 500),
};

ConstellationField _field(Set<String> people) {
  final peers = [
    for (var i = 0; i < 40; i++)
      if (people.contains('p$i'))
        ConstellationPerson(id: 'p$i', displayName: 'Person $i'),
  ];
  return ConstellationField(
    loadedAt: DateTime.utc(2026, 10, 25),
    context: '',
    peers: peers,
    directContactIds: [for (final p in peers) p.id],
    edges: [
      for (final p in peers)
        ConstellationTrustEdgeEntity(src: 'ego', dst: p.id, tier: 1),
    ],
    anchorProjection: ConstellationAnchorProjection(
      revision: ConstellationAnchorRevision(BigInt.one),
      anchors: const [],
      pinnedPeers: const [],
      pinnedRequests: const [],
      supportPeers: const [],
      supportEdges: const [],
      serverFilteredBeaconIds: const [],
      serverFilteredBeaconCount: 0,
    ),
  );
}

final _everyone = {for (var i = 0; i < 40; i++) 'p$i'};

/// The four corner people alone: they span the same field as everyone, so a
/// minimap fitted to the people draws its dots at the same places.
const _corners = {'p0', 'p7', 'p32', 'p39'};

LPoint _lPoint(Offset o) => (x: o.dx, y: o.dy);

final class _Mounted {
  _Mounted(this.cubit, this.holder, this.worldPeople, this.worldViewer);

  final ConstellationCubit cubit;
  final ConstellationPresentationFrameHolder holder;

  /// Scene position of each person (not the viewer), as displayed.
  final Map<String, Offset> worldPeople;

  /// Scene position of the viewer, as displayed.
  final Offset worldViewer;

  ConstellationMinimapProjection get projection =>
      ConstellationMinimapProjection.fromPoints([
        for (final p in worldPeople.values) _lPoint(p),
      ]);

  /// The part of the scene the camera shows right now.
  LRect get viewportWorld {
    final controller = cubit.graphController;
    final size = controller.viewportSize!;
    final topLeft = controller.viewportLocalToScene(Offset.zero);
    final bottomRight = controller.viewportLocalToScene(
      Offset(size.width, size.height),
    );
    return (
      left: topLeft.dx,
      top: topLeft.dy,
      right: bottomRight.dx,
      bottom: bottomRight.dy,
    );
  }

  Offset get viewportCentreWorld {
    final controller = cubit.graphController;
    final size = controller.viewportSize!;
    return controller.viewportLocalToScene(size.center(Offset.zero));
  }

  /// Mounts the Field at camera [scale] (district 0.45–0.85, overview below
  /// 0.45, close above) with [people] (default everyone) placed at [_screenPositions] and the
  /// viewer at [viewerAt] (default the middle). With
  /// [from], the camera first rests at that scale and then zooms to [scale].
  static Future<_Mounted> mount(
    WidgetTester tester, {
    double scale = 0.6,
    double? from,
    Set<String>? people,
    Offset? viewerAt,
  }) async {
    final cubit = await loadReferenceCubit(field: _field(people ?? _everyone));
    final holder = ConstellationPresentationFrameHolder();
    addTearDown(cubit.close);
    await pumpConstellationBody(
      tester,
      cubit,
      size: _surface,
      locale: const Locale('en'),
      presentationFrameHolder: holder,
      disableAnimations: true,
    );
    await tester.pumpAndSettle();
    final controller = cubit.graphController;
    if (from != null) {
      controller.zoomBy(from / controller.cameraScale);
      await tester.pumpAndSettle();
    }
    controller.zoomBy(scale / controller.cameraScale);
    await tester.pumpAndSettle();
    controller.clearAllPresentationPositions();
    final world = <String, Offset>{};
    late Offset viewer;
    final placed = {
      for (final entry in _screenPositions.entries)
        if (entry.key == 'ego' || (people ?? _everyone).contains(entry.key))
          entry.key: entry.key == 'ego'
              ? (viewerAt ?? entry.value)
              : entry.value,
    };
    for (final entry in placed.entries) {
      final scene = controller.viewportLocalToScene(entry.value);
      controller.beginNodePresentationDragForId('fp:${entry.key}', scene);
      if (entry.key == 'ego') {
        viewer = scene;
      } else {
        world[entry.key] = scene;
      }
    }
    await tester.pumpAndSettle();
    // The minimap may start collapsed or expanded; the checks need it open.
    if (find.byKey(_map).evaluate().isEmpty &&
        find.byKey(_toggle).evaluate().isNotEmpty) {
      await tester.tap(find.byKey(_toggle));
      await tester.pumpAndSettle();
    }
    return _Mounted(cubit, holder, world, viewer);
  }
}

Rect _within(WidgetTester tester, Finder child, Finder parent) =>
    tester.getRect(child).shift(-tester.getTopLeft(parent));

/// The rendered pixels of the screen region around the minimap. Reading
/// pixels keeps the dot checks independent of how the minimap draws them.
final class _Pixels {
  _Pixels(this.bytes, this.width, this.height, this.origin);

  final Uint8List bytes;
  final int width;
  final int height;

  /// Screen position of the captured region's top-left corner.
  final Offset origin;

  /// Captures the outermost repaint boundary that holds the whole minimap,
  /// whatever wrapper the minimap itself uses.
  static Future<_Pixels> capture(WidgetTester tester) async {
    final map = tester.getRect(find.byKey(_map));
    final boundary = find.byType(RepaintBoundary).evaluate().where((e) {
      final box = e.renderObject! as RenderBox;
      return box.attached &&
          (box.localToGlobal(Offset.zero) & box.size)
              .inflate(0.5)
              .contains(
                map.center,
              ) &&
          (box.localToGlobal(Offset.zero) & box.size)
              .inflate(0.5)
              .overlaps(map);
    }).first;
    final render = boundary.renderObject! as RenderRepaintBoundary;
    final origin = render.localToGlobal(Offset.zero);
    final captured = await tester.runAsync(() async {
      final image = await render.toImage();
      final data = await image.toByteData();
      return (image.width, image.height, data!.buffer.asUint8List());
    });
    return _Pixels(captured!.$3, captured.$1, captured.$2, origin);
  }

  List<int> _at(Offset screen) {
    final x = (screen.dx - origin.dx).floor().clamp(0, width - 1);
    final y = (screen.dy - origin.dy).floor().clamp(0, height - 1);
    final i = (y * width + x) * 4;
    return [bytes[i], bytes[i + 1], bytes[i + 2]];
  }

  /// The largest colour difference between this capture and [other] in the
  /// 3 by 3 block around [screen]: only what changed between the two
  /// renders, so a frame stroke or background drawn in both cancels out.
  int changeAround(Offset screen, _Pixels other) {
    var most = 0;
    for (final dx in [-1.0, 0.0, 1.0]) {
      for (final dy in [-1.0, 0.0, 1.0]) {
        final a = _at(screen + Offset(dx, dy));
        final b = other._at(screen + Offset(dx, dy));
        for (var c = 0; c < 3; c++) {
          final diff = (a[c] - b[c]).abs();
          if (diff > most) most = diff;
        }
      }
    }
    return most;
  }
}

void main() {
  for (final (name, scale, from, level) in [
    ('district', 0.6, null, ConstellationDetailLevel.district),
    ('overview', 0.35, null, ConstellationDetailLevel.overview),
    (
      'district after zooming out from close',
      0.6,
      1.2,
      ConstellationDetailLevel.district,
    ),
    (
      'overview after zooming out from close',
      0.35,
      1.2,
      ConstellationDetailLevel.overview,
    ),
  ]) {
    group('minimap at $name level', () {
      Future<_Mounted> mount(
        WidgetTester tester, {
        Set<String>? people,
        Offset? viewerAt,
      }) => _Mounted.mount(
        tester,
        scale: scale,
        from: from,
        people: people,
        viewerAt: viewerAt,
      );

      testWidgets('is a 104 by 104 square', (tester) async {
        final m = await mount(tester);
        expect(m.holder.frame!.detail, level);

        expect(find.byKey(_map), findsOneWidget);
        expect(tester.getSize(find.byKey(_map)), const Size(104, 104));
      });

      testWidgets('draws a dot for each person where the projection puts '
          'them', (tester) async {
        // The same camera and frame render twice: with everyone, and with
        // only the four corner people. What differs is exactly the dots of
        // the people left out, wherever the frame or background ink lies.
        final everyone = await mount(tester);
        final withEveryone = await _Pixels.capture(tester);
        final origin = tester.getTopLeft(find.byKey(_map));
        // The viewer is inside the field's extent, so fitting the projection
        // to the people alone or to the people and the viewer is the same.
        final projection = everyone.projection;
        Offset dotOf(Offset world) {
          final dot = projection.worldToMinimap(_lPoint(world));
          return origin + Offset(dot.x, dot.y);
        }

        final dotted = {
          for (final e in everyone.worldPeople.entries)
            if (!_corners.contains(e.key)) e.key: dotOf(e.value),
        };

        await mount(tester, people: _corners);
        final cornersOnly = await _Pixels.capture(tester);
        expect(tester.getTopLeft(find.byKey(_map)), origin);

        expect(dotted, hasLength(36));
        for (final entry in dotted.entries) {
          expect(
            withEveryone.changeAround(entry.value, cornersOnly),
            greaterThan(20),
            reason: '${entry.key} has no dot at ${entry.value}',
          );
        }
      });

      testWidgets('draws the viewer as a dot where they are', (tester) async {
        final middle = await mount(tester);
        final viewerMiddle = await _Pixels.capture(tester);
        final origin = tester.getTopLeft(find.byKey(_map));
        final projection = middle.projection;
        Offset dotOf(Offset world) {
          final dot = projection.worldToMinimap(_lPoint(world));
          return origin + Offset(dot.x, dot.y);
        }

        // The viewer stands between the people of the middle row; moving
        // them to the free space below changes only the viewer's dot.
        final moved = await mount(tester, viewerAt: const Offset(600, 700));
        final viewerLower = await _Pixels.capture(tester);
        expect(tester.getTopLeft(find.byKey(_map)), origin);

        expect(
          viewerMiddle.changeAround(dotOf(middle.worldViewer), viewerLower),
          greaterThan(20),
          reason: 'no viewer dot where the viewer was',
        );
        expect(
          viewerMiddle.changeAround(dotOf(moved.worldViewer), viewerLower),
          greaterThan(20),
          reason: 'no viewer dot where the viewer is now',
        );
      });

      testWidgets('frames the part of the field the camera shows', (
        tester,
      ) async {
        final m = await mount(tester);

        final expected = m.projection.frameOf(m.viewportWorld);
        final frame = _within(tester, find.byKey(_frameKey), find.byKey(_map));
        expect(frame.left, closeTo(expected.left, 1));
        expect(frame.top, closeTo(expected.top, 1));
        expect(frame.right, closeTo(expected.right, 1));
        expect(frame.bottom, closeTo(expected.bottom, 1));
        // The frame has the proportions of the viewport the camera shows.
        final shown = m.cubit.graphController.viewportSize!;
        expect(
          frame.width / frame.height,
          closeTo(shown.width / shown.height, 0.02),
        );
      });

      testWidgets('moves the frame when the camera pans', (tester) async {
        final m = await mount(tester);
        final before = _within(tester, find.byKey(_frameKey), find.byKey(_map));

        m.cubit.graphController.jumpToPosition(m.worldPeople['p36']!);
        await tester.pumpAndSettle();

        final expected = m.projection.frameOf(m.viewportWorld);
        final after = _within(tester, find.byKey(_frameKey), find.byKey(_map));
        expect(after.left, greaterThan(before.left));
        expect(after.top, greaterThan(before.top));
        expect(after.width, closeTo(before.width, 0.5));
        expect(after.left, closeTo(expected.left, 1));
        expect(after.top, closeTo(expected.top, 1));
      });

      testWidgets('keeps the frame inside the minimap when the camera pans to '
          'the edge of the field', (tester) async {
        final m = await mount(tester);

        // p39 is the farthest person: the viewport reaches past the field.
        m.cubit.graphController.jumpToPosition(m.worldPeople['p39']!);
        await tester.pumpAndSettle();

        final viewport = m.viewportWorld;
        final reachesPast = m.projection.worldToMinimap((
          x: viewport.right,
          y: viewport.bottom,
        ));
        expect(
          reachesPast.x > 104 || reachesPast.y > 104,
          isTrue,
          reason: 'the camera must reach beyond the field for this test',
        );
        final expected = m.projection.frameOf(viewport);
        final frame = _within(tester, find.byKey(_frameKey), find.byKey(_map));
        expect(frame.left, greaterThanOrEqualTo(-0.5));
        expect(frame.top, greaterThanOrEqualTo(-0.5));
        expect(frame.right, lessThanOrEqualTo(104.5));
        expect(frame.bottom, lessThanOrEqualTo(104.5));
        expect(frame.left, closeTo(expected.left, 1));
        expect(frame.top, closeTo(expected.top, 1));
        expect(frame.right, closeTo(expected.right, 1));
        expect(frame.bottom, closeTo(expected.bottom, 1));
      });

      testWidgets('resizes the frame when the camera zooms', (tester) async {
        final m = await mount(tester);
        final before = _within(tester, find.byKey(_frameKey), find.byKey(_map));

        m.cubit.graphController.zoomBy(1.25);
        await tester.pumpAndSettle();

        final expected = m.projection.frameOf(m.viewportWorld);
        final after = _within(tester, find.byKey(_frameKey), find.byKey(_map));
        expect(after.width, closeTo(before.width / 1.25, 0.5));
        expect(after.height, closeTo(before.height / 1.25, 0.5));
        expect(after.width, closeTo(expected.right - expected.left, 1));
      });

      testWidgets('tapping moves the camera to that world point', (
        tester,
      ) async {
        final m = await mount(tester);
        final scaleBefore = m.cubit.graphController.cameraScale;
        const tap = Offset(80, 22);

        await tester.tapAt(tester.getTopLeft(find.byKey(_map)) + tap);
        await tester.pumpAndSettle();

        final world = m.projection.minimapToWorld(_lPoint(tap));
        expect(m.viewportCentreWorld.dx, closeTo(world.x, 1));
        expect(m.viewportCentreWorld.dy, closeTo(world.y, 1));
        expect(m.cubit.graphController.cameraScale, closeTo(scaleBefore, 1e-6));
        final frame = _within(tester, find.byKey(_frameKey), find.byKey(_map));
        expect(frame.center.dx, closeTo(tap.dx, 1));
        expect(frame.center.dy, closeTo(tap.dy, 1));
      });

      testWidgets('tapping a second place moves the camera again', (
        tester,
      ) async {
        final m = await mount(tester);
        final origin = tester.getTopLeft(find.byKey(_map));

        await tester.tapAt(origin + const Offset(80, 22));
        await tester.pumpAndSettle();
        await tester.tapAt(origin + const Offset(20, 90));
        await tester.pumpAndSettle();

        final world = m.projection.minimapToWorld((x: 20, y: 90));
        expect(m.viewportCentreWorld.dx, closeTo(world.x, 1));
        expect(m.viewportCentreWorld.dy, closeTo(world.y, 1));
      });

      testWidgets('collapses to its toggle and expands again', (tester) async {
        final m = await mount(tester);
        expect(find.byKey(_map), findsOneWidget);
        expect(find.byKey(_toggle), findsOneWidget);

        await tester.tap(find.byKey(_toggle));
        await tester.pumpAndSettle();
        expect(find.byKey(_map), findsNothing);
        expect(find.byKey(_frameKey), findsNothing);
        expect(find.byKey(_toggle), findsOneWidget);

        await tester.tap(find.byKey(_toggle));
        await tester.pumpAndSettle();
        expect(find.byKey(_map), findsOneWidget);
        expect(tester.getSize(find.byKey(_map)), const Size(104, 104));
        expect(find.byKey(_frameKey), findsOneWidget);
        final expected = m.projection.frameOf(m.viewportWorld);
        final frame = _within(tester, find.byKey(_frameKey), find.byKey(_map));
        expect(frame.left, closeTo(expected.left, 1));
        expect(frame.top, closeTo(expected.top, 1));
        expect(frame.right, closeTo(expected.right, 1));
        expect(frame.bottom, closeTo(expected.bottom, 1));
      });
    });
  }

  group('minimap by zoom level', () {
    testWidgets('shows neither the minimap nor its toggle at close level', (
      tester,
    ) async {
      final m = await _Mounted.mount(tester, scale: 1.2);
      expect(m.holder.frame!.detail, ConstellationDetailLevel.close);

      expect(find.byKey(_map), findsNothing);
      expect(find.byKey(_frameKey), findsNothing);
      expect(find.byKey(_toggle), findsNothing);
    });

    testWidgets('disappears with its toggle when zooming in to close level', (
      tester,
    ) async {
      final m = await _Mounted.mount(tester);
      expect(find.byKey(_map), findsOneWidget);
      expect(find.byKey(_toggle), findsOneWidget);

      final controller = m.cubit.graphController;
      controller.zoomBy(1.2 / controller.cameraScale);
      await tester.pumpAndSettle();

      expect(find.byKey(_map), findsNothing);
      expect(find.byKey(_toggle), findsNothing);
    });
  });
}
